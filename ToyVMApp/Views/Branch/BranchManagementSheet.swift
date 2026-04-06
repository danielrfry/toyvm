//
//  BranchManagementSheet.swift
//  ToyVMApp
//

import SwiftUI
#if canImport(ToyVMCore)
import ToyVMCore
#endif

/// Sheet dialog for managing branches of a VM bundle.
/// Presents a graphical tree and provides all branch operations
/// via context menus and dialogs.
@available(macOS 15.0, *)
struct BranchManagementSheet: View {
    @Bindable var session: VMSession
    @Environment(\.dismiss) private var dismiss

    // MARK: - Dialog state

    @State private var showCreateSheet = false
    @State private var createParent = ""
    @State private var createName = ""

    @State private var showRenameAlert = false
    @State private var renameBranch = ""
    @State private var renameNewName = ""

    @State private var showDeleteConfirm = false
    @State private var deleteBranchName = ""
    @State private var deleteDescendants: [String] = []

    @State private var showRevertConfirm = false
    @State private var revertBranchName = ""

    @State private var showCommitConfirm = false
    @State private var commitBranchName = ""

    @State private var errorMessage: String?
    @State private var showError = false

    private var isRunning: Bool {
        switch session.runner?.state {
        case .starting, .running, .stopping: return true
        default: return false
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Branches")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            // Tree
            ScrollView {
                BranchTreeView(
                    meta: session.bundle.meta,
                    actions: branchActions,
                    isDisabled: isRunning
                )
                .padding()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Footer with Create button
            HStack {
                Button {
                    createParent = session.bundle.meta.activeBranch
                    createName = ""
                    showCreateSheet = true
                } label: {
                    Label("Create Branch…", systemImage: "plus")
                }
                .disabled(isRunning)

                Spacer()
            }
            .padding()
        }
        .frame(minWidth: 400, idealWidth: 500, minHeight: 300, idealHeight: 400)
        // Create branch sub-sheet
        .sheet(isPresented: $showCreateSheet) {
            createBranchSheet
        }
        // Rename alert
        .alert("Rename Branch", isPresented: $showRenameAlert) {
            TextField("New name", text: $renameNewName)
            Button("Rename") { performRename() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter a new name for branch '\(renameBranch)'.")
        }
        // Delete confirmation
        .alert("Delete Branch", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) { performDelete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            if deleteDescendants.count > 1 {
                Text("This will permanently delete '\(deleteBranchName)' and \(deleteDescendants.count - 1) descendant branch(es):\n\(deleteDescendants.dropFirst().joined(separator: ", "))")
            } else {
                Text("This will permanently delete branch '\(deleteBranchName)'.")
            }
        }
        // Revert confirmation
        .alert("Revert Branch", isPresented: $showRevertConfirm) {
            Button("Revert", role: .destructive) { performRevert() }
            Button("Cancel", role: .cancel) {}
        } message: {
            let parentName = session.bundle.meta.branches[revertBranchName]?.parent ?? "parent"
            Text("This will discard all changes to '\(revertBranchName)' and revert to the state of '\(parentName)'.")
        }
        // Commit confirmation
        .alert("Commit Branch", isPresented: $showCommitConfirm) {
            Button("Commit") { performCommit() }
            Button("Cancel", role: .cancel) {}
        } message: {
            let parentName = session.bundle.meta.branches[commitBranchName]?.parent ?? "parent"
            Text("This will replace '\(parentName)' with the contents of '\(commitBranchName)' and delete '\(commitBranchName)'.")
        }
        // Error alert
        .alert("Error", isPresented: $showError) {
            Button("OK") {}
        } message: {
            if let errorMessage {
                Text(errorMessage)
            }
        }
    }

    // MARK: - Create Branch Sheet

    private var createBranchSheet: some View {
        VStack(spacing: 16) {
            Text("Create Branch")
                .font(.headline)

            Form {
                LabeledContent("Parent Branch") {
                    Text(createParent)
                        .foregroundStyle(.secondary)
                }
                TextField("Branch Name", text: $createName)
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel") { showCreateSheet = false }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Create") { performCreate() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(createName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
        .frame(width: 350)
    }

    // MARK: - Branch Actions

    private var branchActions: BranchActions {
        BranchActions(
            onCreate: { parent in
                createParent = parent
                createName = ""
                showCreateSheet = true
            },
            onSelect: { name in
                performSelect(name)
            },
            onRename: { name in
                renameBranch = name
                renameNewName = name
                showRenameAlert = true
            },
            onDelete: { name in
                do {
                    let toDelete = try session.bundle.validateDeleteBranch(named: name)
                    deleteBranchName = name
                    deleteDescendants = toDelete
                    showDeleteConfirm = true
                } catch {
                    showErrorMessage(error.localizedDescription)
                }
            },
            onRevert: { name in
                revertBranchName = name
                showRevertConfirm = true
            },
            onCommit: { name in
                commitBranchName = name
                showCommitConfirm = true
            },
            onToggleReadOnly: { name in
                performToggleReadOnly(name)
            }
        )
    }

    // MARK: - Operations

    private func performCreate() {
        let name = createName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        do {
            try session.bundle.createBranch(named: name, from: createParent)
            session.reloadBundle()
            showCreateSheet = false
        } catch {
            showErrorMessage(error.localizedDescription)
        }
    }

    private func performSelect(_ name: String) {
        do {
            try session.bundle.selectBranch(named: name)
            session.reloadBundle()
        } catch {
            showErrorMessage(error.localizedDescription)
        }
    }

    private func performRename() {
        let newName = renameNewName.trimmingCharacters(in: .whitespaces)
        guard !newName.isEmpty else { return }
        do {
            try session.bundle.renameBranch(from: renameBranch, to: newName)
            session.reloadBundle()
        } catch {
            showErrorMessage(error.localizedDescription)
        }
    }

    private func performDelete() {
        do {
            try session.bundle.deleteBranch(named: deleteBranchName)
            session.reloadBundle()
        } catch {
            showErrorMessage(error.localizedDescription)
        }
    }

    private func performRevert() {
        do {
            try session.bundle.revertBranch(named: revertBranchName)
            session.reloadBundle()
        } catch {
            showErrorMessage(error.localizedDescription)
        }
    }

    private func performCommit() {
        do {
            try session.bundle.commitBranch(named: commitBranchName)
            session.reloadBundle()
        } catch {
            showErrorMessage(error.localizedDescription)
        }
    }

    private func performToggleReadOnly(_ name: String) {
        do {
            let current = session.bundle.meta.branches[name]?.readOnly ?? false
            try session.bundle.setBranchReadOnly(!current, branch: name)
            session.reloadBundle()
        } catch {
            showErrorMessage(error.localizedDescription)
        }
    }

    private func showErrorMessage(_ message: String) {
        errorMessage = message
        showError = true
    }
}
