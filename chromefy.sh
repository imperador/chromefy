#!/bin/sh

#Script to install ChromeOS on top of ChromiumOS
#If installing to a system partition, must be ran from ChromiumOS Live USB (otherwise, any Linux distro is fine)
#If installing to a system partition, You must install ChromiumOS on your Hard Drive before running this script

#Parameters:
#1 - ChromiumOS image or (HDD) system partition (ex: /dev/sda3) (If partition: I suggest to manually resize it to 4GB before running the script)
#2 - ChromeOS image file to be installed
#3 - [Optional] ChromeOS image from older device with TPM1.2 (ex: caroline image file) (needed for TPM2 images like eve to be able to login)

if ( ! test -z {,} ); then echo "Must be ran with \"sudo bash\""; exit 1; fi
if [ $(whoami) != "root" ]; then echo "Please run with sudo"; exit 1; fi
if [ -z "$2" ]; then echo "Missing parametes"; exit 1; fi
if [ -b "$1" ]; then flag_image=false; elif [ -f "$1" ]; then flag_image=true; else echo "Invalid image or partition: $1"; exit 1; fi
if [ "$flag_image" = false ] && [ ! -e "/usr/sbin/chromeos-install" ]; then echo "You need to be running ChromiumOS (Live USB) to chromefy a drive partition"; exit 1; fi;

if [ ! -d /home/chronos ]; then mkdir /home/chronos; fi
if [ ! -d /home/chronos/image ]; then mkdir /home/chronos/image; fi
if [ ! -d /home/chronos/local ]; then mkdir /home/chronos/local; fi
if [ ! -d /home/chronos/tpm1image ]; then mkdir /home/chronos/tpm1image; fi
if [ ! -d /home/chronos/RAW ]; then mkdir /home/chronos/RAW; fi

function cleanup_chromefy {
    sync
    umount /home/chronos/image 2>/dev/null
    umount /home/chronos/local 2>/dev/null
    umount /home/chronos/tpm1image 2>/dev/null
    losetup -d "$chromium_image" 2>/dev/null
    losetup -d "$chromeos_image" 2>/dev/null
    losetup -d "$chromeos_tpm1_image" 2>/dev/null
    rm -rf /home/chronos/RAW/* &>/dev/null
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
fi

if [ ! -f "$2" ]; then echo "Image $2 not found"; abort_chromefy; fi
chromeos_image=`losetup --show -fP "$2"`
mount "$chromeos_image"p3 /home/chronos/image -o loop,ro  2>/dev/null
if [ ! $? -eq 0 ]; then echo "Image $2 does not have a system partition (corrupted?)"; abort_chromefy; fi

if [ ! -z "$3" ]; then
    if [ ! -f "$3" ]; then echo "Image $3 not found"; abort_chromefy; fi
    chromeos_tpm1_image=`losetup --show -fP "$3"`
    mount "$chromeos_tpm1_image"p3 /home/chronos/tpm1image -o loop,ro  2>/dev/null
    if [ ! $? -eq 0 ]; then echo "Image $3 does not have a system partition (corrupted?)"; abort_chromefy; fi
fi

#Increases ROOT_A partition's size (if flashing on image)
if [ "$flag_image" = true ]; then
    #Backups ChromiumOS' /lib
    cp -av /home/chronos/local/lib /home/chronos/RAW/
    umount /home/chronos/local
    
    PART_B=`sudo sfdisk -lq "$chromium_image" | grep "^""$chromium_image""[^:]" | awk '{print $1}' | grep [^0-9]5$`
    PART_A=`sudo sfdisk -lq "$chromium_image" | grep "^""$chromium_image""[^:]" | awk '{print $1}' | grep [^0-9]3$`
    PART_STATE=`sudo sfdisk -lq "$chromium_image" | grep "^""$chromium_image""[^:]" | awk '{print $1}' | grep [^0-9]1$`
    
    START_NEWB=`sfdisk -o Device,Start -lq "$chromium_image" | grep "^""$PART_B"[[:space:]] | awk '{print $2}'`
    END_NEWB=`expr $START_NEWB + 8191`
    UUID_B=`sfdisk --part-uuid "$chromium_image" 5`
    START_NEWA=`expr $END_NEWB + 1`
    END_NEWA=`expr $(sfdisk -o Device,Start -lq "$chromium_image" | grep "^""$PART_STATE"[[:space:]] | awk '{print $2}') - 1`
    UUID_A=`sfdisk --part-uuid "$chromium_image" 3`
    
    #Deletes third (ROOT_A) and fifth (ROOT_B) partitions
    sfdisk --delete $chromium_image 5
    sfdisk --delete $chromium_image 3
    
    #Recreates the fifth partition with 4MB = 4194304
    echo -e 'n\n5\n'"$START_NEWB"'\n'"$END_NEWB"'\nw' | fdisk "$chromium_image"; sync
    sfdisk --part-label "$chromium_image" 5 "ROOT-B"
    sfdisk --part-type "$chromium_image" 5 "3CB8E202-3B7E-47DD-8A3C-7FF2A13CFCEC"
    sfdisk --part-uuid "$chromium_image" 5 "$UUID_B"
    e2label "$PART_B" "ROOT-B"
    mkfs.ext4 "$PART_B"
    
    #Recreates the third partition with the remaining space
    echo -e 'n\n3\n'"$START_NEWA"'\n'"$END_NEWA"'\nw' | fdisk "$chromium_image"; sync
    sfdisk --part-label "$chromium_image" 3 "ROOT-A"
    sfdisk --part-type "$chromium_image" 3 "3CB8E202-3B7E-47DD-8A3C-7FF2A13CFCEC"
    sfdisk --part-uuid "$chromium_image" 3 "$UUID_A"
    e2label "$PART_A" "ROOT-A"
    mkfs.ext4 "$PART_A"
    
    #Searches and fixes errors at filesystem-3, then remounts
    e2fsck -f -y -v -C 0 "$PART_A"
fi

#Mounts ChromiumOS system partition
if [ "$flag_image" = false ]; then
    chromium_root_dir=""
    umount "$1" 2>/dev/null
    mkfs.ext4 "$1"
    mount "$1" /home/chronos/local
    if [ ! $? -eq 0 ]; then echo "Partition $1 inexistent"; abort_chromefy; fi
else
    chromium_root_dir="/home/chronos/RAW"
    mount "$PART_A" /home/chronos/local -o loop,rw,sync  2>/dev/null
    if [ ! $? -eq 0 ]; then echo "Something went wrong while changing $1 partition table (corrupted?)"; abort_chromefy; fi
fi

#Copies all ChromeOS system files
cp -av /home/chronos/image/* /home/chronos/local
umount /home/chronos/image

#Copies modules and certificates from ChromiumOS
rm -rf /home/chronos/local/lib/firmware
rm -rf /home/chronos/local/lib/modules/ 
cp -av "$chromium_root_dir"/lib/firmware /home/chronos/local/lib/
cp -av "$chromium_root_dir"/lib/modules/ /home/chronos/local/lib/
rm -rf /home/chronos/local/etc/modprobe.d/alsa*.conf
sed '0,/enforcing/s/enforcing/permissive/' -i /home/chronos/local/etc/selinux/config

#Fix for TPM2 images (must pass third parameter)
if [ ! -z "$3" ]; then
	#Remove TPM 2.0 services
	rm -rf /home/chronos/local/etc/init/{attestationd,cr50-metrics,cr50-result,cr50-update,tpm_managerd,trunksd,u2fd}.conf

	#Copy TPM 1.2 file from tpm1image
	cp -av /home/chronos/tpm1image/etc/init/{chapsd,cryptohomed,cryptohomed-client,tcsd,tpm-probe}.conf /home/chronos/local/etc/init/
	cp -av /home/chronos/tpm1image/etc/tcsd.conf /home/chronos/local/etc/
	cp -av /home/chronos/tpm1image/usr/bin/{tpmc,chaps_client} /home/chronos/local/usr/bin/
	cp -av /home/chronos/tpm1image/usr/lib64/libtspi.so{,.1{,.2.0}} /home/chronos/local/usr/lib64/
	cp -av /home/chronos/tpm1image/usr/sbin/{chapsd,cryptohome,cryptohomed,cryptohome-path,tcsd} /home/chronos/local/usr/sbin/
	cp -av /home/chronos/tpm1image/usr/share/cros/init/{tcsd-pre-start,chapsd}.sh /home/chronos/local/usr/share/cros/init/
    cp -av /home/chronos/tpm1image/etc/dbus-1/system.d/{Cryptohome,org.chromium.Chaps}.conf /home/chronos/local/etc/dbus-1/system.d/
    if [ ! -f /home/chronos/local/usr/lib64/libecryptfs.so ] && [ -f /home/chronos/tpm1image/usr/lib64/libecryptfs.so ]; then
        cp -av /home/chronos/tpm1image/usr/lib64/libecryptfs* /home/chronos/local/usr/lib64/
        cp -av /home/chronos/tpm1image/usr/lib64/ecryptfs /home/chronos/local/usr/lib64/
    fi

	#Add tss user and group
	echo 'tss:!:207:root,chaps,attestation,tpm_manager,trunks,bootlockboxd' | tee -a /home/chronos/local/etc/group
	echo 'tss:!:207:207:trousers, TPM and TSS operations:/var/lib/tpm:/bin/false' | tee -a /home/chronos/local/etc/passwd
    
    umount /home/chronos/tpm1image
fi

#Expose the internal camera to android container
internal_camera=`dmesg | grep uvcvideo -m 1 | awk -F'[()]' '{print $2}'`
original_camera=`sed -nr 's,^camera0.module0.usb_vid_pid=(.*),\1,p'  /home/chronos/local/etc/camera/camera_characteristics.conf`
if [ ! -z $internal_camera ] && [ ! -z $original_camera ]
  then
    sudo sed -i -e "s/${original_camera%:*}/${internal_camera%:*}/" -e "s/${original_camera##*:}/${internal_camera##*:}/" /home/chronos/local/lib/udev/rules.d/50-camera.rules
    sudo sed -i "s/$original_camera/$internal_camera/" /home/chronos/local/etc/camera/camera_characteristics.conf
fi

cleanup_chromefy
echo
echo "ChromeOS installed, you can now reboot"