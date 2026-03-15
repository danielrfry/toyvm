//
//  Info.swift
//  toyvm
//

import ArgumentParser
import Foundation

extension ToyVM {
    struct Info: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Display the configuration of a VM bundle"
        )

        @Argument(help: "Path to the VM bundle")
        var bundle: String

        func run() throws {
            let bundleURL = URL(fileURLWithPath: bundle, isDirectory: true)
            let config = try VMConfig.load(from: bundleURL)

            print("Kernel:      \(config.kernel)")
            if let initrd = config.initrd {
                print("Initrd:      \(initrd)")
            }
            print("CPUs:        \(config.cpus)")
            print("Memory:      \(config.memoryGB) GB")
            print("Network:     \(config.network ? "yes" : "no")")
            print("Audio:       \(config.audio ? "yes" : "no")")
            print("Rosetta:     \(config.rosetta ? "yes" : "no")")
            print("Kernel args: \(config.kernelCommandLine.joined(separator: " "))")

            if config.disks.isEmpty {
                print("Disks:       (none)")
            } else {
                print("Disks:")
                for disk in config.disks {
                    let rwLabel = disk.readOnly ? "ro" : "rw"
                    let fmtLabel = disk.format == .raw ? "raw" : disk.format.rawValue
                    let size = diskSize(bundleURL.appendingPathComponent(disk.file))
                    print("  [\(rwLabel), \(fmtLabel)] \(disk.file)\(size.map { " (\($0))" } ?? "")")
                }
            }

            if config.shares.isEmpty {
                print("Shares:      (none)")
            } else {
                print("Shares:")
                for share in config.shares {
                    let rwLabel = share.readOnly ? "ro" : "rw"
                    print("  [\(rwLabel)] \(share.tag): \(share.path)")
                }
            }
        }

        /// Returns a human-readable size string for the file at the given URL, or nil on error.
        private func diskSize(_ url: URL) -> String? {
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let bytes = attrs[.size] as? UInt64 else { return nil }
            return formatSize(bytes)
        }

        private func formatSize(_ bytes: UInt64) -> String {
            let units: [(String, UInt64)] = [("T", 1024*1024*1024*1024), ("G", 1024*1024*1024), ("M", 1024*1024), ("K", 1024)]
            for (suffix, factor) in units {
                if bytes >= factor && bytes % factor == 0 {
                    return "\(bytes / factor)\(suffix)"
                }
            }
            return "\(bytes) bytes"
        }
    }
}
