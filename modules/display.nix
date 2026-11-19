{ lib, ... }:
# The client is the Domicile physical seat; NAS and compute are headless.
# modules/common.nix derives greetd from this option.
{
  options.myDisplay = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether this host runs a physical desktop and greeter.";
    };
  };
}
