{
  pkgs,
  lib,
  self,
}:
let
  c = self.nixosConfigurations.nas.config;
  h = c.home-manager.users.tom;
  client = self.nixosConfigurations.client.config.home-manager.users.tom;
  # Inspect the actual production profiles after the rename stack lands.
  compute = self.nixosConfigurations.strix-coordinator.config;
  nonBrainConfigs = map (name: self.nixosConfigurations.${name}.config) [
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
assert
  c.boot.kernelPackages.kernel.version
  == self.nixosConfigurations.strix-coordinator.config.boot.kernelPackages.kernel.version;
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
    80
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
  c.services.atuin.package.version == self.nixosConfigurations.strix-coordinator.pkgs.atuin.version;
assert client.programs.atuin.settings.sync_address == "http://nas:27321";
# T-55: the NAS serves the seats' Atuin sync, but its own home has no Atuin
# client, no fish integration and no key seed (Atuin is on its way out).
assert client.programs.atuin.enable;
assert !h.programs.atuin.enable;
assert !(builtins.any (p: lib.getName p == "atuin") h.home.packages);
# userActivationScripts applies to one combined `script`, so match its text.
assert !(lib.hasInfix "/.local/share/atuin/key" c.system.userActivationScripts.script);
assert lib.hasInfix "/.local/share/atuin/key"
  self.nixosConfigurations.client.config.system.userActivationScripts.script;
# The NAS brain owns the restored executor; compute/client retain no executor
# units or scheduler credentials. Scope admission before touching old queues.
assert c.services.substrate.puller.enable;
assert c.services.substrate.pusher.enable;
assert c.systemd.user.services ? substrate-puller;
assert c.systemd.user.services ? substrate-pusher;
assert
  c.services.substrate.puller.sessionScope == [
    {
      project = "dotfiles";
      thread = "T-69";
    }
  ];
assert c.services.substrate.puller.defaultModel == "qwen3.8-flash-next";
assert c.services.substrate.puller.runtimes.default == "gufo";
assert c.services.substrate.puller.runtimes.runtime.gufo.harness == "dsh";
assert c.services.substrate.puller.runtimes.runtime.gufo.provider == "gufo";
assert builtins.all
  (name: c.age.secrets.${name}.owner == "tom" && c.age.secrets.${name}.mode == "0400")
  [
    "substrate-floor-token"
    "substrate-link-token-strix"
  ];
assert
  c.systemd.user.services.substrate-puller.serviceConfig.LoadCredential == [
    "floor-token:${c.age.secrets.substrate-floor-token.path}"
    "link-token:${c.age.secrets.substrate-link-token-strix.path}"
  ];
assert
  c.systemd.user.services.substrate-pusher.serviceConfig.LoadCredential == [
    "floor-token:${c.age.secrets.substrate-floor-token.path}"
  ];
assert builtins.all (
  cfg:
  !(cfg.services.substrate.puller.enable or false)
  && !(cfg.services.substrate.pusher.enable or false)
  && !(cfg.systemd.user.services ? substrate-puller)
  && !(cfg.systemd.user.services ? substrate-pusher)
  && !(cfg.age.secrets ? substrate-floor-token)
  && !(cfg.age.secrets ? substrate-link-token-strix)
) nonBrainConfigs;
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
assert builtins.all (name: name == "gufo-tp2-control-token") (
  builtins.attrNames compute.age.secrets
);
assert builtins.all (
  name: builtins.elem registry.nas.hostKey recipients."secrets/${name}.age".publicKeys
) toNas;
assert builtins.all (r: !(builtins.elem registry.strix-coordinator.hostKey r.publicKeys)) (
  builtins.attrValues (builtins.removeAttrs recipients [ "secrets/gufo-tp2-control-token.age" ])
);
# The unfilled private source must block the real toplevel. This check does
# not bypass that assertion or pretend the private source has been built.
assert builtins.any (
  a: !a.assertion && lib.hasPrefix "TODO(Tom): private fork rev" a.message
) unfilled.assertions;
pkgs.runCommand "nas-agent-host" { } ''touch "$out"''
