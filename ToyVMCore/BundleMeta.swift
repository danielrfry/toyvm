//
//  BundleMeta.swift
//  ToyVMCore
//

import Darwin
import Foundation

/// Bundle-level metadata stored at `bundle.plist` in the bundle root.
/// Tracks the active branch and the full branch tree.
public struct BundleMeta: Codable {
    public var activeBranch: String
    public var branches: [String: BranchInfo]

    public init(rootBranch: String = "main") {
        activeBranch = rootBranch
        branches = [rootBranch: BranchInfo(parent: nil)]
    }
}

/// Per-branch metadata. The root branch has `parent == nil`.
public struct BranchInfo: Codable {
    public var parent: String?
    public var readOnly: Bool = false

    public init(parent: String?, readOnly: Bool = false) {
        self.parent = parent
        self.readOnly = readOnly
    }
}

extension BundleMeta {
    public static let filename = "bundle.plist"

    public static func load(from bundleURL: URL) throws -> BundleMeta {
        let data = try Data(contentsOf: bundleURL.appendingPathComponent(filename))
        return try PropertyListDecoder().decode(BundleMeta.self, from: data)
    }

    public func save(to bundleURL: URL) throws {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        let data = try encoder.encode(self)
        try data.write(to: bundleURL.appendingPathComponent(BundleMeta.filename))
    }

    /// Returns the names of all direct children of the given branch, sorted.
    public func children(of branch: String) -> [String] {
        return branches.compactMap { name, info in info.parent == branch ? name : nil }.sorted()
    }

    /// Returns all descendant branch names (depth-first, sorted at each level).
    public func descendants(of branch: String) -> [String] {
        var result: [String] = []
        for child in children(of: branch) {
            result.append(child)
            result.append(contentsOf: descendants(of: child))
        }
        return result
    }

    /// The root branch name (the one with no parent).
    public var rootBranch: String? {
        return branches.first(where: { $0.value.parent == nil })?.key
    }
}

/// Clones a directory tree using the APFS copy-on-write `clonefileat` syscall.
/// Falls back to a regular recursive copy on non-APFS volumes.
/// The destination path must not already exist.
public func cloneBranchDirectory(from src: URL, to dst: URL) throws {
    let result = src.path.withCString { srcPath in
        dst.path.withCString { dstPath in
            Darwin.clonefileat(AT_FDCWD, srcPath, AT_FDCWD, dstPath, 0)
        }
    }
    if result == 0 { return }
    // Fall back to a regular recursive copy (e.g. on non-APFS volumes)
    try FileManager.default.copyItem(at: src, to: dst)
}
