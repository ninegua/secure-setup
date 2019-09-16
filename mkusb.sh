#! /usr/bin/env nix-shell
#! nix-shell -i bash -p cryptsetup

USAGE="USAGE: $0 <device>"
device=$1
test -z "$device" && echo $USAGE && exit 1

echo type passphrase:
read -s pass


# 1. Partition disk
disklabel=`uuidgen`
#sfdisk -d ${device}
sleep 2
sfdisk ${device} <<EOF
label: gpt
label-id: $disklabel
- 200M U *
- - L -
EOF
#name=EFI System, size=200M, type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B, bootable
#name=Linux System, type=0FC63DAF-8483-4772-8E79-3D69D8477DE4

bootpart=`sfdisk --part-uuid $device 1|tr '[:upper:]' '[:lower:]'`
rootpart=`sfdisk --part-uuid $device 2|tr '[:upper:]' '[:lower:]'`
# wait a moment for the device to appear
sleep 2
bootdevice=`readlink -f /dev/disk/by-partuuid/$bootpart`
rootdevice=`readlink -f /dev/disk/by-partuuid/$rootpart`
echo $bootdevice $rootdevice

# 2. Create encrypted LUKS device
echo -n $pass | cryptsetup luksFormat -q -c aes-xts-plain64 -s 256 -h sha512 $rootdevice -d -
echo -n $pass | cryptsetup luksOpen $rootdevice crypted-nixos -d -


# 3. Setup LVM  (TODO: fix the label root to avoid conflict)
pvcreate /dev/mapper/crypted-nixos
vgcreate vg /dev/mapper/crypted-nixos
lvcreate -l '100%FREE' -n root vg
vgrootdevice=/dev/vg/root

# 4. Format partitions
mkfs.fat -F 32 $bootdevice
mkfs.ext4 -L root $vgrootdevice

# 5. Mount /mnt
mount $vgrootdevice /mnt
mkdir -p /mnt/boot/efi
mount $bootdevice /mnt/boot/efi

# 6. Dump key file into /mnt/boot
dd if=/dev/urandom of=./root-keyfile.bin bs=1024 count=4
echo -n $pass | cryptsetup luksAddKey $rootdevice root-keyfile.bin -d -
find root-keyfile*.bin -print0 | sort -z | cpio -o -H newc -R +0:+0 --reproducible --null | gzip -9 > /mnt/boot/initrd.keys.gz
chmod 000 /mnt/boot/initrd.keys.gz

# 6. Configure NixOS installation
nixos-generate-config --root /mnt
rootuuid=`lsblk -o UUID -d -n $rootdevice`
cat nixos-configuration.nix|sed -e "s/ROOTDEVICEUUID/${rootuuid}/" > /mnt/etc/nixos/configuration.nix

# 7. Install nixos (will ask for root password)
echo Press ENTER to continue NixOS installation on $device.
echo Or switch to a different terminal to edit /mnt/etc/nixos/configurations.nix
echo and hardware-configure.nix before continuing...
read -s
sh -c nixos-install

# 8. finish up
umount /mnt/boot/efi
umount /mnt
vgchange -an vg
cryptsetup luksClose crypted-nixos
echo Done!
