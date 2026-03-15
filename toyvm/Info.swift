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
            let bundleURL = try resolveBundlePath(bundle)
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
                    let fmtLabel = disk.format.rawValue
                    let url = bundleURL.appendingPathComponent(disk.file)
                    let sizeDesc = diskSizeDescription(url: url, format: disk.format)
                    print("  [\(rwLabel), \(fmtLabel)] \(disk.file)\(sizeDesc.map { " (\($0))" } ?? "")")
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

        /// Returns a display string like "10G, 481M on disk" for the given disk image.
        private func diskSizeDescription(url: URL, format: DiskFormat) -> String? {
            guard let (logical, onDisk) = diskSizes(url: url, format: format) else { return nil }
            let logicalStr = formatSize(logical)
            let onDiskStr = formatSize(onDisk)
            if logicalStr == onDiskStr {
                return logicalStr
            }
            return "\(logicalStr), \(onDiskStr) on disk"
        }

        /// Returns (logicalBytes, onDiskBytes) for the given disk image.
        private func diskSizes(url: URL, format: DiskFormat) -> (logical: UInt64, onDisk: UInt64)? {
            switch format {
            case .raw:
                return rawDiskSizes(url: url)
            case .asif:
                return asifDiskSizes(url: url)
            }
        }

        /// For raw sparse files: logical = st_size, on-disk = st_blocks × 512.
        private func rawDiskSizes(url: URL) -> (logical: UInt64, onDisk: UInt64)? {
            var s = stat()
            guard stat(url.path, &s) == 0 else { return nil }
            let logical = UInt64(s.st_size)
            let onDisk = UInt64(s.st_blocks) * 512
            return (logical, onDisk)
        }

        /// For ASIF images: logical size from diskutil, on-disk = file size (ASIF is internally sparse).
        private func asifDiskSizes(url: URL) -> (logical: UInt64, onDisk: UInt64)? {
            guard let logical = asifLogicalSize(url: url) else { return nil }
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let onDisk = attrs[.size] as? UInt64 else { return nil }
            return (logical, onDisk)
        }

        /// Runs `diskutil image info --plist` and extracts `Size Info → Total Bytes`.
        private func asifLogicalSize(url: URL) -> UInt64? {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
            process.arguments = ["image", "info", "--plist", url.path]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            guard (try? process.run()) != nil else { return nil }
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                  let sizeInfo = plist["Size Info"] as? [String: Any],
                  let totalBytes = sizeInfo["Total Bytes"] as? UInt64 else { return nil }
            return totalBytes
        }

        private func formatSize(_ bytes: UInt64) -> String {
            let units: [(String, UInt64)] = [("T", 1024*1024*1024*1024), ("G", 1024*1024*1024), ("M", 1024*1024), ("K", 1024)]
            for (suffix, factor) in units {
                if bytes >= factor {
                    let value = Double(bytes) / Double(factor)
                    if value.truncatingRemainder(dividingBy: 1) == 0 {
                        return "\(Int(value))\(suffix)"
                    } else {
                        // Show one decimal place (e.g., 1.5G)
                        return String(format: "%.1f%@", value, suffix)
                    }
                }
            }
            return "\(bytes)B"
        }
    }
}
