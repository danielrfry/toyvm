//
//  Start.swift
//  toyvm
//

import ArgumentParser
import CoreFoundation
import Darwin
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

        @Option(name: [.customShort("p"), .long], help: "Number of CPUs to make available to the VM")
        var cpus: Int? = nil

        @Option(name: [.customShort("m"), .long], help: "Amount of memory in gigabytes to reserve for the VM")
        var memory: Int? = nil

        @Flag(name: [.customShort("a"), .customLong("audio")], help: "Enable virtual audio device")
        var audio: Bool = false

        @Flag(name: .customLong("no-net"), help: "Do not add a virtual network interface")
        var noNet: Bool = false

        @Flag(name: .customLong("enable-rosetta"), help: "Enable the Rosetta directory share in the guest OS")
        var enableRosetta: Bool = false

        mutating func run() throws {
            // Load bundle config if a bundle string was given (accept bare VM names)
            var bundleURL: URL? = nil
            var branchURL: URL? = nil
            var bundleConfig: VMConfig? = nil
            if let b = bundle {
                bundleURL = try resolveBundlePath(b, createParentIfNeeded: false)
                let meta = try BundleMeta.load(from: bundleURL!)
                if meta.branches[meta.activeBranch]?.readOnly == true {
                    throw ToyVMError(
                        "Branch '\(meta.activeBranch)' is read-only; the VM cannot be started on a read-only branch."
                    )
                }
                branchURL = VMConfig.branchURL(in: bundleURL!, branch: meta.activeBranch)
                bundleConfig = try VMConfig.load(from: branchURL!)
            }

            // Resolve kernel path: CLI option takes precedence, then active branch
            guard let effectiveKernelPath = kernel
                    ?? bundleConfig.flatMap({ cfg in branchURL.map { cfg.kernelURL(in: $0).path } })
            else {
                throw ValidationError("--kernel is required when no VM bundle is specified")
            }

            let config = VZVirtualMachineConfiguration()

            // Networking: --no-net disables; bundle or default enables
            if !noNet && (bundleConfig?.network ?? true) {
                let netDev = VZVirtioNetworkDeviceConfiguration()
                netDev.attachment = VZNATNetworkDeviceAttachment()
                config.networkDevices = [netDev]
            }

            let consoleCfg = VZVirtioConsoleDeviceSerialPortConfiguration()
            consoleCfg.attachment = VZFileHandleSerialPortAttachment(
                fileHandleForReading: .standardInput,
                fileHandleForWriting: .standardOutput
            )
            config.serialPorts = [consoleCfg]

            let bootLoader = VZLinuxBootLoader(kernelURL: URL(fileURLWithPath: effectiveKernelPath))

            let effectiveInitrd: String?
            if let i = initrd {
                effectiveInitrd = i
            } else if let cfg = bundleConfig, let bURL = branchURL, let initrdURL = cfg.initrdURL(in: bURL) {
                effectiveInitrd = initrdURL.path
            } else {
                effectiveInitrd = nil
            }
            if let initrdPath = effectiveInitrd {
                bootLoader.initialRamdiskURL = URL(fileURLWithPath: initrdPath)
            }

            bootLoader.commandLine = cmdline
                ?? bundleConfig.map { $0.kernelCommandLine.joined(separator: " ") }
                ?? "console=hvc0"
            config.bootLoader = bootLoader

            config.cpuCount = cpus ?? bundleConfig?.cpus ?? 2
            config.memorySize = UInt64(memory ?? bundleConfig?.memoryGB ?? 2) * 1024 * 1024 * 1024

            // Storage: bundle disks first (paths resolved relative to active branch), then CLI disks
            var storageDevices: [VZStorageDeviceConfiguration] = []
            if let cfg = bundleConfig, let bURL = branchURL {
                for d in cfg.disks {
                    storageDevices.append(try makeStorageDevice(path: cfg.diskURL(in: bURL, disk: d).path, readOnly: d.readOnly))
                }
            }
            for path in disk {
                storageDevices.append(try makeStorageDevice(path: path, readOnly: false))
            }
            for path in diskRO {
                storageDevices.append(try makeStorageDevice(path: path, readOnly: true))
            }
            config.storageDevices = storageDevices

            // Shares: bundle shares form the base (keyed by tag); CLI shares add or replace
            var sharedDirs: [String: VZVirtioFileSystemDeviceConfiguration] = [:]
            if let cfg = bundleConfig {
                for s in cfg.shares {
                    sharedDirs[s.tag] = try makeShareDeviceFromConfig(s)
                }
            }
            for arg in share {
                let cfg = try makeShareDevice(arg: arg, readOnly: false)
                sharedDirs[cfg.tag] = cfg
            }
            for arg in shareRO {
                let cfg = try makeShareDevice(arg: arg, readOnly: true)
                sharedDirs[cfg.tag] = cfg
            }

            // Audio: --audio enables; bundle config also enables; neither means disabled
            if audio || (bundleConfig?.audio ?? false) {
                config.audioDevices = [makeSoundDevice()]
            }

            // Rosetta: --enable-rosetta enables; bundle config also enables
            if enableRosetta || (bundleConfig?.rosetta ?? false) {
                sharedDirs["rosetta"] = try makeRosettaShareDevice()
            }

            config.directorySharingDevices = Array(sharedDirs.values)

            try config.validate()

            let vmDelegate = ToyVMDelegate()
            let vm = VZVirtualMachine(configuration: config)
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

        private func makeStorageDevice(path: String, readOnly: Bool) throws -> VZVirtioBlockDeviceConfiguration {
            let attachment = try VZDiskImageStorageDeviceAttachment(url: URL(fileURLWithPath: path), readOnly: readOnly)
            return VZVirtioBlockDeviceConfiguration(attachment: attachment)
        }

        private func makeShareDevice(arg: String, readOnly: Bool) throws -> VZVirtioFileSystemDeviceConfiguration {
            let tag: String
            let path: String
            if let colonIdx = arg.firstIndex(of: ":") {
                tag = String(arg[arg.startIndex..<colonIdx])
                path = String(arg[arg.index(after: colonIdx)...])
            } else {
                tag = "share"
                path = arg
            }
            try VZVirtioFileSystemDeviceConfiguration.validateTag(tag)
            let cfg = VZVirtioFileSystemDeviceConfiguration(tag: tag)
            cfg.share = VZSingleDirectoryShare(directory: VZSharedDirectory(url: URL(fileURLWithPath: path), readOnly: readOnly))
            return cfg
        }

        private func makeShareDeviceFromConfig(_ shareCfg: ShareConfig) throws -> VZVirtioFileSystemDeviceConfiguration {
            try VZVirtioFileSystemDeviceConfiguration.validateTag(shareCfg.tag)
            let cfg = VZVirtioFileSystemDeviceConfiguration(tag: shareCfg.tag)
            cfg.share = VZSingleDirectoryShare(directory: VZSharedDirectory(url: URL(fileURLWithPath: shareCfg.path), readOnly: shareCfg.readOnly))
            return cfg
        }

        private func makeSoundDevice() -> VZVirtioSoundDeviceConfiguration {
            let cfg = VZVirtioSoundDeviceConfiguration()
            let inputStream = VZVirtioSoundDeviceInputStreamConfiguration()
            inputStream.source = VZHostAudioInputStreamSource()
            let outputStream = VZVirtioSoundDeviceOutputStreamConfiguration()
            outputStream.sink = VZHostAudioOutputStreamSink()
            cfg.streams = [inputStream, outputStream]
            return cfg
        }

        private func makeRosettaShareDevice() throws -> VZVirtioFileSystemDeviceConfiguration {
            #if arch(arm64)
            if #available(macOS 13.0, *) {
                let share = try VZLinuxRosettaDirectoryShare()
                let cfg = VZVirtioFileSystemDeviceConfiguration(tag: "rosetta")
                cfg.share = share
                return cfg
            } else {
                throw ToyVMError("--enable-rosetta requires macOS 13.0 or later")
            }
            #else
            throw ToyVMError("--enable-rosetta requires an Apple Silicon processor")
            #endif
        }
    }
}
