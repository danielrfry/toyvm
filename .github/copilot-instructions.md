# toyvm Copilot instructions

## Build commands

- This repository is an Xcode project for a single macOS command-line target: `toyvm`.
- Release build (documented in `doc/INSTALL.md`):
  ```bash
  xcodebuild -project toyvm.xcodeproj -target toyvm -configuration Release
  ```
- Debug build:
  ```bash
  xcodebuild -project toyvm.xcodeproj -target toyvm -configuration Debug
  ```
- The checked-in project does not define any test targets or lint targets. There is no single-test command in the current repo.
- Builds require full Xcode with `xcode-select` pointed at the Xcode developer directory, not just Command Line Tools.

## High-level architecture

- `toyvm/main.m` contains nearly all application logic. It is both the CLI entrypoint and the VM assembly layer.
- The program parses command-line flags with `getopt_long`, converts them into `Virtualization.framework` device/configuration objects, validates the resulting `VZVirtualMachineConfiguration`, then starts the VM and hands control to the main run loop.
- Helper functions in `main.m` each build one kind of device/configuration:
  - storage devices from raw disk images
  - directory shares from `tag:path` arguments
  - NAT networking
  - optional audio
  - optional Rosetta directory sharing on Apple Silicon + macOS 13+
- The boot path is Linux-specific: a `VZLinuxBootLoader` is always created from `--kernel`, optionally gets `--initrd`, and uses remaining positional arguments as the kernel command line. If no kernel command line is provided, it defaults to `console=hvc0`.
- VM lifecycle shutdown/error handling is intentionally split out into `toyvm/ToyVMDelegate.{h,m}`. The delegate stores any stop error and stops the main `CFRunLoop`, which lets `main.m` restore terminal state before exiting.
- `toyvm.entitlements` is required for the app to use Apple virtualization APIs. The Xcode target is configured to sign with that entitlement file.

## Key conventions

- Treat `main.m` as the authoritative place for behavior changes. There is no separate model/controller layer; option parsing, defaults, and Virtualization.framework wiring all live together there.
- Keep CLI behavior aligned between `usage()` in `main.m` and `README.md`. The README usage block is effectively duplicated from the source and should be updated when flags change.
- Directory shares are accumulated in a mutable dictionary keyed by share tag, then assigned via `[sharedDirs allValues]`. Reusing a tag replaces the earlier share definition.
- `--share` and `--share-ro` accept either `tag:path` or just `path`; when the tag is omitted, the code uses `share`. Paths may still contain additional `:` characters because only the first component is treated as the tag.
- Terminal handling is part of normal VM startup/shutdown: `stdin` is switched to raw mode before `CFRunLoopRun()` and restored after the VM stops. Any exit-path changes should preserve terminal restoration.
- Error handling is explicit and early-return based. Helper functions log the underlying `NSError` and return failure so `main()` can abort immediately instead of continuing with a partial configuration.
- Rosetta support is guarded twice: compile/runtime architecture checks and an `@available(macOS 13.0, *)` check. Keep both when changing that path.
- The repo expects external guest artifacts rather than generating them locally. Kernel, initrd, and rootfs images come from outside this repository (see `README.md` / `doc/INSTALL.md`).
