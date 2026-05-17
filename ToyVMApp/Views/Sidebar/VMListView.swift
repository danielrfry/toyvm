//
//  VMListView.swift
//  ToyVMApp
//

import SwiftUI
#if canImport(ToyVMCore)
import ToyVMCore
#endif

@available(macOS 15.0, *)
struct VMListView: View {
    @Bindable var manager: VMManager
    @State private var bundleToDelete: VMBundle?
    @State private var renamingBundleURL: URL?
    @State private var renameText = ""

    var body: some View {
        List(manager.bundles, id: \.bundleURL, selection: $manager.selectedBundleURL) { bundle in
            let isSelected = manager.selectedBundleURL == bundle.bundleURL
            VMRowView(
                bundle: bundle,
                session: manager.sessions[bundle.bundleURL],
                isRenaming: renamingBundleURL == bundle.bundleURL,
                renameText: $renameText,
                onNameClick: {
                    if isSelected {
                        beginRename(bundle)
                    } else {
                        manager.selectedBundleURL = bundle.bundleURL
                    }
                },
                onRenameCommit: {
                    commitRename(for: bundle)
                },
                onRenameCancel: {
                    cancelRename()
                }
            )
            .contextMenu {
                Button("Rename…") {
                    beginRename(bundle)
                }
                Button("Delete…", role: .destructive) {
                    cancelRename()
                    bundleToDelete = bundle
                }
            }
        }
        .navigationTitle("Virtual Machines")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    manager.showCreateSheet = true
                } label: {
                    Label("New VM", systemImage: "plus")
                }
            }
            ToolbarItem(placement: .automatic) {
                Button {
                    manager.refresh()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
        }
        .alert("Delete Virtual Machine?", isPresented: .init(
            get: { bundleToDelete != nil },
            set: { if !$0 { bundleToDelete = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let bundle = bundleToDelete {
                    do {
                        try manager.delete(bundle: bundle)
                    } catch {
                        manager.errorMessage = error.localizedDescription
                    }
                }
                bundleToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                bundleToDelete = nil
            }
        } message: {
            if let bundle = bundleToDelete {
                Text("Are you sure you want to delete \"\(VMManager.displayName(for: bundle))\"? This action cannot be undone.")
            }
        }
        .alert("Error", isPresented: .init(
            get: { manager.errorMessage != nil },
            set: { if !$0 { manager.errorMessage = nil } }
        )) {
            Button("OK") { manager.errorMessage = nil }
        } message: {
            if let errorMessage = manager.errorMessage {
                Text(errorMessage)
            }
        }
    }

    private func beginRename(_ bundle: VMBundle) {
        manager.selectedBundleURL = bundle.bundleURL
        renamingBundleURL = bundle.bundleURL
        renameText = VMManager.displayName(for: bundle)
    }

    private func cancelRename() {
        renamingBundleURL = nil
        renameText = ""
    }

    private func commitRename(for bundle: VMBundle) {
        guard renamingBundleURL == bundle.bundleURL else { return }

        let requestedName = VMManager.normalizedDisplayName(renameText)
        do {
            _ = try manager.rename(bundle: bundle, to: requestedName)
            cancelRename()
        } catch {
            manager.errorMessage = error.localizedDescription
        }
    }
}
