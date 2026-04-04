//
//  ContentView.swift
//  ToyVMApp
//

import SwiftUI
import ToyVMCore

@available(macOS 14.0, *)
struct ContentView: View {
    @Bindable var manager: VMManager

    var body: some View {
        NavigationSplitView {
            VMListView(manager: manager)
        } detail: {
            if let url = manager.selectedBundleURL,
               let bundle = manager.bundles.first(where: { $0.bundleURL == url }) {
                VMDetailView(session: manager.session(for: bundle), manager: manager)
            } else {
                ContentUnavailableView(
                    "No VM Selected",
                    systemImage: "desktopcomputer",
                    description: Text("Select a virtual machine from the sidebar, or create a new one.")
                )
            }
        }
        .sheet(isPresented: $manager.showCreateSheet) {
            CreateVMView(manager: manager)
        }
        .frame(minWidth: 700, minHeight: 400)
    }
}
