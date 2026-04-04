//
//  VMBundle.swift
//  ToyVMCore
//

import Foundation

// MARK: - CreateOptions

/// Options for creating a new VM bundle.
public struct CreateOptions {
    public var cpus: Int = 2
    public var memoryGB: Int = 2
    public var audio: Bool = false
    public var network: Bool = true
    public var rosetta: Bool = false
    public var bootMode: BootMode = .linux
    public var kernelCommandLine: [String] = ["console=hvc0"]
    public var disks: [(format: DiskFormat, size: UInt64, readOnly: Bool)] = []
    public var shares: [ShareConfig] = []
    public var usbDisks: [USBDiskConfig] = []
    public var rootBranchName: String = "main"

    public init() {}
}

// MARK: - VMBundle

/// A loaded VM bundle, providing access to its configuration and branch metadata,
/// and operations for modifying both.
public struct VMBundle {
    public let bundleURL: URL
    public private(set) var meta: BundleMeta
    /// The configuration for the currently active branch. Mutate this directly and
    /// call `saveConfig()` to persist.
    public var config: VMConfig

    /// The URL of the currently active branch directory.
    public var activeBranchURL: URL {
        VMConfig.branchURL(in: bundleURL, branch: meta.activeBranch)
    }

    /// Metadata for the currently active branch.
    public var activeBranchInfo: BranchInfo? {
        meta.branches[meta.activeBranch]
    }

    // MARK: - Init (internal)

    private init(bundleURL: URL, meta: BundleMeta, config: VMConfig) {
        self.bundleURL = bundleURL
        self.meta = meta
        self.config = config
    }

    // MARK: - Loading

    /// Loads a VM bundle from the given URL, reading both bundle metadata and the
    /// active branch's VM configuration.
    public static func load(from bundleURL: URL) throws -> VMBundle {
        let meta = try BundleMeta.load(from: bundleURL)
        let branchURL = VMConfig.branchURL(in: bundleURL, branch: meta.activeBranch)
        let config = try VMConfig.load(from: branchURL)
        return VMBundle(bundleURL: bundleURL, meta: meta, config: config)
    }

    // MARK: - Creating

    /// Creates a new VM bundle at the given URL with the specified options.
    /// For Linux boot mode, kernelPath is required. For EFI boot mode, it is optional.
    /// Returns the newly created bundle.
    ///
    /// - Throws if the bundle directory already exists or any file operation fails.
    ///   On failure, any partially-created bundle directory is removed.
    @discardableResult
    public static func create(
        at bundleURL: URL,
        kernelPath: URL? = nil,
        initrdPath: URL? = nil,
        options: CreateOptions = CreateOptions()
    ) throws -> VMBundle {
        let fm = FileManager.default
        var bundleCreated = false

        do {
            try fm.createDirectory(at: bundleURL, withIntermediateDirectories: false)
            bundleCreated = true

            let rootBranch = options.rootBranchName
            let branchesDir = bundleURL.appendingPathComponent(VMConfig.branchesDir)
            let branchURL = VMConfig.branchURL(in: bundleURL, branch: rootBranch)
            let kernelDir = branchURL.appendingPathComponent(VMConfig.kernelDir)
            let initrdDir = branchURL.appendingPathComponent(VMConfig.initrdDir)
            let disksDir = branchURL.appendingPathComponent(VMConfig.disksDir)

            for dir in [branchesDir, branchURL, kernelDir, initrdDir, disksDir] {
                try fm.createDirectory(at: dir, withIntermediateDirectories: false)
            }

            // Copy kernel (required for .linux, optional for .efi)
            var kernelFilename: String? = nil
            if let src = kernelPath {
                kernelFilename = src.lastPathComponent
                try fm.copyItem(at: src, to: kernelDir.appendingPathComponent(kernelFilename!))
            }

            // Copy initrd
            var initrdFilename: String? = nil
            if let src = initrdPath {
                initrdFilename = src.lastPathComponent
                try fm.copyItem(at: src, to: initrdDir.appendingPathComponent(initrdFilename!))
            }

            // Create disk images
            var diskConfigs: [DiskConfig] = []
            for (idx, spec) in options.disks.enumerated() {
                let name = "disk\(idx).\(spec.format.fileExtension)"
                try createDisk(at: disksDir.appendingPathComponent(name), size: spec.size, format: spec.format)
                diskConfigs.append(DiskConfig(file: name, readOnly: spec.readOnly, format: spec.format))
            }

            let config = VMConfig(
                cpus: options.cpus,
                memoryGB: options.memoryGB,
                audio: options.audio,
                network: options.network,
                rosetta: options.rosetta,
                bootMode: options.bootMode,
                kernel: kernelFilename,
                initrd: initrdFilename,
                kernelCommandLine: options.kernelCommandLine,
                disks: diskConfigs,
                shares: options.shares,
                usbDisks: options.usbDisks
            )
            try config.save(to: branchURL)

            let meta = BundleMeta(rootBranch: rootBranch)
            try meta.save(to: bundleURL)

            return VMBundle(bundleURL: bundleURL, meta: meta, config: config)
        } catch {
            if bundleCreated {
                try? fm.removeItem(at: bundleURL)
            }
            throw error
        }
    }

    // MARK: - Persistence

    /// Saves the in-memory VM configuration to the active branch's config.plist.
    public func saveConfig() throws {
        try config.save(to: activeBranchURL)
    }

    /// Saves the in-memory bundle metadata to bundle.plist.
    public func saveMeta() throws {
        try meta.save(to: bundleURL)
    }

    // MARK: - Branch operations

    /// Returns the names of branches that would be deleted by `deleteBranch(named:)` —
    /// i.e. `[name] + all descendants` — after validating that deletion is permitted.
    /// Throws if the branch does not exist, is the root, is read-only, or the active
    /// branch cannot cleanly migrate to the parent.
    public func validateDeleteBranch(named branchName: String) throws -> [String] {
        guard meta.branches[branchName] != nil else {
            throw ToyVMError("Branch '\(branchName)' does not exist")
        }
        guard meta.branches[branchName]!.parent != nil else {
            throw ToyVMError("The root branch cannot be deleted")
        }
        if meta.branches[branchName]!.readOnly {
            throw ToyVMError("Branch '\(branchName)' is read-only and cannot be deleted.")
        }

        let toDelete = [branchName] + meta.descendants(of: branchName)

        if toDelete.contains(meta.activeBranch) {
            let parentName = meta.branches[branchName]!.parent!
            let remainingSiblings = meta.children(of: parentName).filter { $0 != branchName }
            if !remainingSiblings.isEmpty {
                throw ToyVMError(
                    "Cannot delete branch '\(branchName)': it contains the active branch " +
                    "'\(meta.activeBranch)', and its parent '\(parentName)' still has other " +
                    "child branches. Select a different active branch first."
                )
            }
        }

        return toDelete
    }

    /// Deletes the named branch and all its descendants. Validates constraints first
    /// (use `validateDeleteBranch` to get the list for a confirmation prompt).
    public mutating func deleteBranch(named branchName: String) throws {
        let toDelete = try validateDeleteBranch(named: branchName)
        let parentName = meta.branches[branchName]!.parent!

        for branch in toDelete {
            let url = VMConfig.branchURL(in: bundleURL, branch: branch)
            try? FileManager.default.removeItem(at: url)
            meta.branches.removeValue(forKey: branch)
        }
        if toDelete.contains(meta.activeBranch) {
            meta.activeBranch = parentName
        }
        try saveMeta()
    }

    /// Creates a new branch by cloning the specified source branch (or the active branch
    /// if `from` is nil), then makes the new branch the active branch.
    public mutating func createBranch(named name: String, from parentName: String? = nil) throws {
        guard meta.branches[name] == nil else {
            throw ToyVMError("Branch '\(name)' already exists")
        }
        let parent = parentName ?? meta.activeBranch
        guard meta.branches[parent] != nil else {
            throw ToyVMError("Parent branch '\(parent)' does not exist")
        }

        let srcURL = VMConfig.branchURL(in: bundleURL, branch: parent)
        let dstURL = VMConfig.branchURL(in: bundleURL, branch: name)
        try cloneBranchDirectory(from: srcURL, to: dstURL)

        meta.branches[name] = BranchInfo(parent: parent)
        meta.activeBranch = name
        try saveMeta()
    }

    /// Reverts the named branch (or the active branch if `name` is nil) to the current
    /// state of its parent.
    public mutating func revertBranch(named branchName: String? = nil) throws {
        let branchName = branchName ?? meta.activeBranch

        guard meta.branches[branchName] != nil else {
            throw ToyVMError("Branch '\(branchName)' does not exist")
        }
        guard let parentName = meta.branches[branchName]!.parent else {
            throw ToyVMError("The root branch cannot be reverted (it has no parent)")
        }
        if meta.branches[branchName]!.readOnly {
            throw ToyVMError("Branch '\(branchName)' is read-only and cannot be reverted.")
        }

        let branchURL = VMConfig.branchURL(in: bundleURL, branch: branchName)
        let parentURL = VMConfig.branchURL(in: bundleURL, branch: parentName)
        let tempURL = VMConfig.branchURL(in: bundleURL, branch: branchName + ".\(UUID().uuidString).tmp")

        try cloneBranchDirectory(from: parentURL, to: tempURL)
        do {
            try FileManager.default.removeItem(at: branchURL)
            try FileManager.default.moveItem(at: tempURL, to: branchURL)
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            throw error
        }

        // Reload config for the active branch (it may have changed)
        if branchName == meta.activeBranch {
            config = try VMConfig.load(from: activeBranchURL)
        }
    }

    /// Commits the named branch (or the active branch if `name` is nil) to its parent:
    /// replaces the parent's contents with the branch's, deletes the branch, and makes
    /// the parent the new active branch.
    public mutating func commitBranch(named branchName: String? = nil) throws {
        let branchName = branchName ?? meta.activeBranch

        guard meta.branches[branchName] != nil else {
            throw ToyVMError("Branch '\(branchName)' does not exist")
        }
        guard let parentName = meta.branches[branchName]!.parent else {
            throw ToyVMError("The root branch cannot be committed (it has no parent)")
        }
        if meta.branches[branchName]!.readOnly {
            throw ToyVMError("Branch '\(branchName)' is read-only and cannot be committed.")
        }
        if meta.branches[parentName]?.readOnly == true {
            throw ToyVMError("Cannot commit to '\(parentName)': it is read-only.")
        }
        guard meta.children(of: branchName).isEmpty else {
            throw ToyVMError(
                "Branch '\(branchName)' has child branches and cannot be committed. " +
                "Delete its children first."
            )
        }
        let parentSiblings = meta.children(of: parentName).filter { $0 != branchName }
        guard parentSiblings.isEmpty else {
            throw ToyVMError(
                "Cannot commit '\(branchName)': its parent '\(parentName)' has other child " +
                "branches (\(parentSiblings.joined(separator: ", "))). " +
                "Delete them first."
            )
        }

        let branchURL = VMConfig.branchURL(in: bundleURL, branch: branchName)
        let parentURL = VMConfig.branchURL(in: bundleURL, branch: parentName)
        let tempURL = VMConfig.branchURL(in: bundleURL, branch: parentName + ".\(UUID().uuidString).tmp")

        try cloneBranchDirectory(from: branchURL, to: tempURL)
        do {
            try FileManager.default.removeItem(at: parentURL)
            try FileManager.default.moveItem(at: tempURL, to: parentURL)
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            throw error
        }
        try FileManager.default.removeItem(at: branchURL)

        meta.branches.removeValue(forKey: branchName)
        meta.activeBranch = parentName
        try saveMeta()

        // Reload config for the new active branch
        config = try VMConfig.load(from: activeBranchURL)
    }

    /// Makes the named branch the active branch. Only leaf branches (those with no
    /// children) may be selected.
    public mutating func selectBranch(named name: String) throws {
        guard meta.branches[name] != nil else {
            throw ToyVMError("Branch '\(name)' does not exist")
        }
        guard meta.children(of: name).isEmpty else {
            throw ToyVMError(
                "Branch '\(name)' has child branches; only leaf branches can be selected. " +
                "Select one of its descendants instead."
            )
        }
        meta.activeBranch = name
        try saveMeta()
        config = try VMConfig.load(from: activeBranchURL)
    }

    /// Renames a branch, updating all references in the metadata.
    public mutating func renameBranch(from oldName: String, to newName: String) throws {
        guard meta.branches[oldName] != nil else {
            throw ToyVMError("Branch '\(oldName)' does not exist")
        }
        guard meta.branches[newName] == nil else {
            throw ToyVMError("Branch '\(newName)' already exists")
        }

        let oldURL = VMConfig.branchURL(in: bundleURL, branch: oldName)
        let newURL = VMConfig.branchURL(in: bundleURL, branch: newName)
        try FileManager.default.moveItem(at: oldURL, to: newURL)

        let branchInfo = meta.branches[oldName]!
        meta.branches.removeValue(forKey: oldName)
        meta.branches[newName] = branchInfo

        for (childName, childInfo) in meta.branches where childInfo.parent == oldName {
            meta.branches[childName] = BranchInfo(parent: newName, readOnly: childInfo.readOnly)
        }

        if meta.activeBranch == oldName {
            meta.activeBranch = newName
        }
        try saveMeta()
    }

    /// Sets or clears the read-only flag on the active branch.
    public mutating func setBranchReadOnly(_ readOnly: Bool) throws {
        guard meta.branches[meta.activeBranch] != nil else {
            throw ToyVMError("Active branch '\(meta.activeBranch)' not found in metadata")
        }
        meta.branches[meta.activeBranch]!.readOnly = readOnly
        try saveMeta()
    }

    // MARK: - Config file operations

    /// Replaces the kernel image file with the one at the given URL.
    /// The config is updated in memory; call `saveConfig()` to persist.
    public mutating func replaceKernel(from url: URL) throws {
        let newFilename = url.lastPathComponent
        let kernelDir = activeBranchURL.appendingPathComponent(VMConfig.kernelDir)
        let fm = FileManager.default
        let newPath = kernelDir.appendingPathComponent(newFilename)
        if let oldFilename = config.kernel {
            let oldPath = kernelDir.appendingPathComponent(oldFilename)
            if newFilename != oldFilename {
                try fm.copyItem(at: url, to: newPath)
                try fm.removeItem(at: oldPath)
            } else {
                _ = try fm.replaceItemAt(newPath, withItemAt: url)
            }
        } else {
            try fm.copyItem(at: url, to: newPath)
        }
        config.kernel = newFilename
    }

    /// Replaces or sets the initrd image file with the one at the given URL.
    /// The config is updated in memory; call `saveConfig()` to persist.
    public mutating func replaceInitrd(from url: URL) throws {
        let newFilename = url.lastPathComponent
        let initrdDir = activeBranchURL.appendingPathComponent(VMConfig.initrdDir)
        let fm = FileManager.default
        if let oldFilename = config.initrd, oldFilename != newFilename {
            try fm.copyItem(at: url, to: initrdDir.appendingPathComponent(newFilename))
            try fm.removeItem(at: initrdDir.appendingPathComponent(oldFilename))
        } else if config.initrd == nil {
            try fm.copyItem(at: url, to: initrdDir.appendingPathComponent(newFilename))
        } else {
            let dest = initrdDir.appendingPathComponent(newFilename)
            _ = try fm.replaceItemAt(dest, withItemAt: url)
        }
        config.initrd = newFilename
    }

    /// Removes the initrd image file. The config is updated in memory; call `saveConfig()` to persist.
    public mutating func removeInitrd() throws {
        if let oldFilename = config.initrd {
            let initrdDir = activeBranchURL.appendingPathComponent(VMConfig.initrdDir)
            try FileManager.default.removeItem(at: initrdDir.appendingPathComponent(oldFilename))
            config.initrd = nil
        }
    }

    /// Sets the kernel command line arguments. Call `saveConfig()` to persist.
    public mutating func setKernelCommandLine(_ args: [String]) {
        config.kernelCommandLine = args.isEmpty ? ["console=hvc0"] : args
    }

    /// Creates a new disk image in the bundle and appends it to the config.
    /// The config is updated in memory; call `saveConfig()` to persist.
    public mutating func addDisk(format: DiskFormat, size: UInt64, readOnly: Bool) throws {
        let disksDir = activeBranchURL.appendingPathComponent(VMConfig.disksDir)
        let name = nextDiskFilename(existing: config.disks, format: format)
        try createDisk(at: disksDir.appendingPathComponent(name), size: size, format: format)
        config.disks.append(DiskConfig(file: name, readOnly: readOnly, format: format))
    }

    /// Removes the named disk image file and removes it from the config.
    /// Throws if no disk with that filename exists.
    /// The config is updated in memory; call `saveConfig()` to persist.
    public mutating func removeDisk(named name: String) throws {
        guard let idx = config.disks.firstIndex(where: { $0.file == name }) else {
            throw ToyVMError("No disk named '\(name)' in this bundle")
        }
        let disksDir = activeBranchURL.appendingPathComponent(VMConfig.disksDir)
        try FileManager.default.removeItem(at: disksDir.appendingPathComponent(name))
        config.disks.remove(at: idx)
    }

    /// Adds or replaces a directory share in the config. If a share with the same tag
    /// already exists, it is replaced. Call `saveConfig()` to persist.
    public mutating func addShare(_ share: ShareConfig) {
        config.shares.removeAll { $0.tag == share.tag }
        config.shares.append(share)
    }

    /// Removes the share with the given tag. Throws if no share with that tag exists.
    /// Call `saveConfig()` to persist.
    public mutating func removeShare(tag: String) throws {
        guard config.shares.contains(where: { $0.tag == tag }) else {
            throw ToyVMError("No share with tag '\(tag)' in this bundle")
        }
        config.shares.removeAll { $0.tag == tag }
    }

    // MARK: - Config property setters (call saveConfig() to persist)

    public mutating func setCPUs(_ count: Int) { config.cpus = count }
    public mutating func setMemoryGB(_ gb: Int) { config.memoryGB = gb }
    public mutating func setAudio(_ enabled: Bool) { config.audio = enabled }
    public mutating func setNetwork(_ enabled: Bool) { config.network = enabled }
    public mutating func setRosetta(_ enabled: Bool) { config.rosetta = enabled }
    public mutating func setBootMode(_ mode: BootMode) { config.bootMode = mode }

    /// Adds a USB disk to the configuration. Call `saveConfig()` to persist.
    public mutating func addUSBDisk(_ usbDisk: USBDiskConfig) {
        config.usbDisks.append(usbDisk)
    }

    /// Removes the USB disk at the given index. Call `saveConfig()` to persist.
    public mutating func removeUSBDisk(at index: Int) throws {
        guard config.usbDisks.indices.contains(index) else {
            throw ToyVMError("USB disk index \(index) out of range")
        }
        config.usbDisks.remove(at: index)
    }

    /// Returns the URL of the EFI variable store in the active branch.
    public var efiVariableStoreURL: URL {
        config.efiVariableStoreURL(in: activeBranchURL)
    }
}
