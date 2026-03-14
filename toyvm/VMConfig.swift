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
