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
}

struct ShareConfig: Codable {
    var tag: String
    /// Absolute path to the shared directory on the host.
    var path: String
    var readOnly: Bool
}

extension VMConfig {
    static let configFilename = "config.plist"

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

/// Creates a sparse file of the given size using truncation (no data written to disk).
func createSparseFile(at url: URL, size: UInt64) throws {
    FileManager.default.createFile(atPath: url.path, contents: nil)
    let fh = try FileHandle(forWritingTo: url)
    defer { try? fh.close() }
    try fh.truncate(atOffset: size)
}

/// Parses a `[tag:]path` share argument. If no tag prefix is present, uses "share".
func parseShareArg(_ arg: String) -> (tag: String, path: String) {
    if let colonIdx = arg.firstIndex(of: ":") {
        return (String(arg[arg.startIndex..<colonIdx]), String(arg[arg.index(after: colonIdx)...]))
    }
    return ("share", arg)
}

/// Returns the next available disk filename in the bundle (e.g. "disk3.img").
func nextDiskFilename(existing: [DiskConfig]) -> String {
    let names = Set(existing.map { $0.file })
    var index = 0
    while true {
        let name = "disk\(index).img"
        if !names.contains(name) { return name }
        index += 1
    }
}
