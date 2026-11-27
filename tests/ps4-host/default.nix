{ pkgs, self }:
let
  host = self.nixosConfigurations.ps4-dummy.config;
  suite =
    (self.nixosConfigurations.ps4-dummy.extendModules {
      modules = [ { myPs4.fleetSuite.enable = true; } ];
    }).config;
in
assert host.myHeadless.enable && !host.myDisplay.enable;
assert host.networking.firewall.enable && host.services.tailscale.enable;
assert !host.boot.kernel.enable && !host.boot.initrd.enable;
assert !host.boot.loader.systemd-boot.enable && !host.boot.loader.grub.enable;
assert host.nix.settings.max-jobs == 0 && host.nix.buildMachines == [ ];
assert !host.zramSwap.enable && host.swapDevices == [ ];
assert host.myPs4.gpuBackingLimitMiB == 7424;
assert host.myFleet.roles == [ "compute" ] && !host.mySecrets.enable;
assert !host.home-manager.users.tom.programs.herdrCore.enable;
assert suite.home-manager.users.tom.programs.herdrCore.enable;
assert !suite.home-manager.users.tom.programs.herdrCore.autoStart;
assert !suite.myDisplay.enable && !suite.services.greetd.enable;
assert suite.users.users.tom.linger;
pkgs.runCommand "ps4-host-checks" { nativeBuildInputs = [ pkgs.python3 ]; } ''
  export PYTHONDONTWRITEBYTECODE=1
  python3 ${./test_checks.py} ${../../pkgs/ps4-host-check/check.py}
  touch "$out"
''
