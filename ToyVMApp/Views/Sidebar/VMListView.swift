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

    var body: some View {
        List(manager.bundles, id: \.bundleURL, selection: $manager.selectedBundleURL) { bundle in
            VMRowView(
                bundle: bundle,
                session: manager.sessions[bundle.bundleURL]
            )
            .contextMenu {
                Button("Delete…", role: .destructive) {
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
    }
}
