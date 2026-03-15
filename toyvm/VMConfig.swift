//
//  VMConfig.swift
//  toyvm
//

import Foundation

struct VMConfig: Codable {
    var cpus: Int = 2
    var memoryGB: Int = 2
    var audio: Bool = false
    var network: Bool = true
    var rosetta: Bool = false
    var kernel: String
    var initrd: String?
    var kernelCommandLine: [String] = ["console=hvc0"]
    var disks: [DiskConfig] = []
    var shares: [ShareConfig] = []
}

struct DiskConfig: Codable {
    /// Path to the disk image, relative to the bundle directory.
    var file: String
    var readOnly: Bool
    var format: DiskFormat

    init(file: String, readOnly: Bool, format: DiskFormat = .raw) {
        self.file = file
        self.readOnly = readOnly
        self.format = format
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        file = try c.decode(String.self, forKey: .file)
        readOnly = try c.decode(Bool.self, forKey: .readOnly)
        format = try c.decodeIfPresent(DiskFormat.self, forKey: .format) ?? .raw
    }
}

enum DiskFormat: String, Codable {
    case raw
    case asif

    var fileExtension: String {
        switch self {
        case .raw:  return "img"
        case .asif: return "asif"
        }
    }
}

struct ShareConfig: Codable {
    var tag: String
    /// Absolute path to the shared directory on the host.
    var path: String
    var readOnly: Bool
}

extension VMConfig {
    static let configFilename = "config.plist"
    static let kernelDir = "kernel"
    static let initrdDir = "initrd"
    static let disksDir = "disks"

    static func load(from bundleURL: URL) throws -> VMConfig {
        let data = try Data(contentsOf: bundleURL.appendingPathComponent(configFilename))
        return try PropertyListDecoder().decode(VMConfig.self, from: data)
    }

    func save(to bundleURL: URL) throws {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        let data = try encoder.encode(self)
        try data.write(to: bundleURL.appendingPathComponent(VMConfig.configFilename))
    }

    /// Returns the full URL to the kernel image in the bundle.
    func kernelURL(in bundleURL: URL) -> URL {
        return bundleURL.appendingPathComponent(VMConfig.kernelDir).appendingPathComponent(kernel)
    }

    /// Returns the full URL to the initrd image in the bundle (if it exists).
    func initrdURL(in bundleURL: URL) -> URL? {
        guard let initrdFile = initrd else { return nil }
        return bundleURL.appendingPathComponent(VMConfig.initrdDir).appendingPathComponent(initrdFile)
    }

    /// Returns the full URL to a disk image in the bundle.
    func diskURL(in bundleURL: URL, disk: DiskConfig) -> URL {
        return bundleURL.appendingPathComponent(VMConfig.disksDir).appendingPathComponent(disk.file)
    }
}

/// Parses a human-readable size string (e.g. "20G", "512M", "1T") into bytes.
func parseSize(_ s: String) throws -> UInt64 {
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
func parseDiskSpec(_ s: String) throws -> (format: DiskFormat, size: UInt64) {
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
func createRawDisk(at url: URL, size: UInt64) throws {
    FileManager.default.createFile(atPath: url.path, contents: nil)
    let fh = try FileHandle(forWritingTo: url)
    defer { try? fh.close() }
    try fh.truncate(atOffset: size)
}

/// Creates an ASIF-format disk image of the given size using diskutil.
func createASIFDisk(at url: URL, size: UInt64) throws {
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
func createDisk(at url: URL, size: UInt64, format: DiskFormat) throws {
    switch format {
    case .raw:  try createRawDisk(at: url, size: size)
    case .asif: try createASIFDisk(at: url, size: size)
    }
}

/// Formats a byte count as a size string suitable for diskutil (e.g. "20g", "512m").
private func diskutilSizeString(_ bytes: UInt64) -> String {
    let units: [(UInt64, String)] = [
        (1024 * 1024 * 1024 * 1024, "t"),
        (1024 * 1024 * 1024,         "g"),
        (1024 * 1024,                "m"),
        (1024,                       "k"),
    ]
    for (factor, suffix) in units {
        if bytes % factor == 0 { return "\(bytes / factor)\(suffix)" }
    }
    return "\(bytes)"
}

/// Parses a `[tag:]path` share argument. If no tag prefix is present, uses "share".
func parseShareArg(_ arg: String) -> (tag: String, path: String) {
    if let colonIdx = arg.firstIndex(of: ":") {
        return (String(arg[arg.startIndex..<colonIdx]), String(arg[arg.index(after: colonIdx)...]))
    }
    return ("share", arg)
}

/// Returns the next available disk filename in the bundle for the given format (e.g. "disk3.asif").
func nextDiskFilename(existing: [DiskConfig], format: DiskFormat) -> String {
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
func resolveBundlePath(_ input: String, createParentIfNeeded: Bool = false) throws -> URL {
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
