//
//  Config.swift
//  toyvm
//

import ArgumentParser
import Darwin
import Foundation
import Virtualization

extension ToyVM {
    struct ConfigCommand: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "config",
            abstract: "Display or modify the configuration of a VM bundle"
        )

        @Argument(help: "Path to the VM bundle to configure")
        var bundle: String

        // MARK: - Kernel / initrd

        @Option(name: [.customShort("k"), .long], help: "Replace the kernel image with the file at the given path")
        var kernel: String? = nil

        @Option(name: [.customShort("i"), .long], help: "Replace the initrd image with the file at the given path")
        var initrd: String? = nil

        @Flag(name: .customLong("remove-initrd"), help: "Remove the initrd image from the bundle")
        var removeInitrd: Bool = false

        // MARK: - Kernel command line

        @Option(name: [.customShort("c"), .customLong("cmdline")], help: "Set the kernel command line")
        var cmdline: String? = nil

        // MARK: - Disks

        @Option(name: [.customShort("d"), .long], help: "Add a read/write disk image of the given size (e.g. 20G, 512M, asif:20G)")
        var disk: [String] = []

        @Option(name: [.customShort("r"), .customLong("disk-ro")], help: "As --disk but adds a read-only disk image")
        var diskRO: [String] = []

        @Option(name: .customLong("remove-disk"), help: "Remove a disk image from the bundle by its filename (e.g. disk0.img)")
        var removeDisk: [String] = []

        // MARK: - Directory shares

        @Option(name: [.customShort("s"), .long], help: "Add or replace a directory share; accepts [tag:]path (tag defaults to \"share\")")
        var share: [String] = []

        @Option(name: [.customShort("t"), .customLong("share-ro")], help: "As --share but adds a read-only directory share")
        var shareRO: [String] = []

        @Option(name: .customLong("remove-share"), help: "Remove a directory share by tag")
        var removeShare: [String] = []

        // MARK: - Resources

        @Option(name: [.customShort("p"), .long], help: "Set the number of CPUs")
        var cpus: Int? = nil

        @Option(name: [.customShort("m"), .long], help: "Set the amount of memory in gigabytes")
        var memory: Int? = nil

        // MARK: - Enable/disable flags

        @Flag(name: .customLong("audio"), help: "Enable the virtual audio device")
        var enableAudio: Bool = false

        @Flag(name: .customLong("no-audio"), help: "Disable the virtual audio device")
        var disableAudio: Bool = false

        @Flag(name: .customLong("net"), help: "Enable the virtual network interface")
        var enableNet: Bool = false

        @Flag(name: .customLong("no-net"), help: "Disable the virtual network interface")
        var disableNet: Bool = false

        @Flag(name: .customLong("enable-rosetta"), help: "Enable the Rosetta directory share")
        var enableRosetta: Bool = false

        @Flag(name: .customLong("disable-rosetta"), help: "Disable the Rosetta directory share")
        var disableRosetta: Bool = false

        @Flag(name: .customLong("read-only"), help: "Mark the active branch as read-only")
        var setReadOnly: Bool = false

        @Flag(name: .customLong("no-read-only"), help: "Clear the read-only flag on the active branch")
        var clearReadOnly: Bool = false

        mutating func validate() throws {
            if enableAudio && disableAudio {
                throw ValidationError("--audio and --no-audio are mutually exclusive")
            }
            if enableNet && disableNet {
                throw ValidationError("--net and --no-net are mutually exclusive")
            }
            if enableRosetta && disableRosetta {
                throw ValidationError("--enable-rosetta and --disable-rosetta are mutually exclusive")
            }
            if removeInitrd && initrd != nil {
                throw ValidationError("--initrd and --remove-initrd are mutually exclusive")
            }
            if setReadOnly && clearReadOnly {
                throw ValidationError("--read-only and --no-read-only are mutually exclusive")
            }
        }

        mutating func run() throws {
            let bundleURL = try resolveBundlePath(bundle)
            var meta = try BundleMeta.load(from: bundleURL)
            let branchURL = VMConfig.branchURL(in: bundleURL, branch: meta.activeBranch)
            let fm = FileManager.default
            var config = try VMConfig.load(from: branchURL)

            // Check if branch is read-only before allowing any modifications (other than toggling read-only itself)
            let branchIsReadOnly = meta.branches[meta.activeBranch]?.readOnly ?? false
            let hasConfigChanges = kernel != nil || initrd != nil || removeInitrd
                || !removeDisk.isEmpty || !disk.isEmpty || !diskRO.isEmpty
                || !removeShare.isEmpty || !share.isEmpty || !shareRO.isEmpty
                || cpus != nil || memory != nil
                || enableAudio || disableAudio || enableNet || disableNet
                || enableRosetta || disableRosetta || cmdline != nil
            if branchIsReadOnly && hasConfigChanges {
                throw ToyVMError("Branch '\(meta.activeBranch)' is read-only; configuration changes are not permitted.")
            }

            // Request confirmation for disk removal before making any changes
            if !removeDisk.isEmpty {
                for diskName in removeDisk {
                    guard config.disks.contains(where: { $0.file == diskName }) else {
                        throw ToyVMError("No disk named '\(diskName)' in this bundle")
                    }
                }

                // Prompt user for confirmation
                var msg = "This will permanently delete the following disk image(s):\n"
                for diskName in removeDisk { msg += "  - \(diskName)\n" }
                msg += "Continue? (yes/no) "

                guard confirm(msg) else {
                    throw ToyVMError("Disk removal cancelled.")
                }
            }

            // Kernel replacement
            if let newKernelPath = kernel {
                let src = URL(fileURLWithPath: newKernelPath)
                let newFilename = src.lastPathComponent
                let kernelDir = branchURL.appendingPathComponent(VMConfig.kernelDir)
                let oldFilename = config.kernel
                let oldPath = kernelDir.appendingPathComponent(oldFilename)
                let newPath = kernelDir.appendingPathComponent(newFilename)
                if newFilename != oldFilename {
                    try fm.copyItem(at: src, to: newPath)
                    try fm.removeItem(at: oldPath)
                } else {
                    _ = try fm.replaceItemAt(newPath, withItemAt: src)
                }
                config.kernel = newFilename
            }

            // Initrd replacement / removal
            if let newInitrdPath = initrd {
                let src = URL(fileURLWithPath: newInitrdPath)
                let newFilename = src.lastPathComponent
                let initrdDir = branchURL.appendingPathComponent(VMConfig.initrdDir)
                if let oldFilename = config.initrd, oldFilename != newFilename {
                    try fm.copyItem(at: src, to: initrdDir.appendingPathComponent(newFilename))
                    try fm.removeItem(at: initrdDir.appendingPathComponent(oldFilename))
                } else if config.initrd == nil {
                    try fm.copyItem(at: src, to: initrdDir.appendingPathComponent(newFilename))
                } else {
                    let dest = initrdDir.appendingPathComponent(newFilename)
                    _ = try fm.replaceItemAt(dest, withItemAt: src)
                }
                config.initrd = newFilename
            } else if removeInitrd {
                if let oldFilename = config.initrd {
                    let initrdDir = branchURL.appendingPathComponent(VMConfig.initrdDir)
                    try fm.removeItem(at: initrdDir.appendingPathComponent(oldFilename))
                    config.initrd = nil
                }
            }

            // Kernel command line
            if let line = cmdline {
                config.kernelCommandLine = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
                    .nonEmpty ?? ["console=hvc0"]
            }

            // Remove disks
            let disksDir = branchURL.appendingPathComponent(VMConfig.disksDir)
            for name in removeDisk {
                guard let idx = config.disks.firstIndex(where: { $0.file == name }) else {
                    throw ToyVMError("No disk named '\(name)' in this bundle")
                }
                try fm.removeItem(at: disksDir.appendingPathComponent(name))
                config.disks.remove(at: idx)
            }

            // Add disks
            for spec in disk {
                let (format, size) = try parseDiskSpec(spec)
                let name = nextDiskFilename(existing: config.disks, format: format)
                try createDisk(at: disksDir.appendingPathComponent(name), size: size, format: format)
                config.disks.append(DiskConfig(file: name, readOnly: false, format: format))
            }
            for spec in diskRO {
                let (format, size) = try parseDiskSpec(spec)
                let name = nextDiskFilename(existing: config.disks, format: format)
                try createDisk(at: disksDir.appendingPathComponent(name), size: size, format: format)
                config.disks.append(DiskConfig(file: name, readOnly: true, format: format))
            }

            // Remove shares
            for tag in removeShare {
                guard config.shares.contains(where: { $0.tag == tag }) else {
                    throw ToyVMError("No share with tag '\(tag)' in this bundle")
                }
                config.shares.removeAll { $0.tag == tag }
            }

            // Add/replace shares
            for arg in share {
                let (tag, path) = parseShareArg(arg)
                try VZVirtioFileSystemDeviceConfiguration.validateTag(tag)
                config.shares.removeAll { $0.tag == tag }
                config.shares.append(ShareConfig(tag: tag, path: path, readOnly: false))
            }
            for arg in shareRO {
                let (tag, path) = parseShareArg(arg)
                try VZVirtioFileSystemDeviceConfiguration.validateTag(tag)
                config.shares.removeAll { $0.tag == tag }
                config.shares.append(ShareConfig(tag: tag, path: path, readOnly: true))
            }

            // Resources
            if let c = cpus  { config.cpus     = c }
            if let m = memory { config.memoryGB = m }

            // Boolean toggles
            if enableAudio   { config.audio   = true  }
            if disableAudio  { config.audio   = false }
            if enableNet     { config.network = true  }
            if disableNet    { config.network = false }
            if enableRosetta { config.rosetta = true  }
            if disableRosetta{ config.rosetta = false }

            try config.save(to: branchURL)

            // Toggle read-only status on the branch metadata
            var metaChanged = false
            if setReadOnly && !(meta.branches[meta.activeBranch]?.readOnly ?? false) {
                meta.branches[meta.activeBranch]?.readOnly = true
                metaChanged = true
            } else if clearReadOnly && (meta.branches[meta.activeBranch]?.readOnly ?? false) {
                meta.branches[meta.activeBranch]?.readOnly = false
                metaChanged = true
            }
            if metaChanged {
                try meta.save(to: bundleURL)
            }

            // Display the configuration (after any changes)
            let isReadOnly = meta.branches[meta.activeBranch]?.readOnly ?? false
            print("Branch:      \(meta.activeBranch)\(isReadOnly ? " [read-only]" : "")")
            displayConfig(config, branchURL: branchURL)
        }

        private func displayConfig(_ config: VMConfig, branchURL: URL) {
            print("Kernel:      \(config.kernel)")
            if let initrd = config.initrd {
                print("Initrd:      \(initrd)")
            }
            print("CPUs:        \(config.cpus)")
            print("Memory:      \(config.memoryGB) GB")
            print("Network:     \(config.network ? "yes" : "no")")
            print("Audio:       \(config.audio ? "yes" : "no")")
            print("Rosetta:     \(config.rosetta ? "yes" : "no")")
            print("Kernel args: \(config.kernelCommandLine.joined(separator: " "))")

            if config.disks.isEmpty {
                print("Disks:       (none)")
            } else {
                print("Disks:")
                for disk in config.disks {
                    let rwLabel = disk.readOnly ? "ro" : "rw"
                    let fmtLabel = disk.format.rawValue
                    let url = config.diskURL(in: branchURL, disk: disk)
                    let sizeDesc = diskSizeDescription(url: url, format: disk.format)
                    print("  [\(rwLabel), \(fmtLabel)] \(disk.file)\(sizeDesc.map { " (\($0))" } ?? "")")
                }
            }

            if config.shares.isEmpty {
                print("Shares:      (none)")
            } else {
                print("Shares:")
                for share in config.shares {
                    let rwLabel = share.readOnly ? "ro" : "rw"
                    print("  [\(rwLabel)] \(share.tag): \(share.path)")
                }
            }
        }

        private func diskSizeDescription(url: URL, format: DiskFormat) -> String? {
            guard let (logical, onDisk) = diskSizes(url: url, format: format) else { return nil }
            let logicalStr = formatSize(logical)
            let onDiskStr = formatSize(onDisk)
            if logicalStr == onDiskStr {
                return logicalStr
            }
            return "\(logicalStr), \(onDiskStr) on disk"
        }

        private func diskSizes(url: URL, format: DiskFormat) -> (logical: UInt64, onDisk: UInt64)? {
            switch format {
            case .raw:
                return rawDiskSizes(url: url)
            case .asif:
                return asifDiskSizes(url: url)
            }
        }

        private func rawDiskSizes(url: URL) -> (logical: UInt64, onDisk: UInt64)? {
            var s = stat()
            guard stat(url.path, &s) == 0 else { return nil }
            let logical = UInt64(s.st_size)
            let onDisk = UInt64(s.st_blocks) * 512
            return (logical, onDisk)
        }

        private func asifDiskSizes(url: URL) -> (logical: UInt64, onDisk: UInt64)? {
            guard let logical = asifLogicalSize(url: url) else { return nil }
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let onDisk = attrs[.size] as? UInt64 else { return nil }
            return (logical, onDisk)
        }

        private func asifLogicalSize(url: URL) -> UInt64? {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
            process.arguments = ["image", "info", "--plist", url.path]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            guard (try? process.run()) != nil else { return nil }
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                  let sizeInfo = plist["Size Info"] as? [String: Any],
                  let totalBytes = sizeInfo["Total Bytes"] as? UInt64 else { return nil }
            return totalBytes
        }

        private func formatSize(_ bytes: UInt64) -> String {
            let units: [(String, UInt64)] = [("T", 1024*1024*1024*1024), ("G", 1024*1024*1024), ("M", 1024*1024), ("K", 1024)]
            for (suffix, factor) in units {
                if bytes >= factor {
                    let value = Double(bytes) / Double(factor)
                    if value.truncatingRemainder(dividingBy: 1) == 0 {
                        return "\(Int(value))\(suffix)"
                    } else {
                        return String(format: "%.1f%@", value, suffix)
                    }
                }
            }
            return "\(bytes)B"
        }
    }
}

private extension Array {
    /// Returns the array if non-empty, otherwise nil.
    var nonEmpty: Self? { isEmpty ? nil : self }
}
