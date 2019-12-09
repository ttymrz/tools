# Do not modify this file!  It was generated by ‘nixos-generate-config’
# and may be overwritten by future invocations.  Please make changes
# to /etc/nixos/configuration.nix instead.
{ config, lib, pkgs, ... }:

{
  imports =
    # the not-detected one confuses CI...
    [ # <nixpkgs/nixos/modules/installer/scan/not-detected.nix>
    ];
  # ensure we build for x86_64-linux. This is important
  # to prevent nixops to try tand build this configuration
  # for `currentSystem`, which is x86_64-dsarwin on macOS>
  nixpkgs.localSystem.system = "x86_64-linux";

  boot.initrd.availableKernelModules = [ "ahci" "nvme" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-intel" ];
  boot.extraModulePackages = [ ];

  boot.supportedFilesystems = [ "zfs" ];
  networking.hostId = "eca0dea2"; # required for zfs use

  fileSystems."/" =
    { device = "tank/root";
      fsType = "zfs";
    };

  fileSystems."/home" =
    { device = "tank/home";
      fsType = "zfs";
    };

  fileSystems."/nix" =
    { device = "tank/nix";
      fsType = "zfs";
    };

  fileSystems."/boot" =
    { device = "/dev/disk/by-uuid/cd3f718b-9919-4218-99ea-db3c3ccc5acf";
      fsType = "ext3";
    };

  swapDevices =
    [ { device = "/dev/disk/by-uuid/c9ec93c1-81a3-4a56-b7a8-5bca7468b502"; }
    ];

  nix.maxJobs = lib.mkDefault 16;
  powerManagement.cpuFreqGovernor = lib.mkDefault "powersave";
}