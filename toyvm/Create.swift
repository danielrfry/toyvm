//
//  Create.swift
//  toyvm
//

import ArgumentParser
import Foundation
import Virtualization

extension ToyVM {
    struct Create: ParsableCommand {
        static let configuration = CommandConfiguration(
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

        @Option(name: [.customShort("d"), .long], help: "Create a read/write disk image of the given size (e.g. 20G, 512M)")
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
            let bundleURL = URL(fileURLWithPath: bundle, isDirectory: true)
            let fm = FileManager.default
            var bundleCreated = false

            do {
                try fm.createDirectory(at: bundleURL, withIntermediateDirectories: false)
                bundleCreated = true

                // Copy kernel
                let kernelSrc = URL(fileURLWithPath: kernel)
                let kernelRelPath = kernelSrc.lastPathComponent
                try fm.copyItem(at: kernelSrc, to: bundleURL.appendingPathComponent(kernelRelPath))

                // Copy initrd
                var initrdRelPath: String? = nil
                if let initrdPath = initrd {
                    let initrdSrc = URL(fileURLWithPath: initrdPath)
                    initrdRelPath = initrdSrc.lastPathComponent
                    try fm.copyItem(at: initrdSrc, to: bundleURL.appendingPathComponent(initrdRelPath!))
                }

                // Create disk images (r/w first, then r/o — matching start command ordering)
                var diskConfigs: [DiskConfig] = []
                var diskIndex = 0
                for sizeStr in disk {
                    let name = "disk\(diskIndex).img"
                    try createSparseFile(at: bundleURL.appendingPathComponent(name), size: parseSize(sizeStr))
                    diskConfigs.append(DiskConfig(file: name, readOnly: false))
                    diskIndex += 1
                }
                for sizeStr in diskRO {
                    let name = "disk\(diskIndex).img"
                    try createSparseFile(at: bundleURL.appendingPathComponent(name), size: parseSize(sizeStr))
                    diskConfigs.append(DiskConfig(file: name, readOnly: true))
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
                    kernel: kernelRelPath,
                    initrd: initrdRelPath,
                    kernelCommandLine: cmdLine,
                    disks: diskConfigs,
                    shares: shareConfigs
                )
                try config.save(to: bundleURL)

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

