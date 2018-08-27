# chromefy
Transforming Chromium to Chrome

You can find us in the Telegram Group:
https://t.me/chromeosforpc

## Observations

  - You NEED Chromium installation running 
  - You HAVE to be logged in (because if you don't, the initial setup won't work)
  - I am not responsible for any damage made to your computer by you or by your dog
  - If you are using a Chromebook, you do not need to install Chromium. Just grab a suitable recovery image and follow the      installation instructions while in ChromeOS native
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

## Updating ChromeOS and Chromium Native: The Setup
You will need a Live USB of any Linux distribution. I recommend Mint or Ubuntu.

Find and download the updated recovery image for the device you used at chrome.qwedl.com

Go to ArnoldTheBats and find the latest daily build, download it. Extract the 7z file, and copy the Chromium image to your downloads. rename it to Chromium.img

Now type in the following commands in the Linux terminal:
```sh
losetup -fP /home/chronos/user/Downloads/chromeos.bin
losetup -fP /home/chronos/user/Downloads/Chromium.img
mount /dev/sda5 /home/chronos/local
mount /dev/sda3 /home/chronos/native
```
Now type losetup to get a list of Loop devices, find the one that cooresponds to your ChromeOS Image and than type:
```sh
mount /dev/loop{number}p3 /home/chronos/image -o loop,ro
```

Now look in losetup to find the loop device that cooresponds with your Chromium image. Type:
```sh
mount /dev/loop{number}p3 /home/chronos/chromium -o loop,ro
```

## Updating both ChromeOS and Chromium Native: The actual upgrade
Remember, the commands outlined here must be done in EXACTLY this order to guarantee everything goes smoothly. IF you don't do this and find neither the touchscreen, trackpad, or keyboard works, that's on you. Not me, or anyone else.

```sh
rm -rf /home/chronos/local
cp -av /home/chronos/image/* /home/chronos/local
rm -rf /home/chronos/local/lib/firmware
rm -rf /home/chronos/local/lib/modules/
cp -av /home/chronos/native/lib/firmware /home/chronos/local/lib/
cp -av /home/chronos/native/lib/modules/ /home/chronos/local/lib/modules/
rm -rf /home/chronos/local/etc/modprobe/alsa-.conf
```
(Alsa-* being whatever the config name is, in my case it would be Alsa-skl.conf)

Change in /home/chronos/local/etc/selinux/config the word enforcing to permissive with the following command:
```sh
sudo sed '0,/enforcing/s/enforcing/permissive/' -i /home/chronos/local/etc/selinux/config
```

 [Optional] Now to update Chromium Native
```sh
rm -rf /home/chronos/native
cp -av /home/chronos/chromium/* /home/chronos/native
rm -rf /home/chronos/native/lib/firmware
rm -rf /home/chronos/native/lib/modules/
cp -av /home/chronos/local/firmware /home/chronos/native/lib/
cp -av /home/chronos/local/lib/modules /home/chronos/native/lib/modules
```
Now that both ChromeOS and Chromium Native are updated, type in "sync", hit enter, and than once you regain the ability to type a command in the terminal reboot your system, and boot into your now upgraded ChromeOS machine. It is important that you use this method, as updating ChromeOS via the update function built in will not work properly, and will try to update the 3rd partition, which is Chromium native. ChromeOS cannot be booted at this point. It is best to follow the instructions outlined here when updating.

It is not clear whether you need to update Chromium native to have a bootable, upgraded version of ChromeOS. For now, updating Chromium is optional until we know more.

## Automated script to make all the process
Working in this

## Credits:
  - [allanin](https://github.com/allanin) for all of his ideas on Arnoldthebat discussion, most part of the code here is from him
  - [TCU14](github.com/TCU14) for the upgrade part
  - Dnim Ecaep from the [Telegram Group](https://t.me/chromeosforpc) for the shell command to change the SELINUX to permissive
  - Diogo from the [Telegram Group](https://t.me/chromeosforpc) for the corrections on the firmware migration
  - ++ some more that I will add soon
