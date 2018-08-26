# chromefy
Transforming Chromium to Chrome

## Observations

  - You NEED Chromium installation running 
  - You HAVE to be logged in (because if you don't, the initial setup won't work)
  - I am not responsible for any damage made to your computer by you or by your dog

## Getting the right IMG for YOUR pc

First, download the right recovery img here: chrome.qwedl.com (choose the one with the closest specs of your system)
You can use [THIS LIST](https://www.chromium.org/chromium-os/developer-information-for-chrome-os-devices) to search for your processor, and then search on the internet for which one is the best
 
After finishing installing a Chromium OS, open the browser and press CTRL+ALT+T to open chroot
Type:
```sh
shell
sudo su
```

Installing Chrome OS (some notes):
  - If the file is in Downloads folder, {path}=home/chronos/user/Downloads, so use the path accordingly with your file location
  - Change "chromeos_10575.58.0_caroline_recovery_stable-channel_mp.bin" to the name of YOUR recovery img.
  - Any password or username will be 'chronos'

## Configuring the new Chrome partition

Use the following commands to configure the sda5 (or nvem0n1p5) and other basic things (the exemple is using caroline recovery file):
Type "lsblk" to know your partitions. Search for sda, sdb or nvme0n1 with the size of your usb or HDD. In the following commands, change "sda" for the one that you've found:
```sh
losetup -fP {path}/chromeos_10575.58.0_caroline_recovery_stable-channel_mp.bin
mkdir /home/chronos/image
mkdir /home/chronos/local
mkfs.ext4 /dev/sda5
mount /dev/sda5 /home/chronos/local
```

## Copying the img to the local path

Type "losetup" to get a list, search for loop{number} that has the img file on it
Memorise the number. So if it is loop2, then {number} = 2
Type the following commands (using the {number} that you got in the last step):
```sh
mount /dev/loop{number}p3 /home/chronos/image -o loop,ro
cp -av /home/chronos/image/* /home/chronos/local
rm -rf /home/chronos/local/lib/firmware
rm -rf /home/chronos/local/lib/modules/ (name of folder depends on kernel)
cp -av /lib/firmware /home/chronos/local/lib/
cp -av /lib/modules/4.14.33 /home/chronos/local/lib/modules/
rm -rf /home/chronos/local/etc/modprobe/alsa-skl.conf
```

Change in /home/chronos/local/etc/selinux/config the word enforcing to permissive with the following command:
```sh
sudo sed '0,/enforcing/s/enforcing/permissive/' -i /home/chronos/local/etc/selinux/config
```
Type "sync" and press Enter

Now restart your computer. When the screen with the boot options appear (the grub), press 'e' FAST (or it will boot into the chromium). You will have to change the root for:
root=/dev/sda5

Now press F10. If it boots coorectly, you are ready to go
 
# ADITIONAL:

## Updating the System 

Working on this

# Credits:
[allanin](https://github.com/allanin) for all of his ideas on Arnoldthebat discussion, most part of the code here is from him.

Dnim Ecaep from the [Telegram Group](https://t.me/chromeosforpc)

++ some more that I will add soon

## Updating the System 
