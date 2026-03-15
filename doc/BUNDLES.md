# VM Bundles

A VM bundle is a directory (with a `.bundle` suffix) that contains everything needed to run a VM: the kernel and optional initrd images, disk images, and a configuration file.

## Bundle structure

```
myvm.bundle/
  bundle.plist          ← Branch metadata (active branch, branch tree)
  branches/
    main/               ← Initial branch created by 'toyvm create'
      config.plist      ← VM configuration (CPUs, memory, devices, etc.)
      kernel/           ← Kernel image
      initrd/           ← Initrd image (if present)
      disks/            ← Disk image files
```

Additional branches appear as sibling directories alongside `main/`. See [Branches](BRANCHES.md) for details.

## VM name shortcuts

Wherever a VM bundle path is expected on the command line, you can use either a full path or a bare VM name:

| Argument | Interpretation |
|---|---|
| `myvm` | `~/.toyvm/myvm.bundle` |
| `myvm.bundle` | `./myvm.bundle` (path as given) |
| `./myvm` | `./myvm` (path as given) |
| `/path/to/myvm.bundle` | `/path/to/myvm.bundle` (path as given) |

A bare name (no `/` separator and no `.bundle` suffix) is looked up in `~/.toyvm/`. When creating a VM with a bare name, the `~/.toyvm/` directory is created automatically if it does not exist.

`toyvm ls` lists the names of all VMs in `~/.toyvm/`.

## Disk image formats

toyvm supports two disk image formats. The format is specified as a prefix to the size when creating a disk image:

| Prefix | Format | Extension | Notes |
|---|---|---|---|
| *(none)* or `raw:` | Raw sparse file | `.img` | Default; created with `truncate` |
| `asif:` | Apple Sparse Image Format | `.asif` | More efficient on APFS; created with `diskutil` |

### Examples

```sh
# Raw disk image (default)
toyvm create --disk 20G myvm --kernel vmlinuz

# ASIF disk image
toyvm create --disk asif:20G myvm --kernel vmlinuz

# Add another disk to an existing bundle
toyvm config myvm --disk asif:10G
```

Sizes can be specified using `K`, `M`, `G`, or `T` suffixes (powers of 1024, e.g. `20G` = 21,474,836,480 bytes).

## Configuration file

`config.plist` inside each branch directory is a property list encoding of the VM configuration. It stores:

- Kernel and initrd filenames (relative to the branch directory)
- Kernel command line
- List of disk images (filename, read-only flag, format)
- List of directory shares (tag, path, read-only flag)
- CPU count, memory size
- Enabled/disabled flags for network, audio, and Rosetta
