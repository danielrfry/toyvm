//
//  BranchCommand.swift
//  toyvm
//

import ArgumentParser
import Foundation

func branchLabels(for meta: BundleMeta) -> [String] {
    return meta.branches.keys.sorted().map { name in
        var label = name
        if meta.branches[name]?.readOnly == true { label += " [ro]" }
        if name == meta.activeBranch { label += " *" }
        return label
    }
}

func deleteBranch(named name: String, from bundleURL: URL, meta: inout BundleMeta) throws {
    try validateBranchName(name)

    guard let branchInfo = meta.branches[name] else {
        throw ToyVMError("Branch '\(name)' does not exist")
    }
    guard name != meta.activeBranch else {
        throw ToyVMError(
            "Cannot delete the active branch '\(name)'; select another branch first."
        )
    }
    guard !branchInfo.readOnly else {
        throw ToyVMError("Branch '\(name)' is read-only and cannot be deleted.")
    }

    let branchURL = VMConfig.branchURL(in: bundleURL, branch: name)
    let stagingURL = bundleURL
        .appendingPathComponent(VMConfig.branchesDir)
        .appendingPathComponent(".toyvm-delete-\(UUID().uuidString)")
    try FileManager.default.moveItem(at: branchURL, to: stagingURL)

    meta.branches.removeValue(forKey: name)
    do {
        try meta.save(to: bundleURL)
    } catch {
        try? FileManager.default.moveItem(at: stagingURL, to: branchURL)
        throw error
    }

    try FileManager.default.removeItem(at: stagingURL)
}

extension ToyVM {
    struct BranchCommand: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "branch",
            abstract: "Manage VM branches",
            subcommands: [
                LsSubcommand.self,
                CreateSubcommand.self,
                DeleteSubcommand.self,
                SelectSubcommand.self,
                RenameSubcommand.self,
            ]
        )

        // MARK: - ls

        struct LsSubcommand: ParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "ls",
                abstract: "List branches"
            )

            @Argument(help: "VM name or bundle path") var vm: String

            func run() throws {
                let bundleURL = try resolveBundlePath(vm)
                let meta = try BundleMeta.load(from: bundleURL)
                for label in branchLabels(for: meta) {
                    print(label)
                }
            }
        }

        // MARK: - create

        struct CreateSubcommand: ParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "create",
                abstract: "Create and select a new branch cloned from an existing branch"
            )

            @Argument(help: "VM name or bundle path") var vm: String
            @Argument(help: "Name for the new branch") var name: String
            @Option(name: .long, help: "Branch to clone (defaults to active branch)") var from: String?

            func run() throws {
                try validateBranchName(name)

                let bundleURL = try resolveBundlePath(vm)
                var meta = try BundleMeta.load(from: bundleURL)

                guard meta.branches[name] == nil else {
                    throw ToyVMError("Branch '\(name)' already exists")
                }

                let source = from ?? meta.activeBranch
                try validateBranchName(source)
                guard meta.branches[source] != nil else {
                    throw ToyVMError("Source branch '\(source)' does not exist")
                }

                let sourceURL = VMConfig.branchURL(in: bundleURL, branch: source)
                let destinationURL = VMConfig.branchURL(in: bundleURL, branch: name)
                try cloneBranchDirectory(from: sourceURL, to: destinationURL)

                meta.branches[name] = BranchInfo()
                meta.activeBranch = name
                do {
                    try meta.save(to: bundleURL)
                } catch {
                    try? FileManager.default.removeItem(at: destinationURL)
                    throw error
                }

                print("Created and selected branch '\(name)' from '\(source)'")
            }
        }

        // MARK: - delete

        struct DeleteSubcommand: ParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "delete",
                abstract: "Delete a branch"
            )

            @Argument(help: "VM name or bundle path") var vm: String
            @Argument(help: "Branch to delete") var name: String

            mutating func run() throws {
                try validateBranchName(name)

                let bundleURL = try resolveBundlePath(vm)
                var meta = try BundleMeta.load(from: bundleURL)

                guard let branchInfo = meta.branches[name] else {
                    throw ToyVMError("Branch '\(name)' does not exist")
                }
                guard name != meta.activeBranch else {
                    throw ToyVMError(
                        "Cannot delete the active branch '\(name)'; select another branch first."
                    )
                }
                guard !branchInfo.readOnly else {
                    throw ToyVMError("Branch '\(name)' is read-only and cannot be deleted.")
                }

                guard confirm("Will permanently delete branch '\(name)'.\nContinue? (yes/no) ") else {
                    throw ToyVMError("Deletion cancelled.")
                }

                try deleteBranch(named: name, from: bundleURL, meta: &meta)
                print("Deleted branch '\(name)'")
            }
        }

        // MARK: - select

        struct SelectSubcommand: ParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "select",
                abstract: "Set the active branch"
            )

            @Argument(help: "VM name or bundle path") var vm: String
            @Argument(help: "Branch to make active") var name: String

            func run() throws {
                try validateBranchName(name)

                let bundleURL = try resolveBundlePath(vm)
                var meta = try BundleMeta.load(from: bundleURL)

                guard meta.branches[name] != nil else {
                    throw ToyVMError("Branch '\(name)' does not exist")
                }

                meta.activeBranch = name
                try meta.save(to: bundleURL)
                print("Active branch set to '\(name)'")
            }
        }

        // MARK: - rename

        struct RenameSubcommand: ParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "rename",
                abstract: "Rename a branch"
            )

            @Argument(help: "VM name or bundle path") var vm: String
            @Argument(help: "Current branch name") var oldName: String
            @Argument(help: "New branch name") var newName: String

            mutating func run() throws {
                try validateBranchName(oldName)
                try validateBranchName(newName)

                let bundleURL = try resolveBundlePath(vm)
                var meta = try BundleMeta.load(from: bundleURL)

                guard let branchInfo = meta.branches[oldName] else {
                    throw ToyVMError("Branch '\(oldName)' does not exist")
                }
                guard meta.branches[newName] == nil else {
                    throw ToyVMError("Branch '\(newName)' already exists")
                }

                let oldURL = VMConfig.branchURL(in: bundleURL, branch: oldName)
                let newURL = VMConfig.branchURL(in: bundleURL, branch: newName)
                try FileManager.default.moveItem(at: oldURL, to: newURL)

                meta.branches.removeValue(forKey: oldName)
                meta.branches[newName] = branchInfo
                if meta.activeBranch == oldName {
                    meta.activeBranch = newName
                }

                do {
                    try meta.save(to: bundleURL)
                } catch {
                    try? FileManager.default.moveItem(at: newURL, to: oldURL)
                    throw error
                }

                print("Renamed branch '\(oldName)' to '\(newName)'")
            }
        }
    }
}
