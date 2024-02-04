{
  description = ''
    Turris Omnia
    ************

    This is a 32 bit ARMv7 MVEBU device, which is usually shipped with
    TurrisOS, an OpenWrt-based system. Rather than reformatting the
    builtin storage, we install Liminix on to the existing btrfs
    filesystem so that the vendor snapshot/recovery system continues
    to work (and provides you an easy rollback if you decide you don't
    like Liminix after all).

    The install process is designed so that you should not need to open
    the device and add a serial console (although it may be handy
    for visibility  and in case anything goes wrong). In outline

      1. build a "recovery" system with useful btrfs tools
      2. boot that system using TFTP or a USB stick
      3. once booted, mount the real root filesystem on /mnt
      4. take a snapshot using schnapps, and then delete everything
      5. use min-copy-closure -d /mnt/@ to copy the real configuration
         to the device
      6. reboot into a fully operational system

    Detailed instructions to follow...
  '';

  system = {
    crossSystem = {
      config = "armv7l-unknown-linux-musleabihf";
    };
  };

  module = {pkgs, config, lib, lim, ... }:
    let
      openwrt = pkgs.openwrt;
      inherit (lib) mkOption types;
      inherit (pkgs.liminix.services) oneshot;
      inherit (pkgs) liminix;
      mtd_by_name_links = pkgs.liminix.services.oneshot rec  {
        name = "mtd_by_name_links";
        up = ''
          mkdir -p /dev/mtd/by-name
          cd /dev/mtd/by-name
          for i in /sys/class/mtd/mtd*[0-9]; do
            ln -s ../../$(basename $i) $(cat $i/name)
          done
        '';
      };
    in {
      imports = [
        ../../modules/arch/arm.nix
        ../../modules/outputs/tftpboot.nix
        ../../modules/outputs/mbrimage.nix
        ../../modules/outputs/extlinux.nix
      ];

      config = {
        services.mtd-name-links = mtd_by_name_links;
        kernel = {
          src = pkgs.pkgsBuildBuild.fetchurl {
            name = "linux.tar.gz";
            url = "https://cdn.kernel.org/pub/linux/kernel/v5.x/linux-5.15.137.tar.gz";
            hash = "sha256-PkdzUKZ0IpBiWe/RS70J76JKnBFzRblWcKlaIFNxnHQ=";
          };
          extraPatchPhase = ''
            ${pkgs.openwrt.applyPatches.mvebu}
          '';
          config = {
            PCI = "y";
            OF = "y";
            MEMORY = "y"; # for MVEBU_DEVBUS
            DMADEVICES = "y"; # for MV_XOR
            CPU_V7 = "y";
            ARCH_MULTIPLATFORM = "y";
            ARCH_MVEBU = "y";
            ARCH_MULTI_V7= "y";
            PCI_MVEBU = "y";
            AHCI_MVEBU = "y";
            MACH_ARMADA_38X = "y";
            SMP = "y";
	          # this is disabled for the moment because it relies on a GCC
            # plugin that requires gmp.h to build, and I can't see right now
            # how to confgure it to find gmp
            STACKPROTECTOR_PER_TASK = "n";
            NR_CPUS = "4";
            VFP = "y";
            NEON= "y";

            # WARNING: unmet direct dependencies detected for ARCH_WANT_LIBATA_LEDS
            ATA = "y";

            PSTORE = "y";
            PSTORE_RAM = "y";
            PSTORE_CONSOLE = "y";
            PSTORE_DEFLATE_COMPRESS = "n";

            BLOCK = "y";
            MMC="y";
            PWRSEQ_EMMC="y";        # ???
            PWRSEQ_SIMPLE="y";      # ???
            MMC_BLOCK="y";

            MMC_SDHCI= "y";
            MMC_SDHCI_PLTFM= "y";
            MMC_SDHCI_PXAV3= "y";
            MMC_MVSDIO= "y";

            SERIAL_8250 = "y";
            SERIAL_8250_CONSOLE = "y";
            SERIAL_OF_PLATFORM="y";
            SERIAL_MVEBU_UART = "y";
            SERIAL_MVEBU_CONSOLE = "y";

            SERIAL_8250_DMA= "y";
            SERIAL_8250_DW= "y";
            SERIAL_8250_EXTENDED= "y";
            SERIAL_8250_MANY_PORTS= "y";
            SERIAL_8250_SHARE_IRQ= "y";
            OF_ADDRESS= "y";
            OF_MDIO= "y";

            WATCHDOG = "y";        # watchdog is enabled by u-boot
            ORION_WATCHDOG = "y";  # so is non-optional to keep feeding

            MVEBU_DEVBUS = "y"; # "Device Bus controller ...  flash devices such as NOR, NAND, SRAM, and FPGA"
            MVMDIO = "y";
            MVNETA = "y";
            MVNETA_BM = "y";
            MVNETA_BM_ENABLE = "y";
            SRAM = "y"; # mmio-sram is "compatible" for bm_bppi reqd by BM
            PHY_MVEBU_A38X_COMPHY = "y"; # for eth2
            MARVELL_PHY = "y";

            MVPP2 = "y";
            MV_XOR = "y";

            # there is NOR flash on this device, which is used for U-Boot
            # and the rescue system (which we don't interfere with) but
            # also for the U-Boot environment variables (which we might
            # need to meddle with)
            MTD_SPI_NOR = "y";
            SPI = "y";
            SPI_MASTER = "y";
            SPI_ORION = "y";

            NET_DSA = "y";
            NET_DSA_MV88E6XXX = "y"; # depends on PTP_1588_CLOCK_OPTIONAL
          };
          conditionalConfig = {
            USB = {
              USB_XHCI_MVEBU = "y";
              USB_XHCI_HCD = "y";
            };
          };
        };

        boot = {
          commandLine = [
            "console=ttyS0,115200"
            "pcie_aspm=off" # ath9k pci incompatible with PCIe ASPM
          ];
        };
        filesystem =
          let
            inherit (pkgs.pseudofile) dir symlink;
            firmware = pkgs.stdenv.mkDerivation {
              name = "wlan-firmware";
              phases = ["installPhase"];
              installPhase = ''
                mkdir $out
                cp -r ${pkgs.linux-firmware}/lib/firmware/ath10k/QCA988X $out
              '';
            };
          in dir {
            lib = dir {
              firmware = dir {
                ath10k = symlink firmware;
              };
            };
            etc = dir {
              "fw_env.config" =
                let f = pkgs.writeText "fw_env.config" ''
                  /dev/mtd/by-name/u-boot-env 0x0 0x10000 0x10000
                '';
                in symlink f;
            };
          };

        boot.tftp = {
          loadAddress = lim.parseInt "0x1700000";
          kernelFormat = "zimage";
          compressRoot = true;
        };

        hardware = let
          mac80211 = pkgs.mac80211.override {
            drivers = ["ath9k_pci" "ath10k_pci"];
            klibBuild = config.system.outputs.kernel.modulesupport;
          };
        in {
          defaultOutput = "mtdimage";
          loadAddress = lim.parseInt "0x00800000"; # "0x00008000";
          entryPoint = lim.parseInt "0x00800000"; # "0x00008000";
          rootDevice = "/dev/mmcblk0p1";

          dts = {
            src = "${config.system.outputs.kernel.modulesupport}/arch/arm/boot/dts/armada-385-turris-omnia.dts";
            includes =  [
              "${config.system.outputs.kernel.modulesupport}/arch/arm/boot/dts/"
            ];
          };
          flash.eraseBlockSize = 65536; # only used for tftpboot
          networkInterfaces =
            let
              inherit (config.system.service.network) link;
              inherit (config.system.service) bridge;
            in rec {
              en70000 = link.build {
                # in armada-38x.dtsi this is eth0.
                # It's connected to port 5 of the 88E6176 switch
                devpath = "/devices/platform/soc/soc:internal-regs/f1070000.ethernet";
                # name is unambiguous but not very semantic
                ifname = "en70000";
              };
              en30000 = link.build {
                # in armada-38x.dtsi this is eth1
                # It's connected to port 6 of the 88E6176 switch
                devpath = "/devices/platform/soc/soc:internal-regs/f1030000.ethernet";
                # name is unambiguous but not very semantic
                ifname = "en30000";
              };
              # the default (from the dts? I'm guessing) behavour for
              # lan ports on the switch is to attach them to
              # en30000. It should be possible to do something better,
              # per
              # https://www.kernel.org/doc/html/latest/networking/dsa/configuration.html#affinity-of-user-ports-to-cpu-ports
              # but apparently OpenWrt doesn't either so maybe it's more
              # complicated than it looks.

              wan = link.build {
                # in armada-38x.dtsi this is eth2. It may be connected to
                # an ethernet phy or to the SFP cage, depending on a gpio
                devpath = "/devices/platform/soc/soc:internal-regs/f1034000.ethernet";
                ifname = "wan";
              };

              lan0 = link.build { ifname = "lan0"; };
              lan1 = link.build { ifname = "lan1"; };
              lan2 = link.build { ifname = "lan2"; };
              lan3 = link.build { ifname = "lan3"; };
              lan4 = link.build { ifname = "lan4"; };
              lan5 = link.build { ifname = "lan5"; };
              lan = lan0; # maybe we should build a bridge?

              wlan = link.build {
                ifname = "wlan0";
                dependencies = [ mac80211 ];
              };
              wlan5 = link.build {
                ifname = "wlan1";
                dependencies = [ mac80211 ];
              };
            };
        };
      };
    };
}
