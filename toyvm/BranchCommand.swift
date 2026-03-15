//
//  BranchCommand.swift
//  toyvm
//

import ArgumentParser
import Foundation

extension ToyVM {
    struct BranchCommand: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "branch",
            abstract: "Manage VM branches",
            subcommands: [
                LsSubcommand.self,
                CreateSubcommand.self,
                DeleteSubcommand.self,
                RevertSubcommand.self,
                CommitSubcommand.self,
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
                guard let root = meta.rootBranch else { return }
                print(branchLabel(root, meta: meta))
                printChildren(of: root, meta: meta, prefix: "")
            }

            private func branchLabel(_ name: String, meta: BundleMeta) -> String {
                var label = name
                if meta.branches[name]?.readOnly == true { label += " [ro]" }
                if name == meta.activeBranch { label += " *" }
                return label
            }

            private func printChildren(of parent: String, meta: BundleMeta, prefix: String) {
                let kids = meta.children(of: parent)
                for (i, child) in kids.enumerated() {
                    let isLast = i == kids.count - 1
                    let connector = isLast ? "└── " : "├── "
                    print("\(prefix)\(connector)\(branchLabel(child, meta: meta))")
                    let childPrefix = prefix + (isLast ? "    " : "│   ")
                    printChildren(of: child, meta: meta, prefix: childPrefix)
                }
            }
        }

        // MARK: - create

        struct CreateSubcommand: ParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "create",
                abstract: "Create a new branch from an existing branch"
            )

            @Argument(help: "VM name or bundle path") var vm: String
            @Argument(help: "Name for the new branch") var name: String
            @Option(name: .long, help: "Branch to create from (defaults to active branch)") var from: String?

            func run() throws {
                let bundleURL = try resolveBundlePath(vm)
                var meta = try BundleMeta.load(from: bundleURL)

                guard meta.branches[name] == nil else {
                    throw ToyVMError("Branch '\(name)' already exists")
                }
                let parent = from ?? meta.activeBranch
                guard meta.branches[parent] != nil else {
                    throw ToyVMError("Parent branch '\(parent)' does not exist")
                }
                let srcURL = VMConfig.branchURL(in: bundleURL, branch: parent)
                let dstURL = VMConfig.branchURL(in: bundleURL, branch: name)

                try cloneBranchDirectory(from: srcURL, to: dstURL)

                meta.branches[name] = BranchInfo(parent: parent)
                // Make the newly-created branch the active branch (it will be a leaf)
                meta.activeBranch = name
                try meta.save(to: bundleURL)

                print("Created and selected branch '\(name)' from '\(parent)'")
            }
        }

        // MARK: - delete

        struct DeleteSubcommand: ParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "delete",
                abstract: "Delete a branch and all its descendants"
            )

            @Argument(help: "VM name or bundle path") var vm: String
            @Argument(help: "Branch to delete (defaults to active branch)") var name: String?

            mutating func run() throws {
                let bundleURL = try resolveBundlePath(vm)
                var meta = try BundleMeta.load(from: bundleURL)

                let branchName = name ?? meta.activeBranch

                guard meta.branches[branchName] != nil else {
                    throw ToyVMError("Branch '\(branchName)' does not exist")
                }
                guard meta.branches[branchName]!.parent != nil else {
                    throw ToyVMError("The root branch cannot be deleted")
                }
                if meta.branches[branchName]!.readOnly {
                    throw ToyVMError("Branch '\(branchName)' is read-only and cannot be deleted.")
                }

                let toDelete = [branchName] + meta.descendants(of: branchName)

                // If the active branch is in the subtree being deleted, the parent of `branchName`
                // must become a leaf after deletion so it can take over as the active branch.
                let activeWillBeDeleted = toDelete.contains(meta.activeBranch)
                let parentName = meta.branches[branchName]!.parent!
                if activeWillBeDeleted {
                    // Count how many children parent(branchName) will have after deleting `branchName`'s subtree
                    let remainingSiblings = meta.children(of: parentName).filter { $0 != branchName }
                    if !remainingSiblings.isEmpty {
                        throw ToyVMError(
                            "Cannot delete branch '\(branchName)': it contains the active branch " +
                            "'\(meta.activeBranch)', and its parent '\(parentName)' still has other " +
                            "child branches. Select a different active branch first."
                        )
                    }
                }

                // Confirm deletion
                var msg: String
                if toDelete.count == 1 {
                    msg = "Will permanently delete branch '\(branchName)'.\n"
                } else {
                    msg = "Will permanently delete branch '\(branchName)' and \(toDelete.count - 1) descendant(s):\n"
                    for d in toDelete.dropFirst() { msg += "  - \(d)\n" }
                }
                msg += "Continue? (yes/no) "

                guard confirm(msg) else {
                    throw ToyVMError("Deletion cancelled.")
                }

                // Remove directories and metadata
                for branch in toDelete {
                    let branchURL = VMConfig.branchURL(in: bundleURL, branch: branch)
                    try? FileManager.default.removeItem(at: branchURL)
                    meta.branches.removeValue(forKey: branch)
                }
                if activeWillBeDeleted {
                    meta.activeBranch = parentName
                }
                try meta.save(to: bundleURL)
                print("Deleted branch '\(branchName)'" + (toDelete.count > 1 ? " and \(toDelete.count - 1) descendant(s)" : ""))
            }
        }

        // MARK: - revert

        struct RevertSubcommand: ParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "revert",
                abstract: "Revert a branch to the current state of its parent (defaults to active branch)"
            )

            @Argument(help: "VM name or bundle path") var vm: String
            @Argument(help: "Branch to revert (defaults to active branch)") var name: String?

            mutating func run() throws {
                let bundleURL = try resolveBundlePath(vm)
                let meta = try BundleMeta.load(from: bundleURL)

                let branchName = name ?? meta.activeBranch

                guard meta.branches[branchName] != nil else {
                    throw ToyVMError("Branch '\(branchName)' does not exist")
                }
                guard let parentName = meta.branches[branchName]!.parent else {
                    throw ToyVMError("The root branch cannot be reverted (it has no parent)")
                }
                if meta.branches[branchName]!.readOnly {
                    throw ToyVMError("Branch '\(branchName)' is read-only and cannot be reverted.")
                }

                var msg = "This will discard all changes to branch '\(branchName)' and revert to the state of '\(parentName)'.\n"
                msg += "Continue? (yes/no) "
                guard confirm(msg) else {
                    throw ToyVMError("Revert cancelled.")
                }

                let branchURL = VMConfig.branchURL(in: bundleURL, branch: branchName)
                let parentURL = VMConfig.branchURL(in: bundleURL, branch: parentName)
                let tempURL = VMConfig.branchURL(in: bundleURL, branch: branchName + ".\(UUID().uuidString).tmp")

                // Clone parent to temp, then atomically swap
                try cloneBranchDirectory(from: parentURL, to: tempURL)
                do {
                    try FileManager.default.removeItem(at: branchURL)
                    try FileManager.default.moveItem(at: tempURL, to: branchURL)
                } catch {
                    try? FileManager.default.removeItem(at: tempURL)
                    throw error
                }
                // BundleMeta unchanged (branch still exists with same parent)
                print("Reverted '\(branchName)' to state of '\(parentName)'")
            }
        }

        // MARK: - commit

        struct CommitSubcommand: ParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "commit",
                abstract: "Commit a branch to its parent (branch is then deleted, defaults to active branch)"
            )

            @Argument(help: "VM name or bundle path") var vm: String
            @Argument(help: "Branch to commit (defaults to active branch)") var name: String?

            mutating func run() throws {
                let bundleURL = try resolveBundlePath(vm)
                var meta = try BundleMeta.load(from: bundleURL)

                let branchName = name ?? meta.activeBranch

                guard meta.branches[branchName] != nil else {
                    throw ToyVMError("Branch '\(branchName)' does not exist")
                }
                guard let parentName = meta.branches[branchName]!.parent else {
                    throw ToyVMError("The root branch cannot be committed (it has no parent)")
                }
                if meta.branches[branchName]!.readOnly {
                    throw ToyVMError("Branch '\(branchName)' is read-only and cannot be committed.")
                }
                if meta.branches[parentName]?.readOnly == true {
                    throw ToyVMError("Cannot commit to '\(parentName)': it is read-only.")
                }
                guard meta.children(of: branchName).isEmpty else {
                    throw ToyVMError(
                        "Branch '\(branchName)' has child branches and cannot be committed. " +
                        "Delete its children first."
                    )
                }
                let parentSiblings = meta.children(of: parentName).filter { $0 != branchName }
                guard parentSiblings.isEmpty else {
                    throw ToyVMError(
                        "Cannot commit '\(branchName)': its parent '\(parentName)' has other child " +
                        "branches (\(parentSiblings.joined(separator: ", "))). " +
                        "Delete them first."
                    )
                }

                var msg = "This will commit branch '\(branchName)' to '\(parentName)' and delete '\(branchName)'.\n"
                msg += "Continue? (yes/no) "
                guard confirm(msg) else {
                    throw ToyVMError("Commit cancelled.")
                }

                let branchURL = VMConfig.branchURL(in: bundleURL, branch: branchName)
                let parentURL = VMConfig.branchURL(in: bundleURL, branch: parentName)
                let tempURL = VMConfig.branchURL(in: bundleURL, branch: parentName + ".\(UUID().uuidString).tmp")

                // Clone branch → temp, remove parent, rename temp → parent
                try cloneBranchDirectory(from: branchURL, to: tempURL)
                do {
                    try FileManager.default.removeItem(at: parentURL)
                    try FileManager.default.moveItem(at: tempURL, to: parentURL)
                } catch {
                    try? FileManager.default.removeItem(at: tempURL)
                    throw error
                }
                try FileManager.default.removeItem(at: branchURL)

                meta.branches.removeValue(forKey: branchName)
                meta.activeBranch = parentName
                try meta.save(to: bundleURL)

                print("Committed '\(branchName)' to '\(parentName)'; '\(branchName)' deleted")
            }
        }

        // MARK: - select

        struct SelectSubcommand: ParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "select",
                abstract: "Set the active branch (must be a leaf branch)"
            )

            @Argument(help: "VM name or bundle path") var vm: String
            @Argument(help: "Branch to make active") var name: String

            func run() throws {
                let bundleURL = try resolveBundlePath(vm)
                var meta = try BundleMeta.load(from: bundleURL)

                guard meta.branches[name] != nil else {
                    throw ToyVMError("Branch '\(name)' does not exist")
                }
                guard meta.children(of: name).isEmpty else {
                    throw ToyVMError(
                        "Branch '\(name)' has child branches; only leaf branches can be selected. " +
                        "Select one of its descendants instead."
                    )
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
                let bundleURL = try resolveBundlePath(vm)
                var meta = try BundleMeta.load(from: bundleURL)

                guard meta.branches[oldName] != nil else {
                    throw ToyVMError("Branch '\(oldName)' does not exist")
                }
                guard meta.branches[newName] == nil else {
                    throw ToyVMError("Branch '\(newName)' already exists")
                }

                // Rename the branch directory
                let oldURL = VMConfig.branchURL(in: bundleURL, branch: oldName)
                let newURL = VMConfig.branchURL(in: bundleURL, branch: newName)
                try FileManager.default.moveItem(at: oldURL, to: newURL)

                // Update metadata
                let branchInfo = meta.branches[oldName]!
                meta.branches.removeValue(forKey: oldName)
                meta.branches[newName] = branchInfo

                // Update children's parent references
                for (childName, childInfo) in meta.branches {
                    if childInfo.parent == oldName {
                        meta.branches[childName] = BranchInfo(parent: newName)
                    }
                }

                // Update active branch if it was the renamed branch
                if meta.activeBranch == oldName {
                    meta.activeBranch = newName
                }

                try meta.save(to: bundleURL)
                print("Renamed branch '\(oldName)' to '\(newName)'")
            }
        }
    }
}
