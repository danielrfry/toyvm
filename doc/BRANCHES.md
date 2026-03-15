# Branches

toyvm supports a Git-like branching model for VM snapshots. Branches are efficient copy-on-write clones of a VM's full state (kernel, initrd, disk images and configuration), created using the APFS `clonefileat` system call. On non-APFS volumes, a regular directory copy is made instead.

## Concepts

- Every VM bundle has a **branch tree** rooted at the `main` branch, which is created automatically by `toyvm create`.
- Exactly one branch is the **active branch** at any time. The `start` and `config` subcommands always operate on the active branch.
- Only **leaf branches** (branches with no children) may be active.

## Branch operations

| Command | Description |
|---|---|
| `toyvm branch ls <vm>` | List all branches (tree view) |
| `toyvm branch create <vm> <name> [--from <branch>]` | Create a new branch |
| `toyvm branch select <vm> <name>` | Set the active branch |
| `toyvm branch rename <vm> <old> <new>` | Rename a branch |
| `toyvm branch delete <vm> [<name>]` | Delete a branch and all its descendants |
| `toyvm branch revert <vm> [<name>]` | Revert a branch to its parent's current state |
| `toyvm branch commit <vm> [<name>]` | Promote a branch onto its parent, then delete it |

`delete`, `revert`, and `commit` default to operating on the active branch when no name is given.

## Constraints

These constraints follow from the copy-on-write model:

- **Only leaf branches can be active.** A branch with children cannot be selected.
- **`commit` requires a leaf with a sole-child parent.** The branch must have no children, and its parent must have no other child branches. This ensures the commit is unambiguous.
- **`delete` is recursive.** Deleting a branch also deletes all its descendants. If the active branch falls within the deleted subtree, the parent of the deleted branch becomes the new active branch — but only if it has no other child branches.
- **The root branch (`main`) cannot be deleted.**

## Read-only branches

A branch can be marked read-only using `toyvm config <vm> --read-only`. While read-only:

- The VM **cannot be started** on this branch.
- The VM **configuration cannot be changed** (`config` rejects all modification options).
- The branch **cannot be reverted or deleted**.
- Other branches **cannot be committed onto** a read-only branch.
- **Creating a child branch from a read-only branch is allowed.** The new branch starts writable.

Clear the flag with `toyvm config <vm> --no-read-only`.

Read-only branches are shown with a `[ro]` marker in `toyvm branch ls`.

## Typical workflows

### Saving a known-good state

```sh
# Working on 'main'; save current state before risky changes
toyvm branch create myvm checkpoint

# 'checkpoint' is now active; do work on it
toyvm start myvm

# If things go wrong, revert to the saved state
toyvm branch revert myvm

# If things go well, commit back to main
toyvm branch commit myvm
```

### Keeping a read-only baseline

```sh
# Mark the initial state of 'main' as read-only
toyvm config myvm --read-only

# All work is done on child branches
toyvm branch create myvm work
toyvm start myvm
```

### Exploring multiple options in parallel

```sh
toyvm branch create myvm experiment-a
toyvm branch create myvm experiment-b --from main

# Switch between them
toyvm branch select myvm experiment-a
toyvm start myvm
toyvm branch select myvm experiment-b
toyvm start myvm
```
