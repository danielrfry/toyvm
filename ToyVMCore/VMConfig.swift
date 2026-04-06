//
//  VMConfig.swift
//  ToyVMCore
//

import Foundation

/// Boot mode for the virtual machine.
public enum BootMode: String, Codable, CaseIterable, Sendable {
    /// Direct kernel boot via VZLinuxBootLoader with serial console.
    case linux
    /// EFI boot via VZEFIBootLoader with graphical display.
    case efi
    /// macOS guest boot via VZMacOSBootLoader (Apple Silicon only).
    case macOS

    public var label: String {
        switch self {
        case .linux: return "Linux"
        case .efi: return "Linux (GUI)"
        case .macOS: return "macOS"
        }
    }
}

/// Configuration for a USB mass storage device (e.g. an ISO installer image).
public struct USBDiskConfig: Codable, Equatable, Sendable {
    /// Absolute path to the disk or ISO image on the host.
    public var path: String
    public var readOnly: Bool

    public init(path: String, readOnly: Bool = true) {
        self.path = path
        self.readOnly = readOnly
    }
}

public struct VMConfig: Codable {
    public var cpus: Int = 2
    public var memoryGB: Int = 2
    public var audio: Bool = false
    public var network: Bool = true
    public var rosetta: Bool = false
    public var bootMode: BootMode = .linux
    public var kernel: String?
    public var initrd: String?
    public var kernelCommandLine: [String] = ["console=hvc0"]
    public var disks: [DiskConfig] = []
    public var shares: [ShareConfig] = []
    public var usbDisks: [USBDiskConfig] = []

    public init(
        cpus: Int = 2,
        memoryGB: Int = 2,
        audio: Bool = false,
        network: Bool = true,
        rosetta: Bool = false,
        bootMode: BootMode = .linux,
        kernel: String? = nil,
        initrd: String? = nil,
        kernelCommandLine: [String] = ["console=hvc0"],
        disks: [DiskConfig] = [],
        shares: [ShareConfig] = [],
        usbDisks: [USBDiskConfig] = []
    ) {
        self.cpus = cpus
        self.memoryGB = memoryGB
        self.audio = audio
        self.network = network
        self.rosetta = rosetta
        self.bootMode = bootMode
        self.kernel = kernel
        self.initrd = initrd
        self.kernelCommandLine = kernelCommandLine
        self.disks = disks
        self.shares = shares
        self.usbDisks = usbDisks
    }

    /// Custom decoder for backward compatibility: existing bundles without
    /// bootMode or usbDisks decode with sensible defaults.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        cpus = try c.decodeIfPresent(Int.self, forKey: .cpus) ?? 2
        memoryGB = try c.decodeIfPresent(Int.self, forKey: .memoryGB) ?? 2
        audio = try c.decodeIfPresent(Bool.self, forKey: .audio) ?? false
        network = try c.decodeIfPresent(Bool.self, forKey: .network) ?? true
        rosetta = try c.decodeIfPresent(Bool.self, forKey: .rosetta) ?? false
        bootMode = try c.decodeIfPresent(BootMode.self, forKey: .bootMode) ?? .linux
        kernel = try c.decodeIfPresent(String.self, forKey: .kernel)
        initrd = try c.decodeIfPresent(String.self, forKey: .initrd)
        kernelCommandLine = try c.decodeIfPresent([String].self, forKey: .kernelCommandLine) ?? ["console=hvc0"]
        disks = try c.decodeIfPresent([DiskConfig].self, forKey: .disks) ?? []
        shares = try c.decodeIfPresent([ShareConfig].self, forKey: .shares) ?? []
        usbDisks = try c.decodeIfPresent([USBDiskConfig].self, forKey: .usbDisks) ?? []
    }
}

public struct DiskConfig: Codable {
    /// Path to the disk image, relative to the bundle directory.
    public var file: String
    public var readOnly: Bool
    public var format: DiskFormat

    public init(file: String, readOnly: Bool, format: DiskFormat = .raw) {
        self.file = file
        self.readOnly = readOnly
        self.format = format
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        file = try c.decode(String.self, forKey: .file)
        readOnly = try c.decode(Bool.self, forKey: .readOnly)
        format = try c.decodeIfPresent(DiskFormat.self, forKey: .format) ?? .raw
    }
}

public enum DiskFormat: String, Codable {
    case raw
    case asif

    public var fileExtension: String {
        switch self {
        case .raw:  return "img"
        case .asif: return "asif"
        }
    }
}

public struct ShareConfig: Codable {
    public var tag: String
    /// Absolute path to the shared directory on the host.
    public var path: String
    public var readOnly: Bool

    public init(tag: String, path: String, readOnly: Bool) {
        self.tag = tag
        self.path = path
        self.readOnly = readOnly
    }
}

extension VMConfig {
    public static let configFilename = "config.plist"
    public static let kernelDir = "kernel"
    public static let initrdDir = "initrd"
    public static let disksDir = "disks"
    public static let branchesDir = "branches"

    // macOS guest artifact filenames
    public static let hardwareModelFile = "hardware-model.bin"
    public static let machineIdentifierFile = "machine-identifier.bin"
    public static let auxiliaryStorageFile = "auxiliary-storage.bin"

    public static func load(from branchURL: URL) throws -> VMConfig {
        let data = try Data(contentsOf: branchURL.appendingPathComponent(configFilename))
        return try PropertyListDecoder().decode(VMConfig.self, from: data)
    }

    public func save(to branchURL: URL) throws {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        let data = try encoder.encode(self)
        try data.write(to: branchURL.appendingPathComponent(VMConfig.configFilename))
    }

    /// Returns the URL of the branch directory for the given branch name inside a bundle.
    public static func branchURL(in bundleURL: URL, branch: String) -> URL {
        return bundleURL.appendingPathComponent(branchesDir).appendingPathComponent(branch)
    }

    /// Returns the full URL to the kernel image in this branch, or nil if no kernel is configured.
    public func kernelURL(in branchURL: URL) -> URL? {
        guard let kernel else { return nil }
        return branchURL.appendingPathComponent(VMConfig.kernelDir).appendingPathComponent(kernel)
    }

    /// Returns the full URL to the EFI variable store in this branch.
    public func efiVariableStoreURL(in branchURL: URL) -> URL {
        return branchURL.appendingPathComponent("efi-vars.fd")
    }

    /// Returns the URL of the hardware model data file in this branch.
    public func hardwareModelURL(in branchURL: URL) -> URL {
        return branchURL.appendingPathComponent(VMConfig.hardwareModelFile)
    }

    /// Returns the URL of the machine identifier data file in this branch.
    public func machineIdentifierURL(in branchURL: URL) -> URL {
        return branchURL.appendingPathComponent(VMConfig.machineIdentifierFile)
    }

    /// Returns the URL of the auxiliary storage file in this branch.
    public func auxiliaryStorageURL(in branchURL: URL) -> URL {
        return branchURL.appendingPathComponent(VMConfig.auxiliaryStorageFile)
    }

    /// Returns the full URL to the initrd image in this branch (if one is configured).
    public func initrdURL(in branchURL: URL) -> URL? {
        guard let initrdFile = initrd else { return nil }
        return branchURL.appendingPathComponent(VMConfig.initrdDir).appendingPathComponent(initrdFile)
    }

    /// Returns the full URL to a disk image in this branch.
    public func diskURL(in branchURL: URL, disk: DiskConfig) -> URL {
        return branchURL.appendingPathComponent(VMConfig.disksDir).appendingPathComponent(disk.file)
    }
}

/// Parses a human-readable size string (e.g. "20G", "512M", "1T") into bytes.
public func parseSize(_ s: String) throws -> UInt64 {
    let suffixes: [(String, UInt64)] = [
        ("T", 1024 * 1024 * 1024 * 1024),
        ("G", 1024 * 1024 * 1024),
        ("M", 1024 * 1024),
        ("K", 1024),
    ]
    let upper = s.uppercased()
    for (suffix, multiplier) in suffixes {
        if upper.hasSuffix(suffix) {
            let numStr = String(s.dropLast())
            if let n = UInt64(numStr), n > 0 {
                return n * multiplier
            }
            throw ToyVMError("Invalid size '\(s)': expected a positive integer followed by K, M, G, or T")
        }
    }
    if let n = UInt64(s), n > 0 { return n }
    throw ToyVMError("Invalid size '\(s)': expected a positive integer optionally followed by K, M, G, or T")
}

/// Parses a disk specification of the form `[format:]size` (e.g. "20G", "asif:20G", "raw:512M").
public func parseDiskSpec(_ s: String) throws -> (format: DiskFormat, size: UInt64) {
    if let colonIdx = s.firstIndex(of: ":") {
        let formatStr = String(s[s.startIndex..<colonIdx])
        let sizeStr = String(s[s.index(after: colonIdx)...])
        guard let format = DiskFormat(rawValue: formatStr.lowercased()) else {
            throw ToyVMError("Unknown disk format '\(formatStr)': expected 'raw' or 'asif'")
        }
        return (format, try parseSize(sizeStr))
    }
    return (.raw, try parseSize(s))
}

/// Creates a sparse raw disk image file of the given size using truncation.
public func createRawDisk(at url: URL, size: UInt64) throws {
    FileManager.default.createFile(atPath: url.path, contents: nil)
    let fh = try FileHandle(forWritingTo: url)
    defer { try? fh.close() }
    try fh.truncate(atOffset: size)
}

/// Creates an ASIF-format disk image of the given size using diskutil.
public func createASIFDisk(at url: URL, size: UInt64) throws {
    // diskutil appends .asif automatically, so strip the extension from the target path
    let basePath = url.deletingPathExtension().path
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
    // Always specify the size in bytes to diskutil to avoid unit interpretation
    // differences between binary (1024-based) and decimal (1000-based) prefixes.
    process.arguments = [
        "image", "create", "blank",
        "--fs", "none",
        "--format", "ASIF",
        "--size", String(size),
        basePath,
    ]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw ToyVMError("diskutil failed to create ASIF disk image at \(url.path)")
    }
}

/// Creates a disk image file in the given format.
public func createDisk(at url: URL, size: UInt64, format: DiskFormat) throws {
    switch format {
    case .raw:  try createRawDisk(at: url, size: size)
    case .asif: try createASIFDisk(at: url, size: size)
    }
}

/// Returns an error description if the given string is not a valid ExFAT volume label, or nil if valid.
/// ExFAT volume labels must be 1–11 characters and must not contain control characters (U+0000–U+001F)
/// or any of: `"` `*` `/` `:` `<` `>` `?` `\` `|`
public func exFATVolumeLabelError(_ label: String) -> String? {
    if label.isEmpty { return "Volume label must not be empty." }
    if label.count > 11 { return "Volume label must be 11 characters or fewer." }
    let invalidScalars: Set<Unicode.Scalar> = [
        "\u{0022}", "\u{002A}", "\u{002F}", "\u{003A}",
        "\u{003C}", "\u{003E}", "\u{003F}", "\u{005C}", "\u{007C}",
    ]
    for scalar in label.unicodeScalars {
        if scalar.value <= 0x001F {
            return "Volume label must not contain control characters."
        }
        if invalidScalars.contains(scalar) {
            return #"Volume label must not contain " * / : < > ? \ |"#
        }
    }
    return nil
}

/// Initialises a disk image with a GPT partition scheme containing a single ExFAT partition.
/// Works by attaching the image with `diskutil image attach -n` (supports raw and ASIF formats),
/// partitioning with diskutil, then ejecting.
public func initialiseDisk(at url: URL, volumeLabel: String = "Data") throws {
    // Validate the volume label before attempting to mount the image
    if let labelError = exFATVolumeLabelError(volumeLabel) {
        throw ToyVMError(labelError)
    }

    // Attach the disk image without mounting its filesystems.
    // diskutil image attach supports both raw and ASIF formats; hdiutil does not support ASIF.
    let attach = Process()
    attach.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
    attach.arguments = ["image", "attach", "-n", url.path]
    let pipe = Pipe()
    attach.standardOutput = pipe
    attach.standardError = FileHandle.nullDevice
    try attach.run()
    attach.waitUntilExit()
    guard attach.terminationStatus == 0 else {
        throw ToyVMError("diskutil image attach failed for disk image")
    }

    let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
    guard let output = String(data: outputData, encoding: .utf8),
          let deviceNode = output.components(separatedBy: .whitespaces).first(where: { $0.hasPrefix("/dev/disk") }) else {
        throw ToyVMError("Could not determine device node from diskutil output")
    }

    // Partition with GPT + single ExFAT partition using the provided label
    let diskutil = Process()
    diskutil.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
    diskutil.arguments = ["partitionDisk", deviceNode, "GPT", "ExFAT", volumeLabel, "0b"]
    diskutil.standardOutput = FileHandle.nullDevice
    diskutil.standardError = FileHandle.nullDevice
    try diskutil.run()
    diskutil.waitUntilExit()

    let partitionSuccess = diskutil.terminationStatus == 0

    // Always eject, even if partitioning failed
    let eject = Process()
    eject.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
    eject.arguments = ["eject", deviceNode]
    eject.standardOutput = FileHandle.nullDevice
    eject.standardError = FileHandle.nullDevice
    try eject.run()
    eject.waitUntilExit()

    if !partitionSuccess {
        throw ToyVMError("diskutil failed to partition disk image")
    }
}

/// Parses a `[tag:]path` share argument. If no tag prefix is present, uses "share".
public func parseShareArg(_ arg: String) -> (tag: String, path: String) {
    if let colonIdx = arg.firstIndex(of: ":") {
        return (String(arg[arg.startIndex..<colonIdx]), String(arg[arg.index(after: colonIdx)...]))
    }
    return ("share", arg)
}

/// Returns the next available disk filename in the bundle for the given format (e.g. "disk3.asif").
public func nextDiskFilename(existing: [DiskConfig], format: DiskFormat) -> String {
    let basenames = Set(existing.map { URL(fileURLWithPath: $0.file).deletingPathExtension().lastPathComponent })
    var index = 0
    while true {
        let base = "disk\(index)"
        if !basenames.contains(base) { return "\(base).\(format.fileExtension)" }
        index += 1
    }
}

/// Resolve a user-supplied bundle string to a filesystem path. If the input is a bare name
/// (no path separators and not ending with .bundle), it is interpreted as a VM name and
/// resolved to ~/.toyvm/<name>.bundle. If createParentIfNeeded is true, ~/.toyvm will be
/// created when required (used by 'create').
public func resolveBundlePath(_ input: String, createParentIfNeeded: Bool = false) throws -> URL {
    let fm = FileManager.default
    // Treat as explicit path if it contains a path separator or already ends with .bundle
    if input.contains("/") || input.hasSuffix(".bundle") {
        return URL(fileURLWithPath: input, isDirectory: true)
    }
    // Otherwise treat as VM name under ~/.toyvm
    let home = fm.homeDirectoryForCurrentUser
    let dir = home.appendingPathComponent(".toyvm", isDirectory: true)
    if createParentIfNeeded && !fm.fileExists(atPath: dir.path) {
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    return dir.appendingPathComponent(input + ".bundle", isDirectory: true)
}
