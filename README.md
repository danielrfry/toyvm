#  Toy Linux VM using Virtualization.framework
![Build](https://github.com/danielrfry/toyvm/workflows/Build/badge.svg)

This is a toy virtual machine built using Apple's Virtualization framework, that is capable of running Linux on macOS Big Sur on Apple Silicon and Intel Macs.

[Installation Guide](doc/INSTALL.md)

There's a short video demo of toyvm running Debian on an M1 Mac mini [here](https://www.youtube.com/watch?v=zXqVAUl7T4k).

As well as toyvm itself, kernel, initial ram disk and root filesystem images are needed to build a working system. Please see [debian-vm-aarch64](https://github.com/danielrfry/debian-vm-aarch64) for pre-built ones for Debian Buster on Apple Silicon. The scripts used to produce these are also available at [debian-vm-build](https://github.com/danielrfry/debian-vm-build).

```
usage: toyvm [options] [kernel command line]

Options:
  -k --kernel <path>       Path to the kernel image to load [required]
  -i --initrd <path>       Path to an initrd image to load
  -d --disk <path>         Add a read/write virtual storage device backed by the
                           specified raw disk image file
  -r --disk-ro <path>      Add a read-only virtual storage device backed by the
                           specified raw disk image file
  -p --cpus <number>       Number of CPU (core)s to make available to the VM
                           (default: 2)
  -m --memory <amount>     Amount of memory to reserve for the VM in gigabytes
                           (default: 2)
```
