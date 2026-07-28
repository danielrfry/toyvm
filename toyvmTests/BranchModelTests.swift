import Foundation
import XCTest
@testable import toyvm

final class BranchModelTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDownWithError() throws {
        for url in temporaryDirectories {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryDirectories.removeAll()
    }

    func testInitialMetadataAndFlatLabels() throws {
        var meta = BundleMeta()
        meta.branches["zeta"] = BranchInfo(readOnly: true)
        meta.branches["alpha"] = BranchInfo()
        meta.activeBranch = "alpha"

        XCTAssertEqual(
            branchLabels(for: meta),
            ["alpha *", "main", "zeta [ro]"]
        )
    }

    func testLegacyTreeLoadsFlatAndSavesWithoutParents() throws {
        let bundleURL = try makeEmptyBundle()
        let legacy: [String: Any] = [
            "activeBranch": "work",
            "branches": [
                "main": ["readOnly": true],
                "checkpoint": ["parent": "main"],
                "work": ["parent": "checkpoint", "readOnly": false],
            ],
        ]
        let data = try PropertyListSerialization.data(
            fromPropertyList: legacy,
            format: .xml,
            options: 0
        )
        try data.write(to: bundleURL.appendingPathComponent(BundleMeta.filename))

        let meta = try BundleMeta.load(from: bundleURL)
        XCTAssertEqual(meta.activeBranch, "work")
        XCTAssertEqual(Set(meta.branches.keys), ["main", "checkpoint", "work"])
        XCTAssertTrue(meta.branches["main"]?.readOnly == true)
        XCTAssertFalse(meta.branches["checkpoint"]?.readOnly == true)

        try meta.save(to: bundleURL)
        let savedData = try Data(
            contentsOf: bundleURL.appendingPathComponent(BundleMeta.filename)
        )
        let saved = try XCTUnwrap(
            PropertyListSerialization.propertyList(
                from: savedData,
                format: nil
            ) as? [String: Any]
        )
        let branches = try XCTUnwrap(saved["branches"] as? [String: Any])
        for value in branches.values {
            let info = try XCTUnwrap(value as? [String: Any])
            XCTAssertNil(info["parent"])
        }
    }

    func testCreateFromReadOnlyBranchSelectsWritableClone() throws {
        let bundleURL = try makeBundle(
            active: "main",
            branches: ["main": BranchInfo(readOnly: true)]
        )
        let markerURL = VMConfig.branchURL(in: bundleURL, branch: "main")
            .appendingPathComponent("marker")
        try Data("main state".utf8).write(to: markerURL)

        let command = try ToyVM.BranchCommand.CreateSubcommand.parse([
            bundleURL.path,
            "work",
        ])
        try command.run()

        let meta = try BundleMeta.load(from: bundleURL)
        XCTAssertEqual(meta.activeBranch, "work")
        XCTAssertTrue(meta.branches["main"]?.readOnly == true)
        XCTAssertFalse(meta.branches["work"]?.readOnly == true)
        let clonedMarker = VMConfig.branchURL(in: bundleURL, branch: "work")
            .appendingPathComponent("marker")
        XCTAssertEqual(
            try String(contentsOf: clonedMarker, encoding: .utf8),
            "main state"
        )
        try Data("work state".utf8).write(to: clonedMarker)
        XCTAssertEqual(
            try String(contentsOf: markerURL, encoding: .utf8),
            "main state"
        )
    }

    func testCreateFromAnyBranchAndSelectWithoutTreeRestrictions() throws {
        let bundleURL = try makeBundle(
            active: "current",
            branches: [
                "main": BranchInfo(),
                "base": BranchInfo(),
                "current": BranchInfo(),
            ]
        )
        let markerURL = VMConfig.branchURL(in: bundleURL, branch: "base")
            .appendingPathComponent("marker")
        try Data("base state".utf8).write(to: markerURL)

        let create = try ToyVM.BranchCommand.CreateSubcommand.parse([
            bundleURL.path,
            "experiment",
            "--from",
            "base",
        ])
        try create.run()
        XCTAssertEqual(try BundleMeta.load(from: bundleURL).activeBranch, "experiment")

        let select = try ToyVM.BranchCommand.SelectSubcommand.parse([
            bundleURL.path,
            "base",
        ])
        try select.run()
        XCTAssertEqual(try BundleMeta.load(from: bundleURL).activeBranch, "base")
    }

    func testRenameActiveBranchPreservesReadOnlyStatus() throws {
        let bundleURL = try makeBundle(
            active: "main",
            branches: ["main": BranchInfo(readOnly: true)]
        )

        var command = try ToyVM.BranchCommand.RenameSubcommand.parse([
            bundleURL.path,
            "main",
            "baseline",
        ])
        try command.run()

        let meta = try BundleMeta.load(from: bundleURL)
        XCTAssertEqual(meta.activeBranch, "baseline")
        XCTAssertTrue(meta.branches["baseline"]?.readOnly == true)
        XCTAssertNil(meta.branches["main"])
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: VMConfig.branchURL(in: bundleURL, branch: "baseline").path
            )
        )
    }

    func testDeleteAllowsOnlyWritableInactiveBranches() throws {
        let bundleURL = try makeBundle(
            active: "work",
            branches: [
                "main": BranchInfo(),
                "work": BranchInfo(),
                "locked": BranchInfo(readOnly: true),
            ]
        )
        var meta = try BundleMeta.load(from: bundleURL)

        XCTAssertThrowsError(
            try deleteBranch(named: "work", from: bundleURL, meta: &meta)
        )
        XCTAssertThrowsError(
            try deleteBranch(named: "locked", from: bundleURL, meta: &meta)
        )

        try deleteBranch(named: "main", from: bundleURL, meta: &meta)
        XCTAssertNil(meta.branches["main"])
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: VMConfig.branchURL(in: bundleURL, branch: "main").path
            )
        )
    }

    func testUnsafeNamesAndRemovedSubcommandsAreRejected() throws {
        for name in ["", ".", "..", "nested/name", "bad\0name"] {
            XCTAssertThrowsError(try validateBranchName(name))
        }
        XCTAssertNoThrow(try validateBranchName(".checkpoint"))
        XCTAssertNoThrow(try validateBranchName("release-1.0"))

        XCTAssertThrowsError(
            try ToyVM.parseAsRoot(["branch", "commit", "vm"])
        )
        XCTAssertThrowsError(
            try ToyVM.parseAsRoot(["branch", "revert", "vm"])
        )
        XCTAssertThrowsError(
            try ToyVM.parseAsRoot(["branch", "delete", "vm"])
        )
    }

    private func makeEmptyBundle() throws -> URL {
        let baseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("toyvm-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: baseURL,
            withIntermediateDirectories: false
        )
        temporaryDirectories.append(baseURL)
        return baseURL
    }

    private func makeBundle(
        active: String,
        branches: [String: BranchInfo]
    ) throws -> URL {
        let bundleURL = try makeEmptyBundle()
        let branchesURL = bundleURL.appendingPathComponent(VMConfig.branchesDir)
        try FileManager.default.createDirectory(
            at: branchesURL,
            withIntermediateDirectories: false
        )
        for name in branches.keys {
            try FileManager.default.createDirectory(
                at: VMConfig.branchURL(in: bundleURL, branch: name),
                withIntermediateDirectories: false
            )
        }

        var meta = BundleMeta()
        meta.activeBranch = active
        meta.branches = branches
        try meta.save(to: bundleURL)
        return bundleURL
    }
}
