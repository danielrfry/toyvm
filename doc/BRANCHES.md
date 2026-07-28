# Branches

toyvm branches are independent, mutable copies of a VM's full state: kernel,
initrd, disk images, and configuration. Branches are created efficiently using
the APFS `clonefileat` copy-on-write operation. On non-APFS volumes, toyvm falls
back to a regular directory copy.

## Concepts

- Every VM bundle starts with a branch named `main`.
- Exactly one branch is active. The `start` and `config` commands operate on it.
- Branches form a flat collection. toyvm does not record the source of a branch
  after it is created.
- Any branch can be selected, renamed, or used as the source for another branch.

## Branch operations

| Command | Description |
|---|---|
| `toyvm branch ls <vm>` | List all branches |
| `toyvm branch create <vm> <name> [--from <branch>]` | Create and select a new branch |
| `toyvm branch select <vm> <name>` | Set the active branch |
| `toyvm branch rename <vm> <old> <new>` | Rename a branch |
| `toyvm branch delete <vm> <name>` | Delete a non-active branch |

`create` clones the active branch unless `--from` names another branch. The new
branch is writable and becomes active.

`delete` always requires a branch name and confirmation. The active branch
cannot be deleted; select another branch first. Because there is no special root
branch, `main` can be renamed or deleted once another branch is active.

## Read-only branches

Mark the active branch read-only with:

```sh
toyvm config myvm --read-only
```

While read-only:

- The VM cannot be started on the branch.
- Its configuration cannot be changed.
- The branch cannot be deleted.
- It can still be selected, renamed, or used as the source for a new branch.
- A branch cloned from it starts writable.

Clear the flag with `toyvm config myvm --no-read-only`. Read-only branches are
shown with `[ro]` in `toyvm branch ls`.

## Typical workflows

### Saving a known-good state

```sh
# Save main's current state and continue work on the new branch
toyvm branch create myvm work
toyvm start myvm

# Return to the saved state
toyvm branch select myvm main
```

### Keeping a read-only baseline

```sh
toyvm config myvm --read-only
toyvm branch create myvm work
toyvm start myvm
```

### Exploring multiple alternatives

```sh
toyvm branch create myvm experiment-a
toyvm branch create myvm experiment-b --from main

toyvm branch select myvm experiment-a
toyvm start myvm
toyvm branch select myvm experiment-b
toyvm start myvm
```

## Existing bundles

Bundles created by earlier versions may contain parent relationships between
branches. toyvm accepts those bundles but treats every stored branch as
independent. Parent information is discarded the next time branch metadata is
saved.
