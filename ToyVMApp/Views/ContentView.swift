//
//  ContentView.swift
//  ToyVMApp
//

import SwiftUI
#if canImport(ToyVMCore)
import ToyVMCore
#endif

@available(macOS 15.0, *)
struct ContentView: View {
    @Bindable var manager: VMManager
    @State private var fullScreenObserver = FullScreenObserver()
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    private var selectedSession: VMSession? {
        guard let url = manager.selectedBundleURL,
              let bundle = manager.bundles.first(where: { $0.bundleURL == url }) else {
            return nil
        }
        return manager.sessions[bundle.bundleURL]
    }

    /// Whether the selected VM has an active display.
    private var vmIsActive: Bool {
        guard let session = selectedSession else { return false }
        switch session.runner?.state {
        case .starting, .running, .stopping:
            return true
        default:
            return false
        }
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
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
        .background {
            // Invisible helper to track full screen state of the hosting window
            FullScreenTracker(observer: fullScreenObserver)
        }
        .background(fullScreenObserver.isFullScreen && vmIsActive ? Color.black : Color.clear)
        .windowToolbarFullScreenVisibility(vmIsActive ? .onHover : .visible)
        .onChange(of: vmIsActive) { _, isActive in
            // Auto-adjust sidebar only when in fullscreen
            if fullScreenObserver.isFullScreen {
                columnVisibility = isActive ? .detailOnly : .all
            }
        }
        .onChange(of: fullScreenObserver.isFullScreen) { _, isFullScreen in
            // When entering fullscreen, adjust sidebar based on VM state
            if isFullScreen {
                columnVisibility = vmIsActive ? .detailOnly : .all
            }
        }
        .sheet(isPresented: $manager.showCreateSheet) {
            CreateVMView(manager: manager)
        }
        .frame(minWidth: 700, minHeight: 400)
    }
}
