//
//  BranchCommand.swift
//  toyvm
//

import ArgumentParser
import Foundation
#if canImport(ToyVMCore)
import ToyVMCore
#endif

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
                let bundle = try VMBundle.load(from: bundleURL)
                let meta = bundle.meta
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

            mutating func run() throws {
                let bundleURL = try resolveBundlePath(vm)
                var bundle = try VMBundle.load(from: bundleURL)
                let parent = from ?? bundle.meta.activeBranch
                try bundle.createBranch(named: name, from: parent)
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
                var bundle = try VMBundle.load(from: bundleURL)
                let branchName = name ?? bundle.meta.activeBranch

                // Validate constraints and get the deletion list for the confirmation prompt
                let toDelete = try bundle.validateDeleteBranch(named: branchName)

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

                try bundle.deleteBranch(named: branchName)
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
                var bundle = try VMBundle.load(from: bundleURL)
                let branchName = name ?? bundle.meta.activeBranch
                guard let parentName = bundle.meta.branches[branchName]?.parent else {
                    throw ToyVMError("Branch '\(branchName)' does not exist or has no parent")
                }

                var msg = "This will discard all changes to branch '\(branchName)' and revert to the state of '\(parentName)'.\n"
                msg += "Continue? (yes/no) "
                guard confirm(msg) else {
                    throw ToyVMError("Revert cancelled.")
                }

                try bundle.revertBranch(named: branchName)
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
                var bundle = try VMBundle.load(from: bundleURL)
                let branchName = name ?? bundle.meta.activeBranch
                guard let parentName = bundle.meta.branches[branchName]?.parent else {
                    throw ToyVMError("Branch '\(branchName)' does not exist or has no parent")
                }

                var msg = "This will commit branch '\(branchName)' to '\(parentName)' and delete '\(branchName)'.\n"
                msg += "Continue? (yes/no) "
                guard confirm(msg) else {
                    throw ToyVMError("Commit cancelled.")
                }

                try bundle.commitBranch(named: branchName)
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

            mutating func run() throws {
                let bundleURL = try resolveBundlePath(vm)
                var bundle = try VMBundle.load(from: bundleURL)
                try bundle.selectBranch(named: name)
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
                var bundle = try VMBundle.load(from: bundleURL)
                try bundle.renameBranch(from: oldName, to: newName)
                print("Renamed branch '\(oldName)' to '\(newName)'")
            }
        }
    }
}
