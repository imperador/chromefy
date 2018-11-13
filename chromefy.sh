#!/bin/sh

#Script to install ChromeOS on top of ChromiumOS
#Must be ran from ChromiumOS Live USB
#You must install ChromiumOS on your Hard Drive before running this script

#Parameters:
#1 - ChromiumOS (HDD) system partition (ex: /dev/sda3) (I suggest to manually resize it to 4GB before running the script)
#2 - ChromeOS image file to be installed
#3 - [Optional] ChromeOS image from older device with TPM1.2 (ex: caroline image file) (needed for TPM2 images like eve to be able to login)

if ( ! test -z {,} ); then echo "Must be ran with \"sudo bash\""; exit 1; fi
if [ $(whoami) != "root" ]; then echo "Please run with sudo"; exit 1; fi
if [ -z "$2" ]; then echo "Missing parametes"; exit 1; fi

if [ ! -d /home/chronos/image ]; then mkdir /home/chronos/image; fi
if [ ! -d /home/chronos/local ]; then mkdir /home/chronos/local; fi
if [ ! -d /home/chronos/tpm1image ]; then mkdir /home/chronos/tpm1image; fi

function abort_chromefy {
    echo "aborting...";
    umount /home/chronos/image 2>/dev/null
    umount /home/chronos/local 2>/dev/null
    umount /home/chronos/tpm1image 2>/dev/null
    losetup -d "$chromeos_image" 2>/dev/null
    losetup -d "$chromeos_tpm1_image" 2>/dev/null
    exit 1
}

#Checks if images are valid and mounts them
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

#Mounts ChromiumOS system partition
umount "$1" 2>/dev/null
mkfs.ext4 "$1"
mount "$1" /home/chronos/local
if [ ! $? -eq 0 ]; then echo "Partition $1 inexistent"; abort_chromefy; fi

#Copies all ChromeOS system files
cp -av /home/chronos/image/* /home/chronos/local
umount /home/chronos/image

#Copies modules and certificates from ChromiumOS
rm -rf /home/chronos/local/lib/firmware
rm -rf /home/chronos/local/lib/modules/ 
cp -av /lib/firmware /home/chronos/local/lib/
cp -av /lib/modules/ /home/chronos/local/lib/
rm -rf /home/chronos/local/etc/modprobe.d/alsa*.conf
sed '0,/enforcing/s/enforcing/permissive/' -i /home/chronos/local/etc/selinux/config

#Fix for TPM2 images (must pass third parameter)
if [ ! -z "$3" ]; then
	#Remove TPM 2.0 services
	rm -rf /home/chronos/local/etc/init/{attestationd,cr50-metrics,cr50-result,cr50-update,tpm_managerd,trunksd,u2fd}.conf

	#Copy TPM 1.2 file from tpm1image
	cp -av /home/chronos/tpm1image/etc/init/{chapsd,cryptohomed,tcsd,tpm-probe}.conf /home/chronos/local/etc/init/
	cp -av /home/chronos/tpm1image/etc/tcsd.conf /home/chronos/local/etc/
	cp -av /home/chronos/tpm1image/usr/bin/tpmc /home/chronos/local/usr/bin/
	cp -av /home/chronos/tpm1image/usr/lib64/libtspi.so{,.1{,.2.0}} /home/chronos/local/usr/lib64/
	cp -av /home/chronos/tpm1image/usr/sbin/{chapsd,cryptohomed,tcsd} /home/chronos/local/usr/sbin/
	cp -av /home/chronos/tpm1image/usr/share/cros/init/tcsd-pre-start.sh /home/chronos/local/usr/share/cros/init/
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

umount /home/chronos/local
sync
echo
echo "ChromeOS installed, you can now reboot"