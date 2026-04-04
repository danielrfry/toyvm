//
//  Create.swift
//  toyvm
//

import ArgumentParser
import Foundation
#if canImport(ToyVMCore)
import ToyVMCore
#endif
import Virtualization

extension ToyVM {
    struct CreateCommand: AsyncParsableCommand {
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

        @Flag(name: .customLong("efi"), help: "Use EFI boot mode (for graphical Linux VMs)")
        var efi: Bool = false

        @Flag(name: .customLong("macos"), help: "Create a macOS VM (Apple Silicon only)")
        var macos: Bool = false

        @Option(name: .customLong("restore-image"), help: "Path to macOS restore image (.ipsw) for --macos")
        var restoreImage: String? = nil

        @Option(name: [.customShort("k"), .long], help: "Path to the kernel image to copy into the bundle [required for Linux mode]")
        var kernel: String? = nil

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

        @Option(name: .customLong("usb"), help: "Configure a USB disk image (read-write)")
        var usbDisk: [String] = []

        @Option(name: .customLong("usb-ro"), help: "Configure a USB disk image (read-only, e.g. .iso installer)")
        var usbDiskRO: [String] = []

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

        mutating func validate() throws {
            if efi && macos {
                throw ValidationError("--efi and --macos are mutually exclusive")
            }
            if macos {
                #if !arch(arm64)
                throw ValidationError("--macos requires Apple Silicon")
                #endif
                guard restoreImage != nil else {
                    throw ValidationError("--macos requires --restore-image <path>")
                }
            }
        }

        mutating func run() async throws {
            let bundleURL = try resolveBundlePath(bundle, createParentIfNeeded: true)

            let bootMode: BootMode
            if macos {
                bootMode = .macOS
            } else if efi {
                bootMode = .efi
            } else {
                bootMode = .linux
            }

            // Validate kernel requirement based on boot mode
            if bootMode == .linux && kernel == nil {
                throw ValidationError("--kernel is required for Linux boot mode (use --efi for EFI boot)")
            }

            // Parse disk specs
            var diskSpecs: [(format: DiskFormat, size: UInt64, readOnly: Bool)] = []
            for spec in disk {
                let (format, size) = try parseDiskSpec(spec)
                diskSpecs.append((format, size, false))
            }
            for spec in diskRO {
                let (format, size) = try parseDiskSpec(spec)
                diskSpecs.append((format, size, true))
            }

            // Parse and validate share specs (tag validation requires Virtualization.framework)
            var shareConfigs: [ShareConfig] = []
            var seenTags = Set<String>()
            for (arg, readOnly) in share.map({ ($0, false) }) + shareRO.map({ ($0, true) }) {
                let (tag, path) = parseShareArg(arg)
                try VZVirtioFileSystemDeviceConfiguration.validateTag(tag)
                guard seenTags.insert(tag).inserted else {
                    throw ToyVMError("Duplicate share tag: \(tag)")
                }
                shareConfigs.append(ShareConfig(tag: tag, path: path, readOnly: readOnly))
            }

            // Parse USB disk paths
            var usbDisks: [USBDiskConfig] = []
            for path in usbDisk {
                usbDisks.append(USBDiskConfig(path: path, readOnly: false))
            }
            for path in usbDiskRO {
                usbDisks.append(USBDiskConfig(path: path, readOnly: true))
            }

            var options = CreateOptions()
            options.cpus = cpus
            options.memoryGB = memory
            options.audio = audio
            options.network = !noNet
            options.rosetta = enableRosetta
            options.bootMode = bootMode
            options.kernelCommandLine = kernelCommandLine.isEmpty ? ["console=hvc0"] : kernelCommandLine
            options.disks = diskSpecs
            options.shares = shareConfigs
            options.usbDisks = usbDisks

            var vmBundle = try VMBundle.create(
                at: bundleURL,
                kernelPath: kernel.map { URL(fileURLWithPath: $0) },
                initrdPath: initrd.map { URL(fileURLWithPath: $0) },
                options: options
            )

            print("Created VM bundle: \(bundle)")

            #if arch(arm64)
            if bootMode == .macOS, let restoreImagePath = restoreImage {
                if #available(macOS 14.0, *) {
                    let installManager = MacOSInstallManager()
                    fputs("Installing macOS...\n", stderr)

                    // Observe progress on a background task
                    let progressTask = Task {
                        var lastPct = -1
                        while !Task.isCancelled {
                            try? await Task.sleep(nanoseconds: 500_000_000)
                            let pct = Int(installManager.installProgress * 100)
                            if pct != lastPct {
                                lastPct = pct
                                fputs("\rInstalling macOS... \(pct)%", stderr)
                            }
                        }
                    }

                    do {
                        try await installManager.install(
                            bundle: &vmBundle,
                            restoreImageURL: URL(fileURLWithPath: restoreImagePath)
                        )
                        progressTask.cancel()
                        fputs("\rInstalling macOS... 100%\n", stderr)
                        print("macOS installation complete.")
                    } catch {
                        // Delete the partially-initialized bundle
                        try? FileManager.default.removeItem(at: bundleURL)
                        progressTask.cancel()
                        fputs("\n", stderr)
                        throw error
                    }
                } else {
                    throw ToyVMError("macOS VM support requires macOS 14.0 or later")
                }
            }
            #endif
        }
    }
}
