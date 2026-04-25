# toyvm Copilot instructions

## Build commands

This repository has three build targets:

### `toyvm` (CLI)

```bash
# SPM (requires only Command Line Tools):
swift build -c release --product toyvm
# Xcode (requires full Xcode):
xcodebuild -project toyvm.xcodeproj -scheme toyvm -configuration Release
```

The SPM binary at `.build/release/toyvm` requires manual codesigning with `toyvm.entitlements`.

### `ToyVMApp` (GUI app bundle)

```bash
# SPM:
swift build -c release --product ToyVMApp
# Xcode:
xcodebuild -project toyvm.xcodeproj -scheme ToyVMApp -configuration Release
```

**Always use `-scheme` not `-target` with `xcodebuild`** — target-based builds have package resolution issues.

### Both targets together

```bash
swift build
```

- No test or lint targets exist. There is no single-test command.
- New files in `ToyVMCore/` must be added to both the `toyvm` and `ToyVMApp` source build phases in `toyvm.xcodeproj/project.pbxproj`.
- New files in `ToyVMApp/` must be added to the `ToyVMApp` source build phase and to its group in `project.pbxproj`.

## Architecture overview

The project is split into three Swift targets:

### `ToyVMCore/` — shared library

UI-independent static library used by both CLI and GUI. All types are `public`. Key files:

- **`VMConfig.swift`** — `BootMode` enum (`.linux`, `.efi`, `.macOS`), `VMConfig` struct (all VM settings), `DiskConfig`, `ShareConfig`, `USBDiskConfig`. Has custom `init(from decoder:)` for backwards compatibility; add new fields with `decodeIfPresent` and a sensible default.
- **`VMBundle.swift`** — Loads/creates/saves VM bundles. Provides `CreateOptions`, branch operations (create, delete, revert, commit, rename, select), and macOS artifact URL helpers.
- **`BundleMeta.swift`** — Bundle-level metadata (`bundle.plist`): active branch name, branch tree with parent/child relationships and read-only flags.
- **`VirtualMachineBuilder.swift`** — Builds `VZVirtualMachineConfiguration` from a `VMBundle` or explicit parameters. Does **not** attach serial ports — the caller adds those. Returns a `VMStartContext` which includes `hasGraphicsDevice` (for display routing) and `cleanupPaths` (for no-persist mode).
- **`VMRunner.swift`** — `@Observable` VM lifecycle manager (`State`: `.stopped`, `.starting`, `.running`, `.stopping`, `.error(String)`). Wraps `VZVirtualMachine` and its delegate.
- **`MacOSInstallManager.swift`** — `@Observable` (macOS 14+, arm64 only). Orchestrates the full macOS guest installation: loads restore image, saves hardware model/machine identifier/auxiliary storage to the bundle, builds config, starts VM, runs `VZMacOSInstaller`.
- **`RestoreImageManager.swift`** — `@Observable` (macOS 14+, arm64 only). Downloads macOS restore images (.ipsw) from Apple via `VZMacOSRestoreImage.latestSupported` with progress tracking.
- **`ToyVMError.swift`**, **`DiskInfo.swift`** — Shared error type and disk image utilities.

### `toyvm/` — CLI target

Swift-argument-parser CLI. Entry point: `ToyVM.swift` (`@main struct ToyVM: AsyncParsableCommand`).

Subcommands:

- **`start`** — Starts a VM; connects serial port to stdin/stdout. Supports `--no-persist`. Sets stdin to raw mode before `CFRunLoopRun()` and restores it after.
- **`create`** — Creates a VM bundle. Flags: `--kernel`, `--initrd`, `--disk`, `--disk-ro`, `--usb`, `--usb-ro`, `--share`, `--share-ro`, `--cpus`, `--memory`, `--audio`, `--no-net`, `--enable-rosetta`, `--efi` (EFI boot mode), `--macos` + `--restore-image` (macOS guest, arm64 only). If `--macos` is used, runs `MacOSInstallManager` with stderr progress and deletes the partial bundle on failure.
- **`config`** — Displays current VM configuration.
- **`ls`** — Lists all VMs in `~/.toyvm`.
- **`branch`** — Branch management subcommands: `ls`, `create`, `delete`, `revert`, `commit`, `select`, `rename`.

CLI files use `#if canImport(ToyVMCore) / import ToyVMCore` for SPM vs Xcode single-target compatibility.

### `ToyVMApp/` — GUI target (macOS 15.0+)

SwiftUI macOS application built with `@Observable` throughout. Entry point: `ToyVMAppMain.swift`.

Key types:

- **`VMManager`** — `@Observable`. Discovers VM bundles in `~/.toyvm`, manages `VMSession` instances. Monitors `~/.toyvm` via a GCD `DispatchSource` for automatic list refresh. Deletes bundles to Trash via `NSWorkspace.shared.recycle()`.
- **`VMSession`** — `@Observable`. Runtime state for one VM: holds `VMBundle`, `VMRunner`, pipe pair for serial I/O, `displayMode` (`.terminal` or `.graphics`), `automaticDisplayResize` (runtime toggle, not persisted). Sets `displayMode` from `VMStartContext.hasGraphicsDevice` on start.
- **`VMRunner`** — (in ToyVMCore) Shared with CLI.

View hierarchy:

```
ToyVMAppMain (App)
└── ContentView (NavigationSplitView)
    ├── VMListView / VMRowView  (sidebar)
    └── VMDetailView            (detail)
        ├── configSummary       (when stopped)
        └── VMDisplayView
            ├── TerminalDisplayView  (SwiftTerm, for .linux boot)
            └── GraphicsDisplayView  (VZVirtualMachineView, for .efi / .macOS)
```

View files also include:

- **`FullScreenObserver.swift`** — Tracks macOS full screen state via `NSWindow` notifications; `FullScreenTracker` (NSViewRepresentable) attaches it to the window.
- **`CreateVMView.swift`** — VM creation sheet. Handles Linux, EFI, and macOS flows including restore image selection, "Download Latest from Apple" with progress/cancel, and macOS installation with `MacOSInstallManager`.
- **`ConfigEditView.swift`** — VM config edit sheet (resources, devices, boot mode, USB disks, directory shares).
- **`InstallationProgressView.swift`** — macOS installation progress with cancel.

Menu bar additions (in `ToyVMAppMain`):

- **File > New Virtual Machine…** (⌘N)
- **View > Automatic Display Resize** — toggles `VMSession.automaticDisplayResize` for `VZVirtualMachineView.automaticallyReconfiguresDisplay`; disabled when no graphics display is active.

## VM bundle structure

Bundles are stored in `~/.toyvm/<name>.bundle/`. Bundle layout:

```
<name>.bundle/
  bundle.plist          # BundleMeta: active branch, branch tree
  branches/
    <branchname>/
      config.plist      # VMConfig for this branch
      kernel/           # kernel image (Linux modes)
      initrd/           # initrd image (optional, Linux modes)
      disks/            # disk images (raw .img or .asif)
      efi-vars.fd       # EFI variable store (EFI mode)
      hardware-model.bin      # macOS guest (arm64)
      machine-identifier.bin  # macOS guest (arm64)
      auxiliary-storage.bin   # macOS guest (arm64)
```

Branches form a tree. The root branch has `parent == nil`. Only leaf branches can be the active branch. Branch operations (commit, revert, delete) manipulate disk image files and `BundleMeta` atomically.

## Boot modes

| Mode     | Boot loader         | Display                           | Notes                                                                |
| -------- | ------------------- | --------------------------------- | -------------------------------------------------------------------- |
| `.linux` | `VZLinuxBootLoader` | Terminal (serial)                 | Kernel + optional initrd required                                    |
| `.efi`   | `VZEFIBootLoader`   | Graphics (`VZVirtualMachineView`) | ISO/USB install media supported                                      |
| `.macOS` | `VZMacOSBootLoader` | Graphics (`VZVirtualMachineView`) | arm64 only; requires hardware model + machine ID + auxiliary storage |

## Fullscreen behaviour (ToyVMApp)

`ContentView` manages fullscreen behaviour via `FullScreenObserver` and `columnVisibility`:

- **VM stopped / no VM**: toolbar permanently visible, default window background, sidebar visible.
- **VM running (windowed)**: toolbar permanently visible, sidebar state user-controlled.
- **VM running (fullscreen)**: toolbar auto-hides (appears on hover), window background black (sidebar blends with menu bar), sidebar auto-hides when entering fullscreen or starting a VM while in fullscreen, auto-shows when the VM stops.
- Sidebar auto-adjustment only happens in fullscreen mode; windowed mode never automatically changes sidebar visibility.

## Key conventions

- **Serial ports**: `VirtualMachineBuilder` never adds serial ports. The CLI attaches stdin/stdout; the GUI attaches a pipe pair fed to SwiftTerm. Add serial port config after calling `buildConfiguration(from:)`.
- **macOS auxiliary storage**: The `VZMacAuxiliaryStorage` object created via `creatingStorageAt:` during installation must be passed directly to the platform config — re-reading it immediately with `contentsOf:` causes DiskImages error 45. On subsequent boots (non-install), use `contentsOf:`.
- **Backwards compatibility**: `VMConfig` has a custom `init(from decoder:)`. Always add new fields via `decodeIfPresent` with a default value.
- **Directory shares**: Tag is the first `:` component; path may contain further `:` characters. Reusing a tag silently replaces the prior share.
- **Error handling**: Explicit and early-return based throughout. Helper functions throw/return failure so callers abort immediately.
- **Rosetta**: Guarded by both `#if arch(arm64)` compile-time check and `@available(macOS 13.0, *)` runtime check.
- **Bundle deletion**: Always use `NSWorkspace.shared.recycle()` for user-initiated deletion (moves to Trash). Use `FileManager.removeItem` only for cleanup of partial/failed bundles.
- **Platform minimums**: ToyVMCore minimum is macOS 13; CLI minimum is macOS 12; ToyVMApp minimum is macOS 15 (required for `.windowToolbarFullScreenVisibility`).
- **Guest artifacts**: Kernel, initrd, and rootfs disk images come from outside this repository (see `README.md` / `doc/INSTALL.md`).

## General considerations

- When verifying a change, build both CLI and GUI targets, using both SPM and Xcode (preferably via the MCP server if possible).
- Use the Xcode MCP server, if available, to make modifications to the Xcode project.
- After making each change and successfully verifying the build, commit with a descriptive message. For larger changes, consider breaking them into multiple commits for easier review.
