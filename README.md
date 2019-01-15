# chromefy
Transforming Chromium to Chrome

You can find us at the Telegram Group:
https://t.me/chromeosforpc
   > Please, ask your questions at the group and don't PM the admins. :)
   
You can also follow us on Twitter: https://twitter.com/chromefy

## Observations

  - You need a Chromium installation running for the Methods 2 and 3
    > We strongly recommend using [ArnoldTheBats Chromium](https://chromium.arnoldthebat.co.uk/index.php?dir=special&order=modified&sort=desc) Stable builds.
    > Just deploy the img to a USB Stick, [Rufus](https://rufus.ie/en_IE.html) and similar programs will do the work.
  - You have to be logged in (because if you don't, the initial setup won't work).
  - We are not responsible for any damage made to your computer by you or by your dog.
  - If you are using a Chromebook, you do not need to install Chromium. Just grab a suitable recovery image and follow the      installation instructions while in ChromeOS native.
  - Don't use zip files. Extract and use the BIN file that is inside of it

---

## Required Files

  - An [official Chrome OS recovery image](https://cros-updates-serving.appspot.com) (downloads on the right; RECOMMENDED: eve for mid/high resolution displays, pyro for (very) low-res displays). It must be from the same chipset family (Ex: Intel, ARM or RockChip)
    > You can use [THIS LIST](https://www.chromium.org/chromium-os/developer-information-for-chrome-os-devices) to search for your processor, and then look at the internet which one is the best (the closest, the better).
  - The TPM2 emulator (swtpm.tar) (not compatible with all Chromium kernels) or another Chrome OS recovery image from a TPM 1.2 device (EX: caroline); this is only needed if using an image from TPM2 device to fix a login issue, which is most likely the case for newer ones. (If you don't know which TPM1.2 image to choose, just pick caroline)
  - An image from a Chromium OS distribution (EX: [ArnoldTheBats Builds](https://chromium.arnoldthebat.co.uk/index.php?dir=special&order=modified&sort=desc)).
   - The [Chromefy installation script](https://github.com/imperador/chromefy/releases/download/v1.1/chromefy.sh) (for the Method 1 and Method 2, the easy ways).

## Installation Methods

Chromefy has three installation options. The first option generates an img ready to deploy into your usb stick and then you can boot from it to install Chrome at your computer. The last two options will probably require you to resize the third partition of your sdX drive (EX: sda3 inside sda) from its current size to atleast 4GB; I suggest using Gparted live USB to resize it; 

### Option 1: Automated generation of Chrome img
  - It uses a script and you don't need to resize partitions.
  - Requires: One computer running Linux or Chromium.
  - It will generate a Chrome img ready to install.

### Option 2-A: Automated Script (drive)
  - It uses a script, so the migration is easier.
  - Requires: 2 USB sticks: The first to deploy the Chromium img on it and the second to store the two recovery files.
  - The script can downsize your sdX5 drive and resize sdX3 with the generated free space (will ask first).
  
### Option 2-B: Automated Script (partition)
  - It uses a script, so the migration is easier.
  - Requires: 2 USB sticks: The first to deploy the Chromium img on it and the second to store the two recovery files.
  - As said before, you will need to resize the third partition of your sdX drive (EX: sda3 inside sda, if your main drive is sda). In this method you can either downsize sdX1 (data partition) or delete the sdX5 partition (we won't need it) to get more unallocated space.

### Option 3: Manual Configuration
  - It requires some patience and more commands. And it also has several steps that need to be done.
  - It can be done with only one USB stick.
  - Here you can't just delete the fifth (sdX5) partition, because you will need it.
 
Choose the best method for you and follow the installation process.

---

## Installation Process

With the automated script method you can either generate your own Chrome img ready to run and install (Option 1) or you can also apply the Chrome into a installed Chromium at your computer (Option 2). I strongly suggest you to use the first one, because it will also allows you to have a backup img to deploy anytime you want to install it on a new pc.


### Option 1: Automated Script - Generating your own Chrome img:

Here you will generate your img and then deploy it to a usb stick, this will allow you to install it on your computer. If you already have a Chromefy-generated ChromeOS img, you can deploy it to a usb stick, boot from it at your computer and then jump to the ***Installing an img at your computer***. We won't provide the imgs.

#### Generating the img

Log into a Linux or Chromium OS computer. Download your Chromium image (e.g Arnold the bat), your ChromeOS recovery image (e.g Eve), TPM2 emulator (swtpm.tar) or TPM1.2 ChromeOS recovery image (e.g Caroline [https://cros-updates-serving.appspot.com]) and the Chromefy.sh script (https://github.com/imperador/chromefy/releases/download/v1.1/chromefy.sh). Place all the files in one location. Downloads is a good idea.

In the next step you need to replace '{path}' with the location of all these files. If you put them in Downloads then {path} would be replaced with 'home/chronos/user/Downloads'.
If the files are in another folder, replace it with the other folder location. If you don't know how to discover the path, internet is your friend, you can learn how to discover it.
> Note: Your original chromium.img file will be replaced, so backup it if you want

Now open a terminal (if you’re using ChromiumOS press CTRL + ALT + T, then type the command shell.) For any other Linux OS a normal terminal is fine, and then type the following commands:

```sh
sudo su
cd {path}
sudo  bash  chromefy.sh  chromium.img  recovery.bin  caroline.bin
```
or
```
sudo  bash  chromefy.sh  chromium.img  recovery.bin  swtpm.tar
```

  > Reminder: {path} is the folder where you saved your files

After finishing the process, you will have the **chromium.img**. It is now a full ChromeOS img. You can use any program to deploy it to a usb stick and boot from it. Programs like [Etcher](https://www.balena.io/etcher/) (Windows or Linux), [Rufus](https://rufus.ie/en_IE.html) (Windows only) and [Chromebook Recovery Utility](https://chrome.google.com/webstore/detail/chromebook-recovery-utili/jndclpdbaamdhonoechobihbbiimdgai?hl=en) (Chromium only) will do the work. Just deply the img to your usb stick.

#### Installing an img at your computer

If you already have a Chromefy-generated ChromeOS img, you can deploy it to a usb stick and then just boot from it at your computer.

When the login screen appears, press "CTRL + ALT + F2" and type the following commands:

```sh
chronos
sudo su
cd /
sudo   /usr/sbin/chromeos-install  --dst  /dev/sda  --skip_postinstall
```

When the process finish, turn off your computer, remove your usb stick and turn it on again. It will boot into your Chrome OS device. Congratulations!

#### Fixing Grub

If it doesn't work after your reboot. Just boot into your USB stick again, make sure you have an internet connection, go to the shell command line and type this command:

```sh
curl  -L  https://goo.gl/HdjwAZ   |  sudo  bash  -s  /dev/sda
```

### Option 2: Automated Script - Applying Chrome to Chromium:

Flash the selected **Chromium** OS build on the first USB, boot into the live USB and install it on your HDD/SSD by typing the following command on the shell (keep in mind this will wipe your HDD, so backup everything you need and don't blame us later)
```sh
sudo /usr/sbin/chromeos-install --dst YOURDRIVE (Ex: /dev/sda)
```
- Now make sure that your chromium HDD/SSD installation is working before proceeding. Also save your chosen recovery image (that we will be calling chosenImg.bin), swtpm.tar or caroline recovery image (here called carolineImg.bin) and the [Installation script](https://github.com/imperador/chromefy/releases/download/v1.1/chromefy.sh) to the second USB stick.

OPTION 2B ONLY: Resize the third partition of your sdX drive (EX: sda3 inside sda) from its current size to atleast 4GB (suggestion: search about using Gparted live USB to resize it). And remember: You can either downsize sdX1 (data partition) or delete the sdX5 partition (we won't need it) to get more unallocated space. 

   > Multiboot users: You must use the ROOT-A partition instead of your third partition (sda3). 
   
After this, connect both USB sticks to you computer and boot from your live USB again (with Chromium), make sure you have your Chrome OS images available (on the second USB stick) and go to the folder where you downloaded the chromefy script and run it with the following command (considering your system partition as /dev/sda3):

OPTION 2A:
```sh
sudo bash chromefy.sh /dev/sda /path/to/chosenImg.bin /path/to/carolineImg.bin_OR_swtpm.tar
```
OPTION 2B:
```sh
sudo bash chromefy.sh /dev/sda3 /path/to/chosenImg.bin /path/to/carolineImg.bin_OR_swtpm.tar
```

Don't leave live USB yet, make a powerwash (manually) by typing

```sh
sudo mkfs.ext4 YOURDATAPARTITION(Ex: /dev/sda1)
```

You can now reboot and enjoy your new "chromebook"

---

### Option 3: Manual Configuration
 
After finishing installing a Chromium OS, open the browser and press CTRL+ALT+T to open chroot
Type:
```sh
shell
sudo su
```

Installing Chrome OS (some notes):
  - If the file is in Downloads folder, replace '{path}' with 'home/chronos/user/Downloads', if it is at another folder, replace it with the other folder location. Use the path accordingly with your file location
  - Save your chosen recovery image (that we will be calling chosenImg.bin) and caroline recovery image (here called carolineImg.bin) at this folder
  - Any password or username will be 'chronos'

#### Configuring the new Chrome partition

Use the following commands to configure the sda5 (or nvem0n1p5) and other basic things (the exemple is using caroline recovery file):
Type "lsblk" to know your partitions. Search for sda, sdb or nvme0n1 with the size of your usb or HDD. In the following commands, change "sda" for the one that you've found:
```sh
losetup -fP {path}/chosenImg.bin
mkdir /home/chronos/image
mkdir /home/chronos/local
mkfs.ext4 /dev/sda5
mount /dev/sda5 /home/chronos/local
```

#### Copying the img to the local path

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

  - Using ChromeOS with other Operating systems (Multiboot)
  - Updating ChromeOS (for the Method 2)
  - Resolving Problems With Login

---
## Using ChromeOS with other Operating systems (Multiboot)
Not everyone is willing to wipe their hard drives just to install [ArnoldTheBats Chromium](https://chromium.arnoldthebat.co.uk/index.php?dir=special&order=modified&sort=desc) as a base, and for those people we have made a handy multiboot guide. You can check it out here:
[MultiBoot Guide](https://docs.google.com/document/d/1uBU4IObDI8IFhSjeCMvKw46O4vKCnfeZTGF7Jx8Brno/edit?usp=sharing)

Chainloading is not a requirement with ArnoldTheBats Chromium, however you may need to when you make the initial Chromefy upgrade. Also remember to save your partition layout in between upgrades to newer ChromeOS versions, and also when you initially upgrade to ChromeOS otherwise it will not find the State partition which is needed for a successful boot.

---
## Updating ChromeOS (for the Method 3)
### Updating ChromeOS and Chromium Native: The Setup
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

### Updating both ChromeOS and Chromium Native: The actual upgrade
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
---

## Resolving Problems With Login
Bypassing TPM for select recovery images (Eve, Fizz, etc)
- [Instructions](https://docs.google.com/document/d/1mjOE4qnIxUcnnb5TjexQrYVFOU0eB5VGRFQlFDrPBhU/edit): Done automatically using the script above so long as your second argument is a TPM2.0 image(Such as Eve or Fizz) and the third argument is a platform1.2 image (Such as Asuka or Caroline)
- The reason we need to bypass TPM2.0 for newer recovery images is because these images fail to login otherwise, or may get stuck in a login loop. Images such as Sentry, Asuka, and Caroline are using TPM1.2 which allows login to go successfully

---

## Credits:
  - [imperador](https://github.com/imperador) for the chromefy idea and the scripts
  - [TCU14](https://github.com/TCU14) for upgrading, and the MultiBoot guide
  - [alesimula](https://github.com/alesimula) for the installation script and also for the XDA Tutorial
  - Diogo from the [Telegram Group](https://t.me/chromeosforpc) for the corrections on the firmware migration and also for creating and managing the Telegram Group
  - [sublinhado](https://github.com/sublinhado) for writing down the steps needed for the TPM bypass method
  - Dnim Ecaep from the [Telegram Group](https://t.me/chromeosforpc) for the shell command to change the SELINUX to permissive
  - Danii from the [Telegram Group](https://t.me/chromeosforpc) for the work on the TPM bypass method and TPM emulation method

## Big Thanks:
  - [allanin](https://github.com/allanin) for all of his ideas on Arnoldthebat discussion, most part of the scripts here is based on his ideas
  - [arnold](https://chromium.arnoldthebat.co.uk) for his awesome builds
  - ++ some more that I will add soon (remind me if I forgot someone)
