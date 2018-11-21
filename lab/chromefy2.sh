#!/bin/sh

#Script to install ChromeOS on top of ChromiumOS
#Must be ran from ChromiumOS Live USB
#You must install ChromiumOS on your Hard Drive before running this script

#Parameters:
#1 - ChromiumOS image
#2 - ChromeOS image file to be installed
#3 - [Optional] ChromeOS image from older device with TPM1.2 (ex: caroline image file) (needed for TPM2 images like eve to be able to login)

#Entry: Chromium, Recovery, TPMRecovery, ZipDualBoot



if ( ! test -z {,} ); then echo "Must be ran with \"sudo bash\""; exit 1; fi
if [ $(whoami) != "root" ]; then echo "Please run with sudo"; exit 1; fi
if [ -z "$2" ]; then echo "Missing parametes"; exit 1; fi

if [ ! -d /home/image ]; then mkdir /home/image; fi
if [ ! -d /home/chromium ]; then mkdir /home/chromium; fi
if [ ! -d /home/tpm1image ]; then mkdir /home/tpm1image; fi
if [ ! -d /home/libs ]; then mkdir /home/libs; fi

function abort_chromefy {
    echo "aborting...";
    umount /home/image 2>/dev/null
    umount /home/chromium 2>/dev/null
    umount /home/tpm1image 2>/dev/null
    losetup -d "$chromium_image" 2>/dev/null
    losetup -d "$chromeos_image" 2>/dev/null
    losetup -d "$chromeos_tpm1_image" 2>/dev/null
    exit 1
}


#Checks if the Chromium image is valid and mounts it
if [ ! -f "$1" ]; then echo "Image $1 not found"; abort_chromefy; fi
chromium_image=`losetup --show -fP "$1"`

##### Saving Chrome Base - LAB
mount "$chromium_image"p3 /home/chromium -o loop,rw  2>/dev/null
if [ ! $? -eq 0 ]; then echo "Image $1 does not have a system partition (corrupted?)"; abort_chromefy; fi

cp -av /home/chromium/lib/* /home/libs
umount /home/chromium
##### End of Chrome Base - LAB

##### Resizing - LAB
## Get the Start and the End sectors
#ROOTB_START=`lsblk -o NAME,START -b "$chromium_image"p5 | grep "$chromium_image"p5 | cut -d' ' -f2`  # Getting partition B start sector (could use --first-in-largest)
#ROOTA_END=`lsblk -o NAME,END -b "$chromium_image"p3 | grep "$chromium_image"p3 | cut -d' ' -f2`  # Getting partition A end sector (could use ----end-of-largest)

## 2 - Deleting partitions
sfdisk --delete $chromium_image 5
sfdisk --delete $chromium_image 3

## 3 - Recreate the fifth partition with 4MB = 4194304
START_NEWB=`sgdisk -f $chromium_image`
END_NEWB=`expr $START_NEWB + 8192` #Considering sectors of 512 bytes

sgdisk -n 5:$START_NEWB:$END_NEWB $chromium_image
sgdisk -c 5:"ROOT-B" $chromium_image
sgdisk -t 5:"7F01" $chromium_image
e2label "$chromium_image"p5 "ROOT-B"
mkfs.ext4 "$chromium_image"p5


## 4 - Recreate the third partition with the remaining space
START_NEWA=`sgdisk -f $chromium_image`
END_NEWA=`sgdisk -E $chromium_image`

sgdisk -n 3:$START_NEWA:$END_NEWA $chromium_image
sgdisk -c 3:"ROOT-A" $chromium_image
sgdisk -t 3:"7F01" $chromium_image
e2label "$chromium_image"p3 "ROOT-A"
mkfs.ext4 "$chromium_image"p3

#Searching and fixing errors at filesystem-3
e2fsck -f -y -v -C 0 "$chromium_image"p3
##### End of Resizing Lab

#mkfs.ext4 "$chromium_image"p3
mount "$chromium_image"p3 /home/chromium -o loop,rw,sync  2>/dev/null
if [ ! $? -eq 0 ]; then echo "Image $1 does not have a system partition (corrupted?)"; abort_chromefy; fi

#Checks if the support images are valid and mounts them
if [ ! -f "$2" ]; then echo "Image $2 not found"; abort_chromefy; fi
chromeos_image=`losetup --show -fP "$2"`
mount "$chromeos_image"p3 /home/image -o loop,ro  2>/dev/null
if [ ! $? -eq 0 ]; then echo "Image $2 does not have a system partition (corrupted?)"; abort_chromefy; fi

if [ ! -z "$3" ]; then
    if [ ! -f "$3" ]; then echo "Image $3 not found"; abort_chromefy; fi
    chromeos_tpm1_image=`losetup --show -fP "$3"`
    mount "$chromeos_tpm1_image"p3 /home/tpm1image -o loop,ro  2>/dev/null
    if [ ! $? -eq 0 ]; then echo "Image $3 does not have a system partition (corrupted?)"; abort_chromefy; fi
fi

#Copies all ChromeOS system files
cp -av /home/image/* /home/chromium
umount /home/image

#Copies modules and certificates from ChromiumOS
rm -rf /home/chromium/lib/firmware
rm -rf /home/chromium/lib/modules/
cp -av /home/libs/firmware /home/chromium/lib/
cp -av /home/libs/modules/ /home/chromium/lib/
mount -o remount,rw /home/chromium
rm -rf /home/chromium/etc/modprobe.d/alsa*.conf
sed '0,/enforcing/s/enforcing/permissive/' -i /home/chromium/etc/selinux/config
rm -rf  /home/libs

#Fix for TPM2 images (must pass third parameter)
if [ ! -z "$3" ]; then
	#Remove TPM 2.0 services
	rm -rf /home/chromium/etc/init/{attestationd,cr50-metrics,cr50-result,cr50-update,tpm_managerd,trunksd,u2fd}.conf

	#Copy TPM 1.2 file from tpm1image
	cp -av /home/tpm1image/etc/init/{chapsd,cryptohomed,cryptohomed-client,tcsd,tpm-probe}.conf /home/chromium/etc/init/
	cp -av /home/tpm1image/etc/tcsd.conf /home/chromium/etc/
	cp -av /home/tpm1image/usr/bin/{tpmc,chaps_client} /home/chromium/usr/bin/
	cp -av /home/tpm1image/usr/lib64/libtspi.so{,.1{,.2.0}} /home/chromium/usr/lib64/
	cp -av /home/tpm1image/usr/sbin/{chapsd,cryptohome,cryptohomed,cryptohome-path,tcsd} /home/chromium/usr/sbin/
	cp -av /home/tpm1image/usr/share/cros/init/{tcsd-pre-start,chapsd}.sh /home/chromium/usr/share/cros/init/
    cp -av /home/tpm1image/etc/dbus-1/system.d/{Cryptohome,org.chromium.Chaps}.conf /home/chromium/etc/dbus-1/system.d/
    if [ ! -f /home/chromium/usr/lib64/libecryptfs.so ] && [ -f /home/tpm1image/usr/lib64/libecryptfs.so ]; then
        cp -av /home/tpm1image/usr/lib64/libecryptfs* /home/chromium/usr/lib64/
        cp -av /home/tpm1image/usr/lib64/ecryptfs /home/chromium/usr/lib64/
    fi

	#Add tss user and group
	echo 'tss:!:207:root,chaps,attestation,tpm_manager,trunks,bootlockboxd' | tee -a /home/chromium/etc/group
	echo 'tss:!:207:207:trousers, TPM and TSS operations:/var/lib/tpm:/bin/false' | tee -a /home/chromium/etc/passwd
    
    umount /home/tpm1image
fi

#Expose the internal camera to android container
internal_camera=`dmesg | grep uvcvideo -m 1 | awk -F'[()]' '{print $2}'`
original_camera=`sed -nr 's,^camera0.module0.usb_vid_pid=(.*),\1,p'  /home/chromium/etc/camera/camera_characteristics.conf`
if [ ! -z $internal_camera ] && [ ! -z $original_camera ]
  then
    sudo sed -i -e "s/${original_camera%:*}/${internal_camera%:*}/" -e "s/${original_camera##*:}/${internal_camera##*:}/" /home/chromium/lib/udev/rules.d/50-camera.rules
    sudo sed -i "s/$original_camera/$internal_camera/" /home/chromium/etc/camera/camera_characteristics.conf
fi


umount /home/chromium
sync
echo
echo "ChromeOS installed, you can now reboot"
