# Installing
## Requirements
Building toyvm requires Xcode, available from the [Mac App Store](https://apps.apple.com/app/xcode/id497799835). Ensure it is installed, and opened at least once to install the command-line tools, before following this guide.

## Installing toyvm
Create a directory for the build:
```
mkdir ~/toyvm
```

Check out the source code:
```
cd ~/toyvm
git clone https://github.com/danielrfry/toyvm.git
```

Compile:
```
cd toyvm
xcodebuild -project toyvm.xcodeproj -target toyvm -configuration Release
```

Create the destination directory and copy the toyvm executable:
```
sudo mkdir -p /usr/local/bin
sudo cp build/Release/toyvm /usr/local/bin
```

## Installing the virtual machine
Download the pre-built Debian virtual machine:
```
cd ~/toyvm
curl -O https://media.githubusercontent.com/media/danielrfry/debian-vm-aarch64/main/debian-rootfs-aarch64.tar.bz2
curl -O https://media.githubusercontent.com/media/danielrfry/debian-vm-aarch64/main/initrd.img-4.19.160
curl -O https://media.githubusercontent.com/media/danielrfry/debian-vm-aarch64/main/vmlinuz-4.19.160
```

Unpack the disk image:
```
tar -xvjf debian-rootfs-aarch64.tar.bz2
```

## Booting the virtual machine
Start the virtual machine:
```
toyvm -i ~/toyvm/initrd.img-4.19.160 -k ~/toyvm/vmlinuz-4.19.160 -d ~/toyvm/debian-rootfs-aarch64.img 'root=/dev/vda1 console=hvc0 nosplash'
```
Log in as `root` with password `password`.
