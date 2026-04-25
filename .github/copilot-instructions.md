# toyvm Copilot instructions

Keep this file focused on repo-specific conventions and gotchas that are not obvious from a quick read of the code.

## Build and validation

- Prefer `swift build` for routine validation.
- For target-specific validation, use `swift build --product toyvm` or `swift build --product ToyVMApp`.
- Use Xcode builds when a change affects schemes, app packaging, entitlements, or `toyvm.xcodeproj`.
- When Xcode MCP tools are available, prefer them for Xcode builds and project edits.
- If you use `xcodebuild` directly, always use `-scheme`, not `-target`:

  ```bash
  xcodebuild -project toyvm.xcodeproj -scheme toyvm -configuration Release
  xcodebuild -project toyvm.xcodeproj -scheme ToyVMApp -configuration Release
  ```

- There are currently no test or lint targets.
- After making changes and verifying the build(s), commit the changes with a clear, descriptive message. For larger changes, split the work into multiple small commits and verify the build after each commit.
- When committing, follow the repository's commit conventions and include required trailers (for example, the Co-authored-by trailer when using the Copilot assistant).

## Xcode project maintenance

- When adding or removing Swift source files, update `toyvm.xcodeproj/project.pbxproj` as well as the filesystem.
- Files in `ToyVMCore/` must be added to both Xcode targets (`toyvm` and `ToyVMApp`).
- Files in `ToyVMApp/` must be added to the `ToyVMApp` target and group.
- Prefer Xcode MCP tools over manual `project.pbxproj` edits when possible.

## Code conventions worth preserving

- `VirtualMachineBuilder` intentionally does not attach serial ports. Callers must attach the console after building the configuration.
- `VMConfig` uses a custom decoder for backwards compatibility. When adding persisted fields, decode them with `decodeIfPresent` and provide a sensible default.
- During macOS guest installation, pass the `VZMacAuxiliaryStorage` created via `creatingStorageAt:` directly into the platform configuration. Use `contentsOf:` only on later boots.
- User-initiated VM bundle deletion should go through `NSWorkspace.shared.recycle()`. Reserve `FileManager.removeItem` for cleanup paths and failed partial creation.
- The CLI and shared code rely on `[tag:]path` share syntax where only the first `:` separates the optional tag from the path.
- CLI files use `#if canImport(ToyVMCore)` so they build in both SPM and Xcode layouts.
