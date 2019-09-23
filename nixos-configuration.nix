# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, ... }:

{
  imports = [ ./hardware-configuration.nix ];

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.efi.efiSysMountPoint = "/boot/efi";
  boot.loader.grub = {
    enable = true;
    device = "nodev";
    version = 2;
    efiSupport = true;
    enableCryptodisk = true;
    extraInitrd = "/boot/initrd.keys.gz";
  };
  
  boot.initrd.luks.devices = [
      {
        name = "root";
        device = "/dev/disk/by-uuid/ROOTDEVICEUUID";
        preLVM = true;
        keyFile = "/root-keyfile.bin";
        allowDiscards = true;
      }
  ];

  networking.hostName = "nixos-usb"; # Define your hostname.
  networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.

  # Set your time zone.
  # time.timeZone = "US/Pacific";

  environment.systemPackages = with pkgs; [
    # Common tools 
    vim inetutils psmisc curl wget screen socat rsync expect
    # Disk tools
    efibootmgr efivar gptfdisk cryptsetup
    # Hardware-related tools
    sdparm hdparm dmraid smartmontools pciutils usbutils
    # Secure key management
    yubikey-manager gnupg pass
    # QR code
    (zbar.override { enableVideo = false; }) qrencode
  ];

  programs.gnupg.agent = { enable = true; enableSSHSupport = true; };
  services.openssh.enable = true;
  services.pcscd.enable = true;
  system.stateVersion = "19.03";
  nix = {
    binaryCaches = [ "https://cache.nixos.org/" ];
    binaryCachePublicKeys = [ "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=" ];
  };
}
