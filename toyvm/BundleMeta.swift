//
//  BundleMeta.swift
//  toyvm
//

import Darwin
import Foundation

/// Bundle-level metadata stored at `bundle.plist` in the bundle root.
/// Tracks the active branch and the flat collection of branches.
struct BundleMeta: Codable {
    var activeBranch: String
    var branches: [String: BranchInfo]

    init(initialBranch: String = "main") {
        activeBranch = initialBranch
        branches = [initialBranch: BranchInfo()]
    }
}

/// Per-branch metadata.
///
/// Older bundle metadata also contains a `parent` key. Codable deliberately
/// ignores that unknown key so existing branch trees are flattened on load.
struct BranchInfo: Codable {
    var readOnly: Bool = false

    private enum CodingKeys: String, CodingKey {
        case readOnly
    }

    init(readOnly: Bool = false) {
        self.readOnly = readOnly
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        readOnly = try container.decodeIfPresent(Bool.self, forKey: .readOnly) ?? false
    }
}

extension BundleMeta {
    static let filename = "bundle.plist"

    static func load(from bundleURL: URL) throws -> BundleMeta {
        let data = try Data(contentsOf: bundleURL.appendingPathComponent(filename))
        let meta = try PropertyListDecoder().decode(BundleMeta.self, from: data)
        guard meta.branches[meta.activeBranch] != nil else {
            throw ToyVMError(
                "Bundle metadata refers to missing active branch '\(meta.activeBranch)'"
            )
        }
        for name in meta.branches.keys {
            try validateBranchName(name)
        }
        return meta
    }

    func save(to bundleURL: URL) throws {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        let data = try encoder.encode(self)
        try data.write(
            to: bundleURL.appendingPathComponent(BundleMeta.filename),
            options: .atomic
        )
    }
}

/// Ensures a branch name cannot address anything outside the bundle's branches
/// directory. Names remain otherwise unrestricted so existing user-facing names
/// continue to work.
func validateBranchName(_ name: String) throws {
    guard !name.isEmpty,
          name != ".",
          name != "..",
          !name.contains("/"),
          !name.contains("\0")
    else {
        throw ToyVMError(
            "Invalid branch name '\(name)': expected a single non-empty path component"
        )
    }
}

/// Clones a directory tree using the APFS copy-on-write `clonefileat` syscall.
/// Falls back to a regular recursive copy on non-APFS volumes.
/// The destination path must not already exist.
func cloneBranchDirectory(from src: URL, to dst: URL) throws {
    let result = src.path.withCString { srcPath in
        dst.path.withCString { dstPath in
            Darwin.clonefileat(AT_FDCWD, srcPath, AT_FDCWD, dstPath, 0)
        }
    }
    if result == 0 { return }
    // Fall back to a regular recursive copy (e.g. on non-APFS volumes)
    try FileManager.default.copyItem(at: src, to: dst)
}
