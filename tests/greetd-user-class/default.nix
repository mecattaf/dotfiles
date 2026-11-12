# #734: on the client seat Domicile runs in a user-class logind session
# after boot, after `systemctl restart greetd` and after the desktop exits.
#
# One VM with greetd built from the client's own greetd values: its runfile,
# RuntimeDirectory, Restart, RestartSec and the exact guard binary. Domicile
# and the login shell are stubs that log their logind session class. Steps:
# boot, greetd restart, two desktop exits (each a user-class start through the
# handoff), then a third exit trips the guard (three starts within 120 s) and
# opens the rescue shell, the only greeter-class session.
{ pkgs, client }:
let
  g = client.services.greetd;
  svc = client.systemd.services.greetd.serviceConfig;
  guard = builtins.head (pkgs.lib.splitString " " g.settings.initial_session.command);
  stub =
    name:
    pkgs.writeShellScript "stub-${name}" ''
      class=$(${pkgs.systemd}/bin/loginctl show-session "$XDG_SESSION_ID" -p Class --value)
      echo "${name} $class $XDG_SESSION_ID" >> /tmp/greetd-log
      while :; do ${pkgs.coreutils}/bin/sleep 1; done
    '';
in
pkgs.testers.runNixOSTest {
  name = "greetd-user-class";
  nodes.machine = {
    users.users.tom.isNormalUser = true;
    services.greetd = {
      enable = true;
      inherit (g) restart;
      settings = {
        general.runfile = g.settings.general.runfile;
        initial_session = {
          command = "${guard} ${stub "session"} ${stub "rescue"} -l";
          user = "tom";
        };
        default_session = {
          command = "${guard} --handoff ${stub "rescue"} -l";
          user = "tom";
        };
      };
    };
    systemd.services.greetd.serviceConfig = {
      inherit (svc) RuntimeDirectory RestartSec;
    };
  };
  testScript = ''
    def log():
        return machine.succeed("cat /tmp/greetd-log").split("\n")

    def classes(n):
        machine.wait_until_succeeds(f"test $(wc -l < /tmp/greetd-log) -ge {n}", timeout=60)
        lines = [l.split()[:2] for l in log() if l]
        print(lines)
        return lines

    machine.wait_for_unit("greetd.service")
    assert classes(1) == [["session", "user"]]

    machine.succeed("systemctl restart greetd")
    assert classes(2) == [["session", "user"]] * 2

    machine.succeed("pkill -f stub-session")
    assert classes(3) == [["session", "user"]] * 3
    assert machine.succeed("systemctl show greetd -p NRestarts --value").strip() == "1"

    # Third start inside the window: the next exit opens the rescue shell.
    machine.succeed("pkill -f stub-session")
    assert classes(4) == [["session", "user"]] * 3 + [["rescue", "greeter"]]
    machine.succeed("systemctl is-active greetd")
  '';
}
