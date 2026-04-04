//
//  VirtualMachineBuilder.swift
//  ToyVMCore
//

import Foundation
import Virtualization

/// Result of building a VM configuration, including any temporary files that
/// should be cleaned up after the VM stops.
public struct VMStartContext {
    public let configuration: VZVirtualMachineConfiguration
    /// Paths to copy-on-write clone files created for --no-persist mode.
    public let cleanupPaths: [String]
    /// Whether the configuration includes a graphics display device (for GUI display routing).
    public let hasGraphicsDevice: Bool

    public func cleanup() {
        for path in cleanupPaths {
            try? FileManager.default.removeItem(atPath: path)
        }
    }
}

/// Builds a fully validated `VZVirtualMachineConfiguration` from either a VM
/// bundle or explicit parameters. Serial ports are intentionally left
/// unconfigured — the caller must add its own serial port attachment (e.g.
/// stdin/stdout for the CLI, or a pipe pair for a GUI terminal emulator).
public enum VirtualMachineBuilder {

    // MARK: - Bundle-based convenience

    /// Build a configuration directly from a VM bundle's active branch.
    public static func buildConfiguration(
        from bundle: VMBundle,
        noPersist: Bool = false
    ) throws -> VMStartContext {
        let config = bundle.config
        let branchURL = bundle.activeBranchURL

        switch config.bootMode {
        case .linux:
            guard let kernelURL = config.kernelURL(in: branchURL) else {
                throw ToyVMError("Linux boot mode requires a kernel image")
            }
            let initrdURL = config.initrdURL(in: branchURL)
            let cmdline = config.kernelCommandLine.joined(separator: " ")

            let diskPaths = config.disks.map { disk in
                (url: config.diskURL(in: branchURL, disk: disk), readOnly: disk.readOnly)
            }

            return try buildConfiguration(
                kernelURL: kernelURL,
                initrdURL: initrdURL,
                commandLine: cmdline,
                cpuCount: config.cpus,
                memoryGB: config.memoryGB,
                enableNetwork: config.network,
                enableAudio: config.audio,
                enableRosetta: config.rosetta,
                diskPaths: diskPaths,
                shares: config.shares,
                usbDisks: config.usbDisks,
                noPersist: noPersist
            )

        case .efi:
            guard #available(macOS 13.0, *) else {
                throw ToyVMError("EFI boot mode requires macOS 13.0 or later")
            }
            let efiVarStoreURL = config.efiVariableStoreURL(in: branchURL)
            let diskPaths = config.disks.map { disk in
                (url: config.diskURL(in: branchURL, disk: disk), readOnly: disk.readOnly)
            }

            return try buildEFIConfiguration(
                efiVariableStoreURL: efiVarStoreURL,
                cpuCount: config.cpus,
                memoryGB: config.memoryGB,
                enableNetwork: config.network,
                enableAudio: config.audio,
                enableRosetta: config.rosetta,
                diskPaths: diskPaths,
                shares: config.shares,
                usbDisks: config.usbDisks,
                noPersist: noPersist
            )
        }
    }

    // MARK: - Explicit parameter entry point (Linux boot)

    /// Build a Linux boot configuration with full control over all parameters.
    public static func buildConfiguration(
        kernelURL: URL,
        initrdURL: URL? = nil,
        commandLine: String = "console=hvc0",
        cpuCount: Int = 2,
        memoryGB: Int = 2,
        enableNetwork: Bool = true,
        enableAudio: Bool = false,
        enableRosetta: Bool = false,
        diskPaths: [(url: URL, readOnly: Bool)] = [],
        shares: [ShareConfig] = [],
        usbDisks: [USBDiskConfig] = [],
        noPersist: Bool = false
    ) throws -> VMStartContext {
        let vzConfig = VZVirtualMachineConfiguration()
        var cleanupPaths: [String] = []

        // Boot loader
        let bootLoader = VZLinuxBootLoader(kernelURL: kernelURL)
        if let initrdURL {
            bootLoader.initialRamdiskURL = initrdURL
        }
        bootLoader.commandLine = commandLine
        vzConfig.bootLoader = bootLoader

        // CPU & memory
        vzConfig.cpuCount = cpuCount
        vzConfig.memorySize = UInt64(memoryGB) * 1024 * 1024 * 1024

        // Networking
        if enableNetwork {
            let netDev = VZVirtioNetworkDeviceConfiguration()
            netDev.attachment = VZNATNetworkDeviceAttachment()
            vzConfig.networkDevices = [netDev]
        }

        // Storage devices (VirtIO block + USB mass storage)
        var storageDevices: [VZStorageDeviceConfiguration] = []
        for disk in diskPaths {
            let effectivePath: String
            if noPersist && !disk.readOnly {
                effectivePath = try cloneDiskImage(path: disk.url.path, cleanupPaths: &cleanupPaths)
            } else {
                effectivePath = disk.url.path
            }
            storageDevices.append(try makeStorageDevice(path: effectivePath, readOnly: disk.readOnly))
        }
        try appendUSBStorageDevices(usbDisks: usbDisks, to: &storageDevices)
        vzConfig.storageDevices = storageDevices

        // Directory shares
        var sharedDirs: [String: VZVirtioFileSystemDeviceConfiguration] = [:]
        for share in shares {
            sharedDirs[share.tag] = try makeShareDevice(share: share)
        }

        // Audio
        if enableAudio {
            vzConfig.audioDevices = [makeSoundDevice()]
        }

        // Rosetta
        if enableRosetta {
            sharedDirs["rosetta"] = try makeRosettaShareDevice()
        }

        vzConfig.directorySharingDevices = Array(sharedDirs.values)

        try vzConfig.validate()

        return VMStartContext(configuration: vzConfig, cleanupPaths: cleanupPaths, hasGraphicsDevice: false)
    }

    // MARK: - EFI boot entry point

    /// Build an EFI boot configuration with graphics display, keyboard, and pointing device.
    @available(macOS 13.0, *)
    public static func buildEFIConfiguration(
        efiVariableStoreURL: URL,
        cpuCount: Int = 2,
        memoryGB: Int = 2,
        enableNetwork: Bool = true,
        enableAudio: Bool = false,
        enableRosetta: Bool = false,
        diskPaths: [(url: URL, readOnly: Bool)] = [],
        shares: [ShareConfig] = [],
        usbDisks: [USBDiskConfig] = [],
        noPersist: Bool = false
    ) throws -> VMStartContext {
        let vzConfig = VZVirtualMachineConfiguration()
        var cleanupPaths: [String] = []

        // EFI boot loader with variable store
        let efiBootLoader = VZEFIBootLoader()
        if FileManager.default.fileExists(atPath: efiVariableStoreURL.path) {
            efiBootLoader.variableStore = VZEFIVariableStore(url: efiVariableStoreURL)
        } else {
            efiBootLoader.variableStore = try VZEFIVariableStore(
                creatingVariableStoreAt: efiVariableStoreURL)
        }
        vzConfig.bootLoader = efiBootLoader

        // CPU & memory
        vzConfig.cpuCount = cpuCount
        vzConfig.memorySize = UInt64(memoryGB) * 1024 * 1024 * 1024

        // Graphics display + input devices
        var hasGraphics = false
        if #available(macOS 14.0, *) {
            let graphics = VZVirtioGraphicsDeviceConfiguration()
            graphics.scanouts = [
                VZVirtioGraphicsScanoutConfiguration(widthInPixels: 1920, heightInPixels: 1080)
            ]
            vzConfig.graphicsDevices = [graphics]
            vzConfig.keyboards = [VZUSBKeyboardConfiguration()]
            vzConfig.pointingDevices = [VZUSBScreenCoordinatePointingDeviceConfiguration()]
            hasGraphics = true
        }

        // Networking
        if enableNetwork {
            let netDev = VZVirtioNetworkDeviceConfiguration()
            netDev.attachment = VZNATNetworkDeviceAttachment()
            vzConfig.networkDevices = [netDev]
        }

        // Storage devices (VirtIO block + USB mass storage)
        var storageDevices: [VZStorageDeviceConfiguration] = []
        for disk in diskPaths {
            let effectivePath: String
            if noPersist && !disk.readOnly {
                effectivePath = try cloneDiskImage(path: disk.url.path, cleanupPaths: &cleanupPaths)
            } else {
                effectivePath = disk.url.path
            }
            storageDevices.append(try makeStorageDevice(path: effectivePath, readOnly: disk.readOnly))
        }
        try appendUSBStorageDevices(usbDisks: usbDisks, to: &storageDevices)
        vzConfig.storageDevices = storageDevices

        // Directory shares
        var sharedDirs: [String: VZVirtioFileSystemDeviceConfiguration] = [:]
        for share in shares {
            sharedDirs[share.tag] = try makeShareDevice(share: share)
        }

        // Audio
        if enableAudio {
            vzConfig.audioDevices = [makeSoundDevice()]
        }

        // Rosetta
        if enableRosetta {
            sharedDirs["rosetta"] = try makeRosettaShareDevice()
        }

        vzConfig.directorySharingDevices = Array(sharedDirs.values)

        try vzConfig.validate()

        return VMStartContext(configuration: vzConfig, cleanupPaths: cleanupPaths, hasGraphicsDevice: hasGraphics)
    }

    // MARK: - Device helpers

    /// Creates a copy-on-write clone of a disk image and tracks the clone path for cleanup.
    public static func cloneDiskImage(path: String, cleanupPaths: inout [String]) throws -> String {
        let url = URL(fileURLWithPath: path)
        let dir = url.deletingLastPathComponent()
        let cloneName = ".\(url.lastPathComponent).toyvm-\(UUID().uuidString)"
        let cloneURL = dir.appendingPathComponent(cloneName)
        guard clonefile(url.path, cloneURL.path, 0) == 0 else {
            throw ToyVMError("Failed to clone '\(url.lastPathComponent)': \(String(cString: strerror(errno)))")
        }
        cleanupPaths.append(cloneURL.path)
        return cloneURL.path
    }

    public static func makeStorageDevice(path: String, readOnly: Bool) throws -> VZVirtioBlockDeviceConfiguration {
        let attachment = try VZDiskImageStorageDeviceAttachment(url: URL(fileURLWithPath: path), readOnly: readOnly)
        return VZVirtioBlockDeviceConfiguration(attachment: attachment)
    }

    public static func makeShareDevice(share: ShareConfig) throws -> VZVirtioFileSystemDeviceConfiguration {
        try VZVirtioFileSystemDeviceConfiguration.validateTag(share.tag)
        let cfg = VZVirtioFileSystemDeviceConfiguration(tag: share.tag)
        cfg.share = VZSingleDirectoryShare(
            directory: VZSharedDirectory(url: URL(fileURLWithPath: share.path), readOnly: share.readOnly)
        )
        return cfg
    }

    /// Parses a `[tag:]path` string and creates a share device configuration.
    public static func makeShareDevice(arg: String, readOnly: Bool) throws -> VZVirtioFileSystemDeviceConfiguration {
        let (tag, path) = parseShareArg(arg)
        let share = ShareConfig(tag: tag, path: path, readOnly: readOnly)
        return try makeShareDevice(share: share)
    }

    public static func makeSoundDevice() -> VZVirtioSoundDeviceConfiguration {
        let cfg = VZVirtioSoundDeviceConfiguration()
        let inputStream = VZVirtioSoundDeviceInputStreamConfiguration()
        inputStream.source = VZHostAudioInputStreamSource()
        let outputStream = VZVirtioSoundDeviceOutputStreamConfiguration()
        outputStream.sink = VZHostAudioOutputStreamSink()
        cfg.streams = [inputStream, outputStream]
        return cfg
    }

    public static func makeRosettaShareDevice() throws -> VZVirtioFileSystemDeviceConfiguration {
        #if arch(arm64)
        if #available(macOS 13.0, *) {
            let share = try VZLinuxRosettaDirectoryShare()
            let cfg = VZVirtioFileSystemDeviceConfiguration(tag: "rosetta")
            cfg.share = share
            return cfg
        } else {
            throw ToyVMError("Rosetta requires macOS 13.0 or later")
        }
        #else
        throw ToyVMError("Rosetta requires an Apple Silicon processor")
        #endif
    }

    /// Appends USB mass storage devices for the given USB disk configs.
    public static func appendUSBStorageDevices(
        usbDisks: [USBDiskConfig],
        to storageDevices: inout [VZStorageDeviceConfiguration]
    ) throws {
        guard !usbDisks.isEmpty else { return }
        guard #available(macOS 13.0, *) else {
            throw ToyVMError("USB mass storage devices require macOS 13.0 or later")
        }
        for usbDisk in usbDisks {
            let attachment = try VZDiskImageStorageDeviceAttachment(
                url: URL(fileURLWithPath: usbDisk.path), readOnly: usbDisk.readOnly)
            storageDevices.append(VZUSBMassStorageDeviceConfiguration(attachment: attachment))
        }
    }
}
