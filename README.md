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
rm -rf /home/chronos/local/lib/modules/ 
cp -av /lib/firmware /home/chronos/local/lib/
cp -av /lib/modules/ /home/chronos/local/lib/
rm -rf /home/chronos/local/etc/modprobe.d/alsa-skl.conf
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
Note: Replace "chronos" with the your username if dual booting or the name of the of distribution if booting from USB

Find and download the updated recovery image for the device you used at chrome.qwedl.com

Now type in the following commands in the Linux terminal:
```sh
losetup -fP /home/chronos/user/Downloads/chromeos.bin
mount /dev/sda5 /home/chronos/local
```
Now type losetup to get a list of Loop devices, find the one that corresponds to your ChromeOS Image and than type:
```sh
mount /dev/loop{number}p3 /home/chronos/image -o loop,ro
```

## Updating both ChromeOS and Chromium Native: The actual upgrade
Remember, the commands outlined here must be done in EXACTLY this order to guarantee everything goes smoothly. IF you don't do this and find neither the touchscreen, trackpad, or keyboard works, that's on you. Not me, or anyone else.

```sh
rm -rf /home/chronos/local/*
cp -av /home/chronos/image/* /home/chronos/local
rm -rf /home/chronos/local/lib/firmware
rm -rf /home/chronos/local/lib/modules/
cp -av /home/chronos/native/lib/firmware /home/chronos/local/lib/
cp -av /home/chronos/native/lib/modules /home/chronos/local/lib/
rm -rf /home/chronos/local/etc/modprobe/alsa-.conf
```
(Alsa-* being whatever the config name is, in my case it would be Alsa-skl.conf)

Change in /home/chronos/local/etc/selinux/config the word enforcing to permissive with the following command:
```sh
sudo sed '0,/enforcing/s/enforcing/permissive/' -i /home/chronos/local/etc/selinux/config
```

## Automated script to make all the process
[Installation script](https://raw.githubusercontent.com/imperador/chromefy/master/chromefy.sh)
- Syntax: sudo bash chromefy.sh (partition of Chromium root, eg /dev/sda3) /path/to/desired/recovery/image /path/to/tpm1.2/recovery/image (This is optional, you only need to use the second argument and leave the third blank if you aren't experiencing login issues)
- Must be run from a live Chromium USB, do not run it on an already existing Chromium installation

## Bypassing TPM for select recovery images (Eve, Fizz, etc)
- [Instructions](https://docs.google.com/document/d/1mjOE4qnIxUcnnb5TjexQrYVFOU0eB5VGRFQlFDrPBhU/edit)
(Done automatically using the script above so long as your second argument is a TPM2.0 image(Such as Eve or Fizz) and the third argument is a platform1.2 image (Such as Asuka or Caroline
- The reason we need to bypass TPM2.0 for newer recovery images is because these images fail to login otherwise, or may get stuck in a login loop. Images such as Sentry, Asuka, and Caroline are using TPM1.2 which allows login to go successfully

## Using ChromeOS with other operating systems
Not everyone is willing to wipe their hard drives just to install [ArnoldTheBats Chromium](https://chromium.arnoldthebat.co.uk/index.php?dir=special&order=modified&sort=desc) as a base, and for those people we have made a handy multiboot guide. You can check it out here:
[MultiBoot Guide](https://docs.google.com/document/d/1uBU4IObDI8IFhSjeCMvKw46O4vKCnfeZTGF7Jx8Brno/edit?usp=sharing)

Chainloading is not a requirement with ArnoldTheBats Chromium, however you may need to when you make the initial Chromefy upgrade. Also remember to save your partition layout in between upgrades to newer ChromeOS versions, and also when you initially upgrade to ChromeOS otherwise it will not find the State partition which is needed for a successful boot.


## Credits:
  - [imperador](https://github.com/imperador) for the chromefy idea and the scripts
  - [TCU14](https://github.com/TCU14) for upgrading, and the MultiBoot guide
  - [alesimula](https://github.com/alesimula) for the installation script and also for the XDA Tutorial
  - Diogo from the [Telegram Group](https://t.me/chromeosforpc) for the corrections on the firmware migration and also for creating and managing the Telegram Group
  - [sublinhado](https://github.com/sublinhado) for writing down the steps needed for the TPM bypass method
  - Dnim Ecaep from the [Telegram Group](https://t.me/chromeosforpc) for the shell command to change the SELINUX to permissive
  - Danii from the [Telegram Group](https://t.me/chromeosforpc) for the work on the TPM bypass method

## Big Thanks:
  - [allanin](https://github.com/allanin) for all of his ideas on Arnoldthebat discussion, most part of the scripts here is based on his ideas
  - [arnold](https://chromium.arnoldthebat.co.uk) for his awesome builds
  - ++ some more that I will add soon (remind me if I forgot someone)
