#  Toy Linux VM using Virtualization.framework

toyvm is a toy virtual machine that runs Linux on macOS using Apple's [Virtualization framework](https://developer.apple.com/documentation/virtualization). It supports Apple Silicon and Intel Macs running macOS Monterey or later.

There's a short video demo of toyvm running Debian on an M1 Mac mini [here](https://www.youtube.com/watch?v=zXqVAUl7T4k).

As well as toyvm itself, kernel, initial ram disk and root filesystem images are needed to build a working system. See [debian-vm-build](https://github.com/danielrfry/debian-vm-build) for pre-built ones for Debian Buster on Apple Silicon, and the scripts used to produce them.

## Documentation

- [Installation Guide](doc/INSTALL.md)
- [Command Reference](doc/COMMANDS.md)
- [VM Bundles](doc/BUNDLES.md)
- [Branches](doc/BRANCHES.md)

## Quick start

Create a VM bundle and start it:

```sh
toyvm create --kernel vmlinuz --initrd initrd.img --disk 20G myvm \
    root=/dev/vda1 console=hvc0 nosplash
toyvm start myvm
```

List all VMs stored in `~/.toyvm`:

```sh
toyvm ls
```

> **Note:** Use `--` to separate toyvm options from kernel arguments that begin with `-`
> (e.g. `toyvm start myvm -- -single`).
