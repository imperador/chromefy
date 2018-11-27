#!/bin/sh

#Script to add Dualboot to Chromefy
#If installing to a system partition, must be ran from ChromiumOS Live USB (otherwise, any Linux distro is fine)
#You must install ChromiumOS on your Hard Drive before running this script
#After the process, just run: "sudo bash /usr/sbin/dual-boot-install -d /dev/sda"
#This script adds Fyde dual booot files to your chromeos. Not solid yet, so keep in mind that it is a test.

#Parameters:
#1 - ChromiumOS image or (HDD) system partition (ex: /dev/sda3) (If partition: I suggest to manually resize it to 4GB before running the script)
#2 - Dualboot bin file

if ( ! test -z {,} ); then echo "Must be ran with \"sudo bash\""; exit 1; fi
if [ $(whoami) != "root" ]; then echo "Please run with sudo"; exit 1; fi
if [ -z "$2" ]; then echo "Missing parametes"; exit 1; fi
if [ -b "$1" ]; then flag_image=false; elif [ -f "$1" ]; then flag_image=true; else echo "Invalid image or partition: $1"; exit 1; fi
if [ "$flag_image" = false ] && [ ! -e "/usr/sbin/chromeos-install" ]; then echo "You need to be running ChromiumOS (Live USB) to chromefy a drive partition"; exit 1; fi;

if [ ! -d /home/chronos ]; then mkdir /home/chronos; fi
if [ ! -d /home/chronos/dualboot ]; then mkdir /home/chronos/dualboot; fi
if [ ! -d /home/chronos/RAW ]; then mkdir /home/chronos/RAW; fi

function cleanup_chromefy {
    sync
    umount /home/chronos/dualboot 2>/dev/null
    umount /home/chronos/RAW 2>/dev/null
    losetup -d "$chromium_image" 2>/dev/null
    losetup -d "$dualboot_image" 2>/dev/null
}

function abort_chromefy {
    echo "aborting...";
    cleanup_chromefy
    exit 1
}

#Checks if images are valid and mounts them
if [ "$flag_image" = true ]; then
    chromium_image=`losetup --show -fP "$1"`
    mount "$chromium_image"p3 /home/chronos/local -o loop,rw  2>/dev/null
    if [ ! $? -eq 0 ]; then echo "Image $1 does not have a system partition (corrupted?)"; abort_chromefy; fi
else
    mount "$1" /home/chronos/local
    if [ ! $? -eq 0 ]; then echo "Partition $1 inexistent"; abort_chromefy; fi
fi

if [ ! -f "$2" ]; then echo "Image $2 not found"; abort_chromefy; fi
dualboot_image=`losetup --show -fP "$2"`
mount "$dualboot_image" /home/chronos/dualboot -o loop,ro  2>/dev/null
if [ ! $? -eq 0 ]; then echo "Image $2 does not have a system partition (corrupted?)"; abort_chromefy; fi

#Copies all Dualboot files
cp -av /home/chronos/dualboot/* /home/chronos/local
sudo chmod +x /home/chronos/local/usr/sbin/gdisk
sudo chmod +x /home/chronos/local/usr/sbin/sgdisk

cleanup_chromefy
echo
echo "ChromeOS installed, you can now reboot"
