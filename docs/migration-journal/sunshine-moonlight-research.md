# Sunshine + Moonlight on headless NixOS + niri (worker / AMD Strix Halo gfx1151)

Research harvest (2026-06-20) for the **worker** host (headless AMD Strix Halo, no
monitor). Feeds task #7. The worker real-boot is NOT this session's goal (Duo flash
is), but this is the design to implement.

## The crux: headless display (status 2026-06-20)
The clean answer is **niri PR #3800 (willybarret) — DYNAMIC virtual outputs**
(`niri msg create-virtual-output --name <n> --width W --height H --refresh-rate F` +
`remove-virtual-output`). Sunshine creates the VD on stream-start, sized to the Moonlight
client, via per-app **prep-commands** (`do`/`undo`), and removes it on disconnect. No
monitor, no EDID. Community reports it "works great."

**BUT: deferred until the PR merges.** We do NOT pin an unmerged PR in committed config —
building niri from `pull/3800/head` proved flaky (a clean rebuild failed with exit 2). So
`hosts/worker/sunshine.nix` uses **stock niri** for now and configures only the stable
pieces (Sunshine service, uinput, VA-API, greetd autologin). Revisit the virtual-output
approach when #3800 lands in niri / niri-flake — at that point: build the PR niri (override
`src` + `cargoDeps` — the prefetched hashes are recorded in this repo's git history at
commit `a373d99`), set it as the worker's `programs.niri.package`, add the Sunshine app
prep-cmd, and pin `output_name = "sunshine"`.

**Interim headless options (until #3800):** fake a connector so niri lights an output —
a ~$8 HDMI/DP **EDID dummy dongle** (zero config), OR kernel-injected EDID
(`drm.edid_firmware=<conn>:edid/blob.bin` + `video=<conn>:e`, blob via `hardware.firmware`;
needs the real connector name from `niri msg outputs`). VKMS/EVDI as primary output is
unproven for niri.

⚠️ **Runtime gotchas to resolve on real hardware** (PR #3800 thread, for when it's used):
env-var expansion of `${SUNSHINE_CLIENT_*}` into the prep-cmd (seen logged verbatim by
some), and the stream targeting the VD not a real connector (`output_name` is the fix).

## Capture + encode
- `services.sunshine` exists (nixpkgs PR #294641). Runs as a **systemd USER unit**.
  Options: `enable, openFirewall, capSysAdmin, autoStart, settings, applications`.
- **`capture = "wlr"`** — niri implements wlr-screencopy via Smithay, so Sunshine's
  wlroots path binds without a wlroots compositor. Fallback `capture = "kms"` (needs
  `capSysAdmin=true`) if wlr output is garbled (open 2025 XR30-modifier bugs #4050/#3996).
- **AMD encode = VAAPI** (`h264_vaapi`/`hevc_vaapi`/AV1 on VCN4) via Mesa radeonsi.
  gfx1151 (RDNA3.5) needs **recent Mesa (25.x) + LLVM 20+** — fine on nixos-unstable.
  `encoder = "vaapi"`, `encoder = "software"` as last resort. Verify with `vainfo`.
  ⚠️ Mesa↔Sunshine VAAPI coupling is moving (segfaults on some Mesa/RDNA); pin if needed.
- Ports: TCP 47984/47989/47990/48010, UDP 47998-48000 + 8000-8010. Web UI/pair: `:47990`.

## Session + input
- **greetd autologin → niri** (`settings.initial_session` = passwordless), +
  `systemd.user.services.niri.enableDefaultPath = false` (documented PATH gotcha).
- Input injection via **uinput**: `hardware.uinput.enable = true`; user in `uinput`+`input`.
- `hardware.graphics.enable` + `libva`/`libva-utils`. `capSysAdmin=true` for Wayland capture.
- Client: `pkgs.moonlight-qt`; pair via PIN at `https://<host>:47990`.

## Draft module → put in `hosts/worker/sunshine.nix` (when task #7 lands)
```nix
{ config, pkgs, lib, ... }:
let user = "tom"; in {
  programs.niri.enable = true;
  services.greetd = {
    enable = true;
    settings.initial_session = {
      command = "${config.programs.niri.package}/bin/niri-session";
      user = user;
    };
  };
  systemd.user.services.niri.enableDefaultPath = false;
  # fake a connector (Option B) — ship a real EDID blob at ./edid/headless-1080p.bin
  hardware.firmware = [ (pkgs.runCommand "edid-fw" {} ''
    mkdir -p $out/lib/firmware/edid
    cp ${./edid/headless-1080p.bin} $out/lib/firmware/edid/headless-1080p.bin
  '') ];
  boot.kernelParams = [ "drm.edid_firmware=DP-1:edid/headless-1080p.bin" "video=DP-1:e" ];
  hardware.graphics = { enable = true; extraPackages = with pkgs; [ libva libva-utils ]; };
  hardware.uinput.enable = true;
  users.users.${user}.extraGroups = [ "uinput" "input" "video" "render" ];
  services.sunshine = {
    enable = true; autoStart = true; capSysAdmin = true; openFirewall = true;
    settings = { capture = "wlr"; encoder = "vaapi"; };
  };
}
```

## Biggest unknowns to validate on real hardware
1. Does gfx1151 connector + EDID injection give niri a usable output?
2. Does `capture=wlr` bind cleanly to niri's Smithay screencopy (XR30 bug)?
3. Exact Mesa version for stable VAAPI encode on gfx1151 + Sunshine.

**No documented niri+Sunshine+headless+AMD writeup exists** — closest is
`daaaaan/sunshine-headless-sway` (Sway) + Arch virtual-display guides. This combo is
**partly unproven — flagged.**
