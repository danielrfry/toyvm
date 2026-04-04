# Command Reference

## toyvm ls

Lists the names of all VMs stored in `~/.toyvm`. Does nothing if the directory does not exist.

```
USAGE: toyvm ls
```

---

## toyvm create

Creates a new VM bundle. The kernel image (and optional initrd) are copied into the bundle. Disk images are created as sparse files inside the bundle. The configuration is saved to `config.plist` inside the bundle's initial `main` branch.

```
USAGE: toyvm create [<options>] <bundle> --kernel <kernel> [<kernel-command-line> ...]

ARGUMENTS:
  <bundle>                  VM name or path to the bundle directory to create
  <kernel-command-line>     Kernel command line (default: console=hvc0)

OPTIONS:
  -k, --kernel <kernel>     Path to the kernel image to copy into the bundle [required]
  -i, --initrd <initrd>     Path to an initrd image to copy into the bundle
  -d, --disk <spec>         Create a read/write disk image of the given size (e.g. 20G, 512M, asif:20G)
  -r, --disk-ro <spec>      As --disk but marks the disk image as read-only
  -s, --share <share>       Add a directory share; accepts [tag:]path (tag defaults to "share")
  -t, --share-ro <share>    As --share but adds a read-only directory share
  -p, --cpus <cpus>         Number of CPUs (default: 2)
  -m, --memory <memory>     Memory in gigabytes (default: 2)
  -a, --audio               Enable virtual audio device
  --no-net                  Disable the virtual network interface
  --enable-rosetta          Enable the Rosetta directory share in the guest OS
  -h, --help                Show help information
```

See [VM Bundles](BUNDLES.md) for details on the bundle format and disk image size specifications.

---

## toyvm start

Starts a VM. When a bundle is supplied, its stored configuration is used as the base. CLI options override the corresponding bundle settings. Options that enable features (`--audio`, `--enable-rosetta`) are additive; `--no-net` disables networking regardless of the bundle setting.

A VM cannot be started if the active branch is marked read-only. See [Branches](BRANCHES.md).

```
USAGE: toyvm start [<options>] [<bundle>]

ARGUMENTS:
  <bundle>                  VM name or path to a VM bundle

OPTIONS:
  -k, --kernel <kernel>     Path to the kernel image (required without a bundle)
  -i, --initrd <initrd>     Path to an initrd image
  -c, --cmdline <cmdline>   Kernel command line (default: console=hvc0)
  -d, --disk <disk>         Add a read/write storage device (path to a disk image)
  -r, --disk-ro <disk>      As --disk but adds a read-only storage device
  -s, --share <share>       Add a directory share; accepts [tag:]path (tag defaults to "share")
  -t, --share-ro <share>    As --share but adds a read-only directory share
  -p, --cpus <cpus>         Number of CPUs
  -m, --memory <memory>     Memory in gigabytes
  -a, --audio               Enable virtual audio device
  --no-net                  Disable the virtual network interface
  --no-persist              Use copy-on-write clones of disk images; originals are not modified
  --enable-rosetta          Enable the Rosetta directory share in the guest OS
  -h, --help                Show help information
```

> **Note:** Use `--` to separate toyvm options from kernel arguments that begin with `-`
> (e.g. `toyvm start myvm -- -single`).

---

## toyvm config

Displays the configuration of the active branch of a VM bundle. When options are given, they are applied before the configuration is displayed. Run without options to display the current configuration.

Configuration changes are not permitted on read-only branches. The `--read-only` and `--no-read-only` flags are the only exception — they may always be used regardless of the current read-only status.

```
USAGE: toyvm config [<options>] <bundle>

ARGUMENTS:
  <bundle>                      VM name or path to the VM bundle

KERNEL / INITRD:
  -k, --kernel <path>           Replace the kernel image with the file at the given path
  -i, --initrd <path>           Replace the initrd image with the file at the given path
      --remove-initrd           Remove the initrd image from the bundle
  -c, --cmdline <cmdline>       Set the kernel command line

DISKS:
  -d, --disk <spec>             Add a read/write disk image of the given size (e.g. 20G, asif:20G)
  -r, --disk-ro <spec>          As --disk but adds a read-only disk image
      --remove-disk <filename>  Remove a disk image by filename (e.g. disk0.img); prompts for confirmation

DIRECTORY SHARES:
  -s, --share <share>           Add or replace a directory share; accepts [tag:]path
  -t, --share-ro <share>        As --share but adds a read-only directory share
      --remove-share <tag>      Remove a directory share by tag

RESOURCES:
  -p, --cpus <cpus>             Set the number of CPUs
  -m, --memory <memory>         Set the amount of memory in gigabytes

ENABLE/DISABLE:
      --audio                   Enable the virtual audio device
      --no-audio                Disable the virtual audio device
      --net                     Enable the virtual network interface
      --no-net                  Disable the virtual network interface
      --enable-rosetta          Enable the Rosetta directory share
      --disable-rosetta         Disable the Rosetta directory share
      --read-only               Mark the active branch as read-only
      --no-read-only            Clear the read-only flag on the active branch

  -h, --help                    Show help information
```

---

## toyvm branch

Manages branches within a VM bundle. See [Branches](BRANCHES.md) for a full explanation.

```
USAGE: toyvm branch <subcommand>
```

### toyvm branch ls

Lists all branches in a tree view. The active branch is marked with `*`. Read-only branches are marked with `[ro]`.

```
USAGE: toyvm branch ls <vm>
```

Example output:
```
main [ro]
├── stable *
└── experimental
    └── wip
```

### toyvm branch create

Creates a new branch as a copy-on-write clone of an existing branch. The new branch is automatically selected as the active branch.

```
USAGE: toyvm branch create [--from <branch>] <vm> <name>

ARGUMENTS:
  <vm>              VM name or bundle path
  <name>            Name for the new branch

OPTIONS:
  --from <branch>   Branch to create from (default: active branch)
```

### toyvm branch select

Sets the active branch. Only leaf branches (branches with no children) may be selected.

```
USAGE: toyvm branch select <vm> <name>
```

### toyvm branch rename

Renames a branch. Updates all child branch references and the active branch pointer if needed.

```
USAGE: toyvm branch rename <vm> <old-name> <new-name>
```

### toyvm branch delete

Deletes a branch and all its descendants. Prompts for confirmation. The root branch cannot be deleted. Read-only branches cannot be deleted.

If the active branch is within the deleted subtree, the parent of the deleted branch becomes the new active branch (only possible if it has no other child branches after the deletion).

```
USAGE: toyvm branch delete [<vm>] [<name>]

  <name>  Branch to delete (default: active branch)
```

### toyvm branch revert

Reverts a branch to the current state of its parent branch, discarding all changes. Prompts for confirmation. Read-only branches cannot be reverted.

```
USAGE: toyvm branch revert <vm> [<name>]

  <name>  Branch to revert (default: active branch)
```

### toyvm branch commit

Copies the state of a branch onto its parent, then deletes the branch. Prompts for confirmation.

Constraints:
- The branch must be a leaf (no children).
- The parent must have no other child branches.
- Neither the branch nor its parent may be read-only.

```
USAGE: toyvm branch commit <vm> [<name>]

  <name>  Branch to commit (default: active branch)
```
