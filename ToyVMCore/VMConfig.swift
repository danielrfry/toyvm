//
//  VMConfig.swift
//  ToyVMCore
//

import Foundation

public struct VMConfig: Codable {
    public var cpus: Int = 2
    public var memoryGB: Int = 2
    public var audio: Bool = false
    public var network: Bool = true
    public var rosetta: Bool = false
    public var kernel: String
    public var initrd: String?
    public var kernelCommandLine: [String] = ["console=hvc0"]
    public var disks: [DiskConfig] = []
    public var shares: [ShareConfig] = []

    public init(
        cpus: Int = 2,
        memoryGB: Int = 2,
        audio: Bool = false,
        network: Bool = true,
        rosetta: Bool = false,
        kernel: String,
        initrd: String? = nil,
        kernelCommandLine: [String] = ["console=hvc0"],
        disks: [DiskConfig] = [],
        shares: [ShareConfig] = []
    ) {
        self.cpus = cpus
        self.memoryGB = memoryGB
        self.audio = audio
        self.network = network
        self.rosetta = rosetta
        self.kernel = kernel
        self.initrd = initrd
        self.kernelCommandLine = kernelCommandLine
        self.disks = disks
        self.shares = shares
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

    /// Returns the full URL to the kernel image in this branch.
    public func kernelURL(in branchURL: URL) -> URL {
        return branchURL.appendingPathComponent(VMConfig.kernelDir).appendingPathComponent(kernel)
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
