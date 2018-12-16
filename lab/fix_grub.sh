#!/bin/sh
#Script to correct grub problem
#If installing to a system partition, must be ran from ChromiumOS Live USB (otherwise, any Linux distro is fine)
#If installing to a system partition, You must install ChromiumOS on your Hard Drive before running this script

#Parameters:
#1 - Disc where ChromeOs is installed

function fix_grub {
    sync
    umount /home/chronos/EFI 2>/dev/null
}

# Get the partition of the EFI
if [ ! -d /home/chronos/EFI ]; then mkdir /home/chronos/EFI; fi
if [ -z "$1" ]; then echo "Missing Disk"; exit 1; fi
EFIPART=`sfdisk -lq "$1" 2>/dev/null | grep "^""$1""[^:]" | awk '{print $1}' | grep [^0-9]12$`

# Try to mount the EFI partition
mount "$EFIPART" /home/chronos/EFI -o loop,rw  2>/dev/null
if [ ! $? -eq 0 ]; then echo "Disk $1 does not have a EFI partition (corrupted?)"; fix_grub; fi

# Gets the UUID at the grub file
OLD_UUID=`cat /home/chronos/EFI/efi/boot/grub.cfg | grep -m 1 "PARTUUID=" | awk -v FS="(PARTUUID=)" '{print $2}' | awk '{print $1}'`
OLD_UUID_LEGACY=`cat /home/chronos/EFI/syslinux/usb.A.cfg | grep -m 1 "PARTUUID=" | awk -v FS="(PARTUUID=)" '{print $2}' | awk '{print $1}'`

# Changes the grub configuration to point to the right partition
PARTUUID=`sfdisk --part-uuid "$1" 3`
sed -i "s/$OLD_UUID/$PARTUUID/" /home/chronos/EFI/efi/boot/grub.cfg
sed -i "s/$OLD_UUID_LEGACY/$PARTUUID/" /home/chronos/EFI/syslinux/usb.A.cfg

echo "Partition $OLD_UUID changed to $PARTUUID"
echo "You can reboot your PC!"

fix_grub

