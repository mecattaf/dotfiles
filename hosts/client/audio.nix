{ pkgs, ... }:
# USB camera microphone wins over the laptop mic. F9 resolves the same
# preference on every selection, including camera reconnects. If hardware
# capture becomes silent, inspect `amixer -c Pro sget Mic`: this camera has
# previously reset its ALSA capture gain to zero despite a nonzero wpctl level.
{
  services.pipewire.wireplumber.extraConfig."51-client-default-source" = {
    "monitor.alsa.rules" = [
      {
        matches = [
          { "node.name" = "~alsa_input\\.usb-.*iContact_Camera_Pro.*"; }
        ];
        actions.update-props."priority.session" = 3000;
      }
    ];
  };
  environment.systemPackages = [ pkgs.alsa-utils ];
}
