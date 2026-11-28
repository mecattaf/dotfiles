{
  inputs,
  lib,
  osConfig,
  ...
}:
# The factory floor (`agency`, github.com/agency-agency/agency): a Cordis
# orchestrator on herdr-core, the floor that replaces the retired dshd
# instance `floor` (2026-11-26). The repository owns the unit: this file
# imports its Home Manager module (inputs.agency, pinned by rev in flake.nix)
# and sets only what is Tom's. The module declares factory-floor.service in
# store mode: the unit runs the package's bin/agency-service, nothing is built
# in a checkout, and `agency` (with `floor-say`) lands on PATH.
#
# Every path keeps the value the old local-checkout unit had (state
# ~/.agency/state/master/factory-floor, work ~/.local/state/factory-floor,
# config ~/.config/agency/factory-floor/floor.jsonc, panel 127.0.0.1:3082), so
# the switch moves the program and not the data: the floor opens the same
# store and adopts the same workers. docs/factory-floor.md has the runbook.
#
# BUNDLES. The module writes the profile's package.json from the store before
# every start, so this list owns it: bundle-core first (the core's command
# table, socket and agencies; the floor refuses to start without it), then the
# three bundles the live profile already listed.
#
# SCHEDULED SOURCE OFF. The new floor's scheduled Source reads the heartbeat's
# inbox (~/.agency/state/master/inbox/scheduled) by default and would launch
# the items waiting there. The overlay turns it off; flipping it on is a
# separate step of Tom's (docs/factory-floor.md "The flips").
#
# STILL NOT AUTOSTARTED, NO WAKE (2026-11-26): autostart and heartbeatWake keep
# the module's defaults (false). X-SwitchMethod=keep-old: a switch never
# restarts a running floor; restart it by hand.
#
# `checkout` and `documentation` keep the module's defaults
# (~/agency/agency-agency/agency and the agency repository's service README).
{
  imports = [ inputs.agency.homeManagerModules.default ];

  config.services.factory-floor = {
    enable = lib.mkDefault (osConfig.myFleet.has "brain");
    bundles = [
      "@agency/bundle-core"
      "@factory-floor/bundle-base"
      "@factory-floor/bundle-web"
      "@factory-floor/bundle-chat"
    ];
    overlay = [
      {
        id = "source-scheduled";
        disabled = true;
      }
    ];
  };
}
