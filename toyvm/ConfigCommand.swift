//
//  Config.swift
//  toyvm
//

import ArgumentParser
import Foundation
#if canImport(ToyVMCore)
import ToyVMCore
#endif
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

        @Flag(name: .customLong("efi"), help: "Switch to EFI boot mode")
        var setEFI: Bool = false

        @Flag(name: .customLong("no-efi"), help: "Switch to Linux (direct kernel) boot mode")
        var clearEFI: Bool = false

        @Option(name: .customLong("usb"), help: "Add a USB disk image (read-write)")
        var addUSB: [String] = []

        @Option(name: .customLong("usb-ro"), help: "Add a USB disk image (read-only)")
        var addUSBRO: [String] = []

        @Option(name: .customLong("remove-usb"), help: "Remove a USB disk by index (0-based)")
        var removeUSB: [Int] = []

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
            if setEFI && clearEFI {
                throw ValidationError("--efi and --no-efi are mutually exclusive")
            }
        }

        mutating func run() throws {
            let bundleURL = try resolveBundlePath(bundle)
            var bundle = try VMBundle.load(from: bundleURL)

            // Check if branch is read-only before allowing any modifications (other than toggling read-only itself)
            let branchIsReadOnly = bundle.activeBranchInfo?.readOnly ?? false
            let hasConfigChanges = kernel != nil || initrd != nil || removeInitrd
                || !removeDisk.isEmpty || !disk.isEmpty || !diskRO.isEmpty
                || !removeShare.isEmpty || !share.isEmpty || !shareRO.isEmpty
                || cpus != nil || memory != nil
                || enableAudio || disableAudio || enableNet || disableNet
                || enableRosetta || disableRosetta || cmdline != nil
                || setEFI || clearEFI
                || !addUSB.isEmpty || !addUSBRO.isEmpty || !removeUSB.isEmpty
            if branchIsReadOnly && hasConfigChanges {
                throw ToyVMError("Branch '\(bundle.meta.activeBranch)' is read-only; configuration changes are not permitted.")
            }

            // Request confirmation for disk removal before making any changes
            if !removeDisk.isEmpty {
                for diskName in removeDisk {
                    guard bundle.config.disks.contains(where: { $0.file == diskName }) else {
                        throw ToyVMError("No disk named '\(diskName)' in this bundle")
                    }
                }
                var msg = "This will permanently delete the following disk image(s):\n"
                for diskName in removeDisk { msg += "  - \(diskName)\n" }
                msg += "Continue? (yes/no) "
                guard confirm(msg) else {
                    throw ToyVMError("Disk removal cancelled.")
                }
            }

            // Kernel replacement
            if let newKernelPath = kernel {
                try bundle.replaceKernel(from: URL(fileURLWithPath: newKernelPath))
            }

            // Initrd replacement / removal
            if let newInitrdPath = initrd {
                try bundle.replaceInitrd(from: URL(fileURLWithPath: newInitrdPath))
            } else if removeInitrd {
                try bundle.removeInitrd()
            }

            // Kernel command line
            if let line = cmdline {
                let args = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
                bundle.setKernelCommandLine(args)
            }

            // Remove disks
            for name in removeDisk {
                try bundle.removeDisk(named: name)
            }

            // Add disks
            for spec in disk {
                let (format, size) = try parseDiskSpec(spec)
                try bundle.addDisk(format: format, size: size, readOnly: false)
            }
            for spec in diskRO {
                let (format, size) = try parseDiskSpec(spec)
                try bundle.addDisk(format: format, size: size, readOnly: true)
            }

            // Remove shares
            for tag in removeShare {
                try bundle.removeShare(tag: tag)
            }

            // Add/replace shares (tag validation requires Virtualization.framework)
            for (arg, readOnly) in share.map({ ($0, false) }) + shareRO.map({ ($0, true) }) {
                let (tag, path) = parseShareArg(arg)
                try VZVirtioFileSystemDeviceConfiguration.validateTag(tag)
                bundle.addShare(ShareConfig(tag: tag, path: path, readOnly: readOnly))
            }

            // Resources
            if let c = cpus   { bundle.setCPUs(c) }
            if let m = memory { bundle.setMemoryGB(m) }

            // Boolean toggles
            if enableAudio    { bundle.setAudio(true) }
            if disableAudio   { bundle.setAudio(false) }
            if enableNet      { bundle.setNetwork(true) }
            if disableNet     { bundle.setNetwork(false) }
            if enableRosetta  { bundle.setRosetta(true) }
            if disableRosetta { bundle.setRosetta(false) }

            // Boot mode
            if setEFI   { bundle.setBootMode(.efi) }
            if clearEFI { bundle.setBootMode(.linux) }

            // Remove USB disks (process indices in descending order to avoid shifting)
            for idx in removeUSB.sorted().reversed() {
                try bundle.removeUSBDisk(at: idx)
            }

            // Add USB disks
            for path in addUSB {
                bundle.addUSBDisk(USBDiskConfig(path: path, readOnly: false))
            }
            for path in addUSBRO {
                bundle.addUSBDisk(USBDiskConfig(path: path, readOnly: true))
            }

            try bundle.saveConfig()

            // Toggle read-only status on the branch metadata
            if setReadOnly && !(bundle.activeBranchInfo?.readOnly ?? false) {
                try bundle.setBranchReadOnly(true)
            } else if clearReadOnly && (bundle.activeBranchInfo?.readOnly ?? false) {
                try bundle.setBranchReadOnly(false)
            }

            // Display the configuration (after any changes)
            let isReadOnly = bundle.activeBranchInfo?.readOnly ?? false
            print("Branch:      \(bundle.meta.activeBranch)\(isReadOnly ? " [read-only]" : "")")
            displayConfig(bundle.config, branchURL: bundle.activeBranchURL)
        }

        private func displayConfig(_ config: VMConfig, branchURL: URL) {
            print("Boot mode:   \(config.bootMode.label)")
            if config.bootMode != .macOS {
                if let kernel = config.kernel {
                    print("Kernel:      \(kernel)")
                }
                if let initrd = config.initrd {
                    print("Initrd:      \(initrd)")
                }
            }
            print("CPUs:        \(config.cpus)")
            print("Memory:      \(config.memoryGB) GB")
            print("Network:     \(config.network ? "yes" : "no")")
            print("Audio:       \(config.audio ? "yes" : "no")")
            if config.bootMode != .macOS {
                print("Rosetta:     \(config.rosetta ? "yes" : "no")")
            }
            if config.bootMode == .linux {
                print("Kernel args: \(config.kernelCommandLine.joined(separator: " "))")
            }
            if config.bootMode == .macOS {
                let hwModelExists = FileManager.default.fileExists(
                    atPath: config.hardwareModelURL(in: branchURL).path)
                let auxStorageExists = FileManager.default.fileExists(
                    atPath: config.auxiliaryStorageURL(in: branchURL).path)
                print("Hardware:    \(hwModelExists ? "configured" : "not configured")")
                print("Aux storage: \(auxStorageExists ? "present" : "missing")")
            }

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

            if config.usbDisks.isEmpty {
                print("USB disks:   (none)")
            } else {
                print("USB disks:")
                for (idx, usbDisk) in config.usbDisks.enumerated() {
                    let rwLabel = usbDisk.readOnly ? "ro" : "rw"
                    print("  [\(idx), \(rwLabel)] \(usbDisk.path)")
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
    }
}
