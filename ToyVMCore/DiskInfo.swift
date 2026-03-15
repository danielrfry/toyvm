//
//  DiskInfo.swift
//  ToyVMCore
//

import Darwin
import Foundation

/// Returns the logical size and on-disk (sparse) size of a disk image.
public func diskSizes(url: URL, format: DiskFormat) -> (logical: UInt64, onDisk: UInt64)? {
    switch format {
    case .raw:  return rawDiskSizes(url: url)
    case .asif: return asifDiskSizes(url: url)
    }
}

/// Formats a byte count as a human-readable size string (e.g. "20G", "1.5G", "512M").
public func formatSize(_ bytes: UInt64) -> String {
    let units: [(String, UInt64)] = [("T", 1024*1024*1024*1024), ("G", 1024*1024*1024), ("M", 1024*1024), ("K", 1024)]
    for (suffix, factor) in units {
        if bytes >= factor {
            let value = Double(bytes) / Double(factor)
            if value.truncatingRemainder(dividingBy: 1) == 0 {
                return "\(Int(value))\(suffix)"
            } else {
                return String(format: "%.1f%@", value, suffix)
            }
        }
    }
    return "\(bytes)B"
}

private func rawDiskSizes(url: URL) -> (logical: UInt64, onDisk: UInt64)? {
    var s = stat()
    guard stat(url.path, &s) == 0 else { return nil }
    let logical = UInt64(s.st_size)
    let onDisk = UInt64(s.st_blocks) * 512
    return (logical, onDisk)
}

private func asifDiskSizes(url: URL) -> (logical: UInt64, onDisk: UInt64)? {
    guard let logical = asifLogicalSize(url: url) else { return nil }
    guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
          let onDisk = attrs[.size] as? UInt64 else { return nil }
    return (logical, onDisk)
}

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
