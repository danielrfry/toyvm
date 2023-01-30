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
Download the pre-built Debian virtual machine from [debian-vm-build Releases](https://github.com/danielrfry/debian-vm-build/releases).

Unpack the kernel, initrd and root filesystem images:
```
cd ~/toyvm
tar -xvjf debian-vm-aarch64_*.tar.bz2 
```

## Booting the virtual machine
Start the virtual machine:
```
toyvm -i ~/toyvm/initrd.img-4.19.160 -k ~/toyvm/vmlinuz-4.19.160 -d ~/toyvm/debian-rootfs-aarch64.img 'root=/dev/vda1 console=hvc0 nosplash'
```
Log in as `root` with password `password`.
