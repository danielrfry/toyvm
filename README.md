#  Toy Linux VM using Virtualization.framework
This is a toy virtual machine built using Apple's Virtualization framework, that is capable of running Linux on macOS Monterey on Apple Silicon and Intel Macs.

[Installation Guide](doc/INSTALL.md)

There's a short video demo of toyvm running Debian on an M1 Mac mini [here](https://www.youtube.com/watch?v=zXqVAUl7T4k).

As well as toyvm itself, kernel, initial ram disk and root filesystem images are needed to build a working system. Please see [debian-vm-build](https://github.com/danielrfry/debian-vm-build) for pre-built ones for Debian Buster on Apple Silicon, and the scripts used to produce them.

```
USAGE: toyvm --kernel <kernel> [--initrd <initrd>] [--disk <disk> ...]
             [--disk-ro <disk-ro> ...] [--share <share> ...] [--share-ro <share-ro> ...]
             [--cpus <cpus>] [--memory <memory>] [-a] [--no-net] [--enable-rosetta]
             [<kernel-command-line> ...]

ARGUMENTS:
  <kernel-command-line>   Kernel command line (default: console=hvc0)

OPTIONS:
  -k, --kernel <kernel>   Path to the kernel image to load [required]
  -i, --initrd <initrd>   Path to an initrd image to load
  -d, --disk <disk>       Add a read/write virtual storage device backed by the
                          specified raw disk image file
  -r, --disk-ro <disk-ro> As --disk but adds a read-only storage device
  -s, --share <share>     Add a directory share device; accepts [tag:]path
                          (tag defaults to "share")
  -t, --share-ro <share-ro>
                          As --share but adds a read-only directory share
  -p, --cpus <cpus>       Number of CPUs to make available to the VM (default: 2)
  -m, --memory <memory>   Amount of memory in gigabytes to reserve for the VM
                          (default: 2)
  -a, --audio             Enable virtual audio device
  --no-net                Do not add a virtual network interface
  --enable-rosetta        Enable the Rosetta directory share in the guest OS
  -h, --help              Show help information.
```

> **Note:** Use `--` to separate toyvm options from kernel command line arguments
> that begin with `-` (e.g., `toyvm -k kernel -- -single`).
