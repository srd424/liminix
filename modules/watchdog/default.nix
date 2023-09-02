{ lib, pkgs, config, ...}:
let
  inherit (lib) mkOption types;
  inherit (pkgs) liminix;
in
{
  options = {
    system.service.watchdog =  mkOption {
      type = liminix.lib.types.serviceDefn;
    };
  };
  config.system.service.watchdog = liminix.callService ./watchdog.nix {
    watched = mkOption {
      description = "services to watch";
      type = types.listOf liminix.lib.types.service;
    };
    headStart = mkOption {
      description = "delay in seconds before watchdog starts checking service health";
      default = 60;
      type = types.int;
    };
  };
  config.kernel.config.WATCHDOG = "y";
}
