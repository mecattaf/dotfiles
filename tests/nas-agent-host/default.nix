{
  pkgs,
  lib,
  self,
}:
let
  c = self.nixosConfigurations.nas.config;
  h = c.home-manager.users.tom;
  client = self.nixosConfigurations.client.config.home-manager.users.tom;
  # Evaluate a future compute role without importing NAS-only declarations.
  compute =
    (self.nixosConfigurations.strix.extendModules {
      modules = [ { myFleet.roles = lib.mkForce [ "compute" ]; } ];
    }).config;
  # Before the host-rename stack lands, project the existing Strix module
  # into each target's compute role. Once present, assert the real profiles.
  nonBrainConfigs =
    map
      (
        name:
        if builtins.hasAttr name self.nixosConfigurations then
          self.nixosConfigurations.${name}.config
        else
          (self.nixosConfigurations.strix.extendModules {
            modules = [
              {
                networking.hostName = lib.mkForce name;
                myFleet.roles = lib.mkForce [ "compute" ];
              }
            ];
          }).config
      )
      [
        "strix-coordinator"
        "strix-worker"
        "client"
      ];
  dshPackages = home: builtins.filter (p: lib.getName p == "dsh") home.home.packages;
  # Assert the refusal with an explicitly unfilled fixture so this check
  # still passes after Tom supplies the production source pin and hashes.
  unfilled =
    (self.nixosConfigurations.nas.extendModules {
      modules = [
        {
          services.herdr-web-ui = {
            revision = lib.mkForce "TODO-private-fork-rev";
            sourceHash = lib.mkForce lib.fakeHash;
            depsHash = lib.mkForce lib.fakeHash;
          };
        }
      ];
    }).config;
  recipients = import ../../secrets.nix;
  registry = import ../../modules/mesh-registry.nix;
  toNas = [
    "atuin-key"
    "ssh-user-key"
    "tom-password-hash"
    "gh-hosts"
    "wrangler-config"
    "cloudflare-api-token"
    "codex-auth"
    "navidrome-credentials"
    "immich-api-key"
    "soundcloud-cookies"
    "youtube-music-cookies"
    "huggingface-token"
    "qwencloud-token"
    "openrouter-token"
    "printer-admin"
    "atticd-server-token"
    "substrate-floor-token"
    "substrate-link-token-strix"
  ];
  helperNames = cfg: builtins.attrNames cfg.home.file.".local/bin".source.passthru.entries;
in
assert
  c.myFleet.roles == [
    "router"
    "brain"
  ];
assert c.users.users.tom.linger;
assert c.zramSwap.memoryMax == 10 * 1024 * 1024 * 1024;
assert c.boot.kernelPackages.kernel.version == "7.2.10";
assert h.home.enableNixpkgsReleaseCheck;
assert h.home.version.release == "26.05";
assert !h.rawDotfiles.inStore;
assert h.rawDotfiles.repoDir == "/home/tom/mecattaf/dotfiles";
# dsh, including all Nix-pinned plugins, follows the NAS brain and its key.
assert h.programs.dsh.enable;
assert map (p: p.qwenKeyFile or null) (dshPackages h) == [ c.age.secrets.qwencloud-token.path ];
assert h.home.file ? ".agents/AGENTS.md";
assert builtins.all (
  cfg:
  let
    home = cfg.home-manager.users.tom;
  in
  !home.programs.dsh.enable
  && dshPackages home == [ ]
  && !(home.home.file ? ".agents/AGENTS.md")
  && !(cfg.age.secrets ? qwencloud-token)
) nonBrainConfigs;
assert !h.gtk.enable && !h.programs.obs-studio.enable;
assert !(h.xdg.configFile ? "sway-local.conf");
assert !(h.systemd.user.services ? vicinae);
assert !(h.home.file ? ".pi/agent/models.json");
assert !builtins.any (p: lib.getName p == "call-diarize") h.home.packages;
assert h.systemd.user.services.herdr.Unit.X-SwitchMethod == "keep-old";
assert h.systemd.user.services.herdr.Service.OOMPolicy == "continue";
assert h.systemd.user.services.herdr.Service.ManagedOOMPreference == "omit";
assert !(h.systemd.user.services.herdr.Unit ? PartOf);
assert c.systemd.services."user@".serviceConfig.ManagedOOMPreference == "omit";
assert builtins.all
  (
    name:
    c.systemd.services.${name}.serviceConfig.OOMScoreAdjust == -900
    && c.systemd.services.${name}.serviceConfig ? MemoryMin
  )
  [
    "dnsmasq"
    "adguardhome"
    "tailscaled"
    "sshd@"
  ];
assert c.services.openssh.startWhenNeeded;
assert !(c.systemd.services ? sshd);
assert c.systemd.services ? herdr-web-ui-serve;
assert builtins.elem "HOST=127.0.0.1" h.systemd.user.services.herdr-web-ui.Service.Environment;
assert !(builtins.elem "tailscale0" c.networking.firewall.trustedInterfaces);
assert
  lib.sort builtins.lessThan c.networking.firewall.interfaces.tailscale0.allowedTCPPorts == [
    22
    53
    443
    2283
    4533
    27321
    32400
  ];
assert lib.hasInfix "10.42.0.16 tcp dport 22 accept" c.networking.firewall.extraInputRules;
assert c.services.atuin.enable;
assert h.programs.atuin.package.version == c.services.atuin.package.version;
assert
  c.services.atuin.package.version
  == self.nixosConfigurations.strix.config.services.atuin.package.version;
assert client.programs.atuin.settings.sync_address == "http://nas:27321";
assert !(c.systemd.user.services ? substrate-puller);
assert !(c.systemd.user.services ? substrate-pusher);
assert !(c.age.secrets ? substrate-floor-token);
assert h.home.file ? ".local/state/agency/crm/node";
assert
  toString h.home.file.".local/bin".source == toString (h.lib.rawDotfiles.link "dot_local/bin");
assert builtins.all (name: !(builtins.elem name (helperNames client))) [
  "mail"
  "crm"
  "project"
];
assert builtins.all (name: !(builtins.elem name (helperNames compute.home-manager.users.tom))) [
  "mail"
  "crm"
  "project"
];
assert c.systemd.services."user@".overrideStrategy == "asDropin";
assert !(client.home.file ? ".local/state/agency/crm/node");
assert builtins.all (name: h.home.file ? ${name}) [
  ".claude/skills"
  ".claude-work/skills"
];
assert builtins.all (name: c.age.secrets ? ${name}) [
  "ssh-user-key"
  "atuin-key"
  "tom-password-hash"
  "codex-auth"
];
assert compute.age.secrets == { };
assert builtins.all (
  name: builtins.elem registry.nas.hostKey recipients."secrets/${name}.age".publicKeys
) toNas;
assert builtins.all (r: !(builtins.elem registry.strix.hostKey r.publicKeys)) (
  builtins.attrValues recipients
);
# The unfilled private source must block the real toplevel. This check does
# not bypass that assertion or pretend the private source has been built.
assert builtins.any (
  a: !a.assertion && lib.hasPrefix "TODO(Tom): private fork rev" a.message
) unfilled.assertions;
pkgs.runCommand "nas-agent-host" { } ''touch "$out"''
