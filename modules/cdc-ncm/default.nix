{ config, pkgs, lib, ... }:
let
  inherit (pkgs) liminix;
  inherit (lib) mkOption types;
  svc = config.system.service;
in {
  options = {
    system.service.wwan = mkOption {
      type = liminix.lib.types.serviceDefn;
    };
  };
  config = {
    kernel.config = {
      USB_NET_HUAWEI_CDC_NCM = "y";
      USB_USBNET = "y";
      USB_SERIAL = "y";
      USB_SERIAL_OPTION = "y";
    };

    # https://www.0xf8.org/2017/01/flashing-a-huawei-e3372h-4g-lte-stick-from-hilink-to-stick-mode/
    system.service.wwan = config.system.callService ./wwan.nix {
      apn = mkOption { type = types.str; };
      username = mkOption { type = types.str; };
      password = mkOption { type = types.str; };
      authType = mkOption { type = types.enum [ "pap" "chap" ]; };
    };
  };
}
