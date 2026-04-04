//
//  ContentView.swift
//  ToyVMApp
//

import SwiftUI
#if canImport(ToyVMCore)
import ToyVMCore
#endif

@available(macOS 14.0, *)
struct ContentView: View {
    @Bindable var manager: VMManager
    @State private var fullScreenObserver = FullScreenObserver()

    private var selectedSession: VMSession? {
        guard let url = manager.selectedBundleURL,
              let bundle = manager.bundles.first(where: { $0.bundleURL == url }) else {
            return nil
        }
        return manager.sessions[bundle.bundleURL]
    }

    /// Whether to hide all chrome: only when the window is in macOS full screen
    /// AND the selected VM has an active display.
    private var shouldHideChrome: Bool {
        guard fullScreenObserver.isFullScreen,
              let session = selectedSession else {
            return false
        }
        switch session.runner?.state {
        case .starting, .running, .stopping:
            return true
        default:
            return false
        }
    }

    var body: some View {
        ZStack {
            // Invisible helper to track full screen state of the hosting window
            FullScreenTracker(observer: fullScreenObserver)
                .frame(width: 0, height: 0)

            if shouldHideChrome, let session = selectedSession {
                // In full screen with a running VM: show only the display, edge to edge
                VMDisplayView(session: session)
                    .ignoresSafeArea()
                    .toolbar(.hidden, for: .windowToolbar)
            } else {
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
            }
        }
        .sheet(isPresented: $manager.showCreateSheet) {
            CreateVMView(manager: manager)
        }
        .frame(minWidth: 700, minHeight: 400)
    }
}
