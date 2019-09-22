# Secure Setup for Key Management

***WARNING: this is a work-in-progress. Follow it at your own risk!***


## 1. Create a USB drive

The `mkusb.sh` script is used to create an encrypted USB drive.
***It only works on an existing NixOS.***

For example, if your USB drive is at `/dev/sdc`, run this:
```
sudo ./mkusb.sh /dev/sdc
```

Just follow through the steps, and it will format the USB drive and install a customized NixOS on it, with encrypted UEFI partitions.
The USB drive can then be plugged into a separate machine to boot.
The recommendation is to only boot this USB drive on an offline machine.

The pitfall of using `nixos-install` in this script is that the hardware detection can be mis-guided (e.g. swap partition).
A better way is to follow the approach taken by [`nixos/modules/installer/cd-dvd/iso-image.nix`](https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/installer/cd-dvd/iso-image.nix), and use a pure Nix way to create a USB disk image.
Ideas and suggestions on how to make it happen are welcome!

## 2. Create GnuPG keys

## 3. Move secret keys to YubiKey

## 4. Multi-device considerations

## 5. Related setups

### 5.1 GnuPG Agent and SSH

### 5.2 Pass and Browserpass

### 5.3 XBrowserSync
