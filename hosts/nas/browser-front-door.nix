{ ... }:
{
  # The NAS fronts https://browser.internal; the desktop stays on strix-coordinator.
  imports = [ ../../modules/browser-desktop.nix ];
  services.browser-desktop.frontDoor.enable = true;
}
