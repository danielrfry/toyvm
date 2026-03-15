//
//  Create.swift
//  toyvm
//

import ArgumentParser
import Foundation
import Virtualization

extension ToyVM {
    struct CreateCommand: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "create",
            abstract: "Create a VM bundle",
            discussion: """
                Creates a VM bundle directory containing the kernel, optional initrd, \
                disk images, and a configuration file. Remaining positional arguments \
                are stored as the kernel command line. \
                Use -- to separate toyvm options from kernel arguments that begin with -.
                """
        )

        @Argument(help: "Path to the VM bundle directory to create")
        var bundle: String

        @Option(name: [.customShort("k"), .long], help: "Path to the kernel image to copy into the bundle [required]")
        var kernel: String

        @Option(name: [.customShort("i"), .long], help: "Path to an initrd image to copy into the bundle")
        var initrd: String?

        @Option(name: [.customShort("d"), .long], help: "Create a read/write disk image of the given size (e.g. 20G, 512M, asif:20G)")
        var disk: [String] = []

        @Option(name: [.customShort("r"), .customLong("disk-ro")], help: "As --disk but marks the disk image as read-only")
        var diskRO: [String] = []

        @Option(name: [.customShort("s"), .long], help: "Add a directory share; accepts [tag:]path (tag defaults to \"share\")")
        var share: [String] = []

        @Option(name: [.customShort("t"), .customLong("share-ro")], help: "As --share but adds a read-only directory share")
        var shareRO: [String] = []

        @Option(name: [.customShort("p"), .long], help: "Number of CPUs to make available to the VM")
        var cpus: Int = 2

        @Option(name: [.customShort("m"), .long], help: "Amount of memory in gigabytes to reserve for the VM")
        var memory: Int = 2

        @Flag(name: [.customShort("a"), .customLong("audio")], help: "Enable virtual audio device")
        var audio: Bool = false

        @Flag(name: .customLong("no-net"), help: "Do not add a virtual network interface")
        var noNet: Bool = false

        @Flag(name: .customLong("enable-rosetta"), help: "Enable the Rosetta directory share in the guest OS")
        var enableRosetta: Bool = false

        @Argument(help: "Kernel command line (default: console=hvc0)")
        var kernelCommandLine: [String] = []

        mutating func run() throws {
            let bundleURL = try resolveBundlePath(bundle, createParentIfNeeded: true)
            let fm = FileManager.default
            var bundleCreated = false

            do {
                try fm.createDirectory(at: bundleURL, withIntermediateDirectories: false)
                bundleCreated = true

                // Create branches directory and the root "main" branch subdirectory
                let branchesDir = bundleURL.appendingPathComponent(VMConfig.branchesDir)
                try fm.createDirectory(at: branchesDir, withIntermediateDirectories: false)
                let rootBranch = "main"
                let branchURL = VMConfig.branchURL(in: bundleURL, branch: rootBranch)
                try fm.createDirectory(at: branchURL, withIntermediateDirectories: false)

                // Create kernel, initrd, and disks subdirectories inside the branch
                let kernelDir = branchURL.appendingPathComponent(VMConfig.kernelDir)
                let initrdDir = branchURL.appendingPathComponent(VMConfig.initrdDir)
                let disksDir = branchURL.appendingPathComponent(VMConfig.disksDir)
                try fm.createDirectory(at: kernelDir, withIntermediateDirectories: false)
                try fm.createDirectory(at: initrdDir, withIntermediateDirectories: false)
                try fm.createDirectory(at: disksDir, withIntermediateDirectories: false)

                // Copy kernel
                let kernelSrc = URL(fileURLWithPath: kernel)
                let kernelFilename = kernelSrc.lastPathComponent
                try fm.copyItem(at: kernelSrc, to: kernelDir.appendingPathComponent(kernelFilename))

                // Copy initrd
                var initrdFilename: String? = nil
                if let initrdPath = initrd {
                    let initrdSrc = URL(fileURLWithPath: initrdPath)
                    initrdFilename = initrdSrc.lastPathComponent
                    try fm.copyItem(at: initrdSrc, to: initrdDir.appendingPathComponent(initrdFilename!))
                }

                // Create disk images
                var diskConfigs: [DiskConfig] = []
                var diskIndex = 0
                for spec in disk {
                    let (format, size) = try parseDiskSpec(spec)
                    let name = "disk\(diskIndex).\(format.fileExtension)"
                    try createDisk(at: disksDir.appendingPathComponent(name), size: size, format: format)
                    diskConfigs.append(DiskConfig(file: name, readOnly: false, format: format))
                    diskIndex += 1
                }
                for spec in diskRO {
                    let (format, size) = try parseDiskSpec(spec)
                    let name = "disk\(diskIndex).\(format.fileExtension)"
                    try createDisk(at: disksDir.appendingPathComponent(name), size: size, format: format)
                    diskConfigs.append(DiskConfig(file: name, readOnly: true, format: format))
                    diskIndex += 1
                }

                // Collect directory shares, validating tags and detecting duplicates
                var shareConfigs: [ShareConfig] = []
                var seenTags = Set<String>()
                for arg in share {
                    let (tag, path) = parseShareArg(arg)
                    try VZVirtioFileSystemDeviceConfiguration.validateTag(tag)
                    guard seenTags.insert(tag).inserted else {
                        throw ToyVMError("Duplicate share tag: \(tag)")
                    }
                    shareConfigs.append(ShareConfig(tag: tag, path: path, readOnly: false))
                }
                for arg in shareRO {
                    let (tag, path) = parseShareArg(arg)
                    try VZVirtioFileSystemDeviceConfiguration.validateTag(tag)
                    guard seenTags.insert(tag).inserted else {
                        throw ToyVMError("Duplicate share tag: \(tag)")
                    }
                    shareConfigs.append(ShareConfig(tag: tag, path: path, readOnly: true))
                }

                let cmdLine = kernelCommandLine.isEmpty ? ["console=hvc0"] : kernelCommandLine
                let config = VMConfig(
                    cpus: cpus,
                    memoryGB: memory,
                    audio: audio,
                    network: !noNet,
                    rosetta: enableRosetta,
                    kernel: kernelFilename,
                    initrd: initrdFilename,
                    kernelCommandLine: cmdLine,
                    disks: diskConfigs,
                    shares: shareConfigs
                )
                try config.save(to: branchURL)

                // Write bundle-level metadata
                let bundleMeta = BundleMeta(rootBranch: rootBranch)
                try bundleMeta.save(to: bundleURL)

                print("Created VM bundle: \(bundle)")
            } catch {
                if bundleCreated {
                    try? fm.removeItem(at: bundleURL)
                }
                throw error
            }
        }
    }
}

