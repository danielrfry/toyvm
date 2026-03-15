//
//  Config.swift
//  toyvm
//

import ArgumentParser
import Foundation
import Virtualization

extension ToyVM {
    struct Config: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Update the configuration of a VM bundle"
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

        @Option(name: [.customShort("d"), .long], help: "Add a read/write disk image of the given size (e.g. 20G, 512M)")
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
        }

        mutating func run() throws {
            let bundleURL = URL(fileURLWithPath: bundle, isDirectory: true)
            let fm = FileManager.default
            var config = try VMConfig.load(from: bundleURL)

            // Kernel replacement
            if let newKernelPath = kernel {
                let src = URL(fileURLWithPath: newKernelPath)
                let newRelName = src.lastPathComponent
                let oldRelName = config.kernel
                if newRelName != oldRelName {
                    try fm.copyItem(at: src, to: bundleURL.appendingPathComponent(newRelName))
                    try fm.removeItem(at: bundleURL.appendingPathComponent(oldRelName))
                } else {
                    // Same filename — replace in place
                    let dest = bundleURL.appendingPathComponent(newRelName)
                    _ = try fm.replaceItemAt(dest, withItemAt: src)
                }
                config.kernel = newRelName
            }

            // Initrd replacement / removal
            if let newInitrdPath = initrd {
                let src = URL(fileURLWithPath: newInitrdPath)
                let newRelName = src.lastPathComponent
                if let oldRelName = config.initrd, oldRelName != newRelName {
                    try fm.copyItem(at: src, to: bundleURL.appendingPathComponent(newRelName))
                    try fm.removeItem(at: bundleURL.appendingPathComponent(oldRelName))
                } else if config.initrd == nil {
                    try fm.copyItem(at: src, to: bundleURL.appendingPathComponent(newRelName))
                } else {
                    let dest = bundleURL.appendingPathComponent(newRelName)
                    _ = try fm.replaceItemAt(dest, withItemAt: src)
                }
                config.initrd = newRelName
            } else if removeInitrd {
                if let oldRelName = config.initrd {
                    try fm.removeItem(at: bundleURL.appendingPathComponent(oldRelName))
                    config.initrd = nil
                }
            }

            // Kernel command line
            if let line = cmdline {
                config.kernelCommandLine = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
                    .nonEmpty ?? ["console=hvc0"]
            }

            // Remove disks
            for name in removeDisk {
                guard let idx = config.disks.firstIndex(where: { $0.file == name }) else {
                    throw ToyVMError("No disk named '\(name)' in this bundle")
                }
                try fm.removeItem(at: bundleURL.appendingPathComponent(name))
                config.disks.remove(at: idx)
            }

            // Add disks
            for sizeStr in disk {
                let name = nextDiskFilename(existing: config.disks)
                try createSparseFile(at: bundleURL.appendingPathComponent(name), size: parseSize(sizeStr))
                config.disks.append(DiskConfig(file: name, readOnly: false))
            }
            for sizeStr in diskRO {
                let name = nextDiskFilename(existing: config.disks)
                try createSparseFile(at: bundleURL.appendingPathComponent(name), size: parseSize(sizeStr))
                config.disks.append(DiskConfig(file: name, readOnly: true))
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

            try config.save(to: bundleURL)
        }
    }
}

private extension Array {
    /// Returns the array if non-empty, otherwise nil.
    var nonEmpty: Self? { isEmpty ? nil : self }
}
