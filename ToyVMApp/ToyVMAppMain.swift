//
//  ToyVMAppMain.swift
//  ToyVMApp
//

import SwiftUI

@available(macOS 14.0, *)
@main
struct ToyVMAppMain: App {
    @State private var manager = VMManager()

    /// The currently selected VM session, if any.
    private var selectedSession: VMSession? {
        guard let url = manager.selectedBundleURL,
              let bundle = manager.bundles.first(where: { $0.bundleURL == url }) else {
            return nil
        }
        return manager.sessions[bundle.bundleURL]
    }

    /// Whether the selected session has an active graphics display.
    private var hasGraphicsDisplay: Bool {
        guard let session = selectedSession,
              session.displayMode == .graphics else {
            return false
        }
        switch session.runner?.state {
        case .starting, .running, .stopping:
            return true
        default:
            return false
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(manager: manager)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Virtual Machine…") {
                    manager.showCreateSheet = true
                }
                .keyboardShortcut("n", modifiers: .command)
            }
            CommandGroup(after: .toolbar) {
                Toggle("Automatic Display Resize", isOn: Binding(
                    get: { selectedSession?.automaticDisplayResize ?? true },
                    set: { selectedSession?.automaticDisplayResize = $0 }
                ))
                .disabled(!hasGraphicsDisplay)
            }
        }
    }
}
