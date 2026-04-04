//
//  Start.swift
//  toyvm
//

import ArgumentParser
import CoreFoundation
import Darwin
#if canImport(ToyVMCore)
import ToyVMCore
#endif
import Virtualization

extension ToyVM {
    struct StartCommand: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "start",
            abstract: "Start a VM",
            discussion: """
                When a VM bundle is specified, configuration is loaded from the bundle. \
                Any options provided on the command line override the bundle configuration. \
                Without a bundle, --kernel is required. \
                Use -- to separate toyvm options from arguments that begin with -.
                """
        )

        @Argument(help: "Path to a VM bundle to start")
        var bundle: String? = nil

        @Option(name: [.customShort("k"), .long], help: "Path to the kernel image to load (required without a bundle)")
        var kernel: String? = nil

        @Option(name: [.customShort("i"), .long], help: "Path to an initrd image to load")
        var initrd: String? = nil

        @Option(name: [.customShort("c"), .customLong("cmdline")], help: "Kernel command line (default: console=hvc0)")
        var cmdline: String? = nil

        @Option(name: [.customShort("d"), .long], help: "Add a read/write virtual storage device backed by the specified raw disk image file")
        var disk: [String] = []

        @Option(name: [.customShort("r"), .customLong("disk-ro")], help: "As --disk but adds a read-only storage device")
        var diskRO: [String] = []

        @Option(name: [.customShort("s"), .long], help: "Add a directory share device; accepts [tag:]path (tag defaults to \"share\")")
        var share: [String] = []

        @Option(name: [.customShort("t"), .customLong("share-ro")], help: "As --share but adds a read-only directory share")
        var shareRO: [String] = []

        @Option(name: .customLong("usb"), help: "Attach a USB disk image (read-write)")
        var usb: [String] = []

        @Option(name: .customLong("usb-ro"), help: "Attach a USB disk image (read-only, e.g. .iso installer)")
        var usbRO: [String] = []

        @Option(name: [.customShort("p"), .long], help: "Number of CPUs to make available to the VM")
        var cpus: Int? = nil

        @Option(name: [.customShort("m"), .long], help: "Amount of memory in gigabytes to reserve for the VM")
        var memory: Int? = nil

        @Flag(name: [.customShort("a"), .customLong("audio")], help: "Enable virtual audio device")
        var audio: Bool = false

        @Flag(name: .customLong("no-net"), help: "Do not add a virtual network interface")
        var noNet: Bool = false

        @Flag(name: .customLong("no-persist"), help: "Use copy-on-write clones of disk images; originals are not modified")
        var noPersist: Bool = false

        @Flag(name: .customLong("enable-rosetta"), help: "Enable the Rosetta directory share in the guest OS")
        var enableRosetta: Bool = false

        mutating func run() throws {
            // Collect CLI USB disks
            var cliUSBDisks: [USBDiskConfig] = []
            for path in usb {
                cliUSBDisks.append(USBDiskConfig(path: path, readOnly: false))
            }
            for path in usbRO {
                cliUSBDisks.append(USBDiskConfig(path: path, readOnly: true))
            }

            // Load bundle config if a bundle string was given (accept bare VM names)
            var bundleConfig: VMConfig? = nil
            var branchURL: URL? = nil
            var vmBundle: VMBundle? = nil
            if let b = bundle {
                let bundleURL = try resolveBundlePath(b, createParentIfNeeded: false)
                let loaded = try VMBundle.load(from: bundleURL)
                if loaded.activeBranchInfo?.readOnly == true {
                    throw ToyVMError(
                        "Branch '\(loaded.meta.activeBranch)' is read-only; the VM cannot be started on a read-only branch."
                    )
                }
                branchURL = loaded.activeBranchURL
                bundleConfig = loaded.config
                vmBundle = loaded
            }

            // For EFI mode bundles, use the bundle-based builder directly
            if let vmBundle, vmBundle.config.bootMode == .efi {
                // Merge CLI USB disks with bundle config
                var bundleCopy = vmBundle
                for usbDisk in cliUSBDisks {
                    bundleCopy.addUSBDisk(usbDisk)
                }
                let ctx = try VirtualMachineBuilder.buildConfiguration(
                    from: bundleCopy, noPersist: noPersist)
                defer { ctx.cleanup() }

                // Attach the console serial port to stdin/stdout (CLI-specific)
                let consoleCfg = VZVirtioConsoleDeviceSerialPortConfiguration()
                consoleCfg.attachment = VZFileHandleSerialPortAttachment(
                    fileHandleForReading: .standardInput,
                    fileHandleForWriting: .standardOutput
                )
                ctx.configuration.serialPorts = [consoleCfg]

                return try runVM(configuration: ctx.configuration)
            }

            // Linux boot mode (direct kernel or bundle-based)

            // Resolve kernel path: CLI option takes precedence, then active branch
            guard let effectiveKernelPath = kernel
                    ?? bundleConfig.flatMap({ cfg in branchURL.flatMap { cfg.kernelURL(in: $0)?.path } })
            else {
                throw ValidationError("--kernel is required when no VM bundle is specified")
            }

            let effectiveInitrd: String?
            if let i = initrd {
                effectiveInitrd = i
            } else if let cfg = bundleConfig, let bURL = branchURL, let initrdURL = cfg.initrdURL(in: bURL) {
                effectiveInitrd = initrdURL.path
            } else {
                effectiveInitrd = nil
            }

            let effectiveCmdline = cmdline
                ?? bundleConfig.map { $0.kernelCommandLine.joined(separator: " ") }
                ?? "console=hvc0"

            // Build disk list: bundle disks first, then CLI-specified disks
            var diskPaths: [(url: URL, readOnly: Bool)] = []
            if let cfg = bundleConfig, let bURL = branchURL {
                for d in cfg.disks {
                    diskPaths.append((url: cfg.diskURL(in: bURL, disk: d), readOnly: d.readOnly))
                }
            }
            for path in disk {
                diskPaths.append((url: URL(fileURLWithPath: path), readOnly: false))
            }
            for path in diskRO {
                diskPaths.append((url: URL(fileURLWithPath: path), readOnly: true))
            }

            // Build share list: bundle shares form the base; CLI shares add or replace (keyed by tag)
            var shareMap: [String: ShareConfig] = [:]
            if let cfg = bundleConfig {
                for s in cfg.shares {
                    shareMap[s.tag] = s
                }
            }
            for arg in share {
                let (tag, path) = parseShareArg(arg)
                shareMap[tag] = ShareConfig(tag: tag, path: path, readOnly: false)
            }
            for arg in shareRO {
                let (tag, path) = parseShareArg(arg)
                shareMap[tag] = ShareConfig(tag: tag, path: path, readOnly: true)
            }

            // Merge USB disks from bundle config and CLI
            var allUSBDisks = bundleConfig?.usbDisks ?? []
            allUSBDisks.append(contentsOf: cliUSBDisks)

            let ctx = try VirtualMachineBuilder.buildConfiguration(
                kernelURL: URL(fileURLWithPath: effectiveKernelPath),
                initrdURL: effectiveInitrd.map { URL(fileURLWithPath: $0) },
                commandLine: effectiveCmdline,
                cpuCount: cpus ?? bundleConfig?.cpus ?? 2,
                memoryGB: memory ?? bundleConfig?.memoryGB ?? 2,
                enableNetwork: !noNet && (bundleConfig?.network ?? true),
                enableAudio: audio || (bundleConfig?.audio ?? false),
                enableRosetta: enableRosetta || (bundleConfig?.rosetta ?? false),
                diskPaths: diskPaths,
                shares: Array(shareMap.values),
                usbDisks: allUSBDisks,
                noPersist: noPersist
            )
            defer { ctx.cleanup() }

            // Attach the console serial port to stdin/stdout (CLI-specific)
            let consoleCfg = VZVirtioConsoleDeviceSerialPortConfiguration()
            consoleCfg.attachment = VZFileHandleSerialPortAttachment(
                fileHandleForReading: .standardInput,
                fileHandleForWriting: .standardOutput
            )
            ctx.configuration.serialPorts = [consoleCfg]

            try runVM(configuration: ctx.configuration)
        }

        private func runVM(configuration: VZVirtualMachineConfiguration) throws {
            let vmDelegate = ToyVMDelegate()
            let vm = VZVirtualMachine(configuration: configuration)
            vm.delegate = vmDelegate
            vm.start { result in
                if case .failure(let error) = result {
                    fputs("Error starting VM: \(error.localizedDescription)\n", stderr)
                }
            }

            var termInfo = termios()
            tcgetattr(STDIN_FILENO, &termInfo)
            var rawTermInfo = termInfo
            cfmakeraw(&rawTermInfo)
            tcsetattr(STDIN_FILENO, TCSANOW, &rawTermInfo)

            CFRunLoopRun()

            tcsetattr(STDIN_FILENO, TCSANOW, &termInfo)

            if let error = vmDelegate.error {
                fputs("\(error.localizedDescription)\n", stderr)
                throw ExitCode(1)
            }
        }
    }
}
