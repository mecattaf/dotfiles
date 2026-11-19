# Domicile owns panel behavior; closing the lid never suspends this seat.
# F10 controls both panel backlights through the shell.
{
  services.logind.settings.Login = {
    HandleLidSwitch = "ignore";
    HandleLidSwitchDocked = "ignore";
    HandleLidSwitchExternalPower = "ignore";
  };
}
