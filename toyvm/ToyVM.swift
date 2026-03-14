//
//  ToyVM.swift
//  toyvm
//

import ArgumentParser
import CoreFoundation
import Darwin
import Virtualization

@main
struct ToyVM: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "toyvm",
        abstract: "Toy Linux VM using Virtualization.framework",
        discussion: """
            Remaining positional arguments are passed to the kernel as the command line. \
            Use -- to separate toyvm options from kernel arguments that begin with -.
            """
    )

    @Option(name: [.customShort("k"), .long], help: "Path to the kernel image to load [required]")
    var kernel: String

    @Option(name: [.customShort("i"), .long], help: "Path to an initrd image to load")
    var initrd: String?

    @Option(name: [.customShort("d"), .long], help: "Add a read/write virtual storage device backed by the specified raw disk image file")
    var disk: [String] = []

    @Option(name: [.customShort("r"), .customLong("disk-ro")], help: "As --disk but adds a read-only storage device")
    var diskRO: [String] = []

    @Option(name: [.customShort("s"), .long], help: "Add a directory share device; accepts [tag:]path (tag defaults to \"share\")")
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

    @Argument(help: "Kernel command line")
    var kernelCommandLine: [String] = ["console=hvc0"]

    mutating func run() throws {
        let config = VZVirtualMachineConfiguration()

        if !noNet {
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

        let bootLoader = VZLinuxBootLoader(kernelURL: URL(fileURLWithPath: kernel))
        if let initrdPath = initrd {
            bootLoader.initialRamdiskURL = URL(fileURLWithPath: initrdPath)
        }
        bootLoader.commandLine = kernelCommandLine.joined(separator: " ")
        config.bootLoader = bootLoader

        config.memorySize = UInt64(memory) * 1024 * 1024 * 1024
        config.cpuCount = cpus

        var storageDevices: [VZStorageDeviceConfiguration] = []
        for path in disk {
            storageDevices.append(try makeStorageDevice(path: path, readOnly: false))
        }
        for path in diskRO {
            storageDevices.append(try makeStorageDevice(path: path, readOnly: true))
        }
        config.storageDevices = storageDevices

        var sharedDirs: [String: VZVirtioFileSystemDeviceConfiguration] = [:]
        for arg in share {
            let cfg = try makeShareDevice(arg: arg, readOnly: false)
            sharedDirs[cfg.tag] = cfg
        }
        for arg in shareRO {
            let cfg = try makeShareDevice(arg: arg, readOnly: true)
            sharedDirs[cfg.tag] = cfg
        }
        if enableRosetta {
            let cfg = try makeRosettaShareDevice()
            sharedDirs[cfg.tag] = cfg
        }
        config.directorySharingDevices = Array(sharedDirs.values)

        if audio {
            config.audioDevices = [makeSoundDevice()]
        }

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

struct ToyVMError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}
