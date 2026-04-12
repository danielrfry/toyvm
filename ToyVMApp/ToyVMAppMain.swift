//
//  ToyVMAppMain.swift
//  ToyVMApp
//

import SwiftUI
#if canImport(ToyVMCore)
import ToyVMCore
#endif

@available(macOS 15.0, *)
@main
struct ToyVMAppMain: App {
    @State private var manager = VMManager()
    @State private var showConfigEditor = false
    @State private var showBranchSheet = false
    @State private var showAddShareSheet = false
    @State private var showForceStopConfirmation = false

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

    private var isRunning: Bool {
        guard let state = selectedSession?.runner?.state else { return false }
        switch state {
        case .running, .starting, .stopping: return true
        default: return false
        }
    }

    private var sharesEditable: Bool {
        guard let session = selectedSession else { return false }
        return !isRunning || session.bundle.config.bootMode == .macOS
    }

    var body: some Scene {
        WindowGroup {
            ContentView(manager: manager)
                .sheet(isPresented: $showConfigEditor) {
                    if let session = selectedSession {
                        ConfigEditView(session: session, isRunning: isRunning)
                    }
                }
                .sheet(isPresented: $showBranchSheet) {
                    if let session = selectedSession {
                        BranchManagementSheet(session: session)
                    }
                }
                .sheet(isPresented: $showAddShareSheet) {
                    if let session = selectedSession {
                        ShareEditSheet(session: session, existing: nil) {}
                    }
                }
                .alert("Force Stop Virtual Machine?", isPresented: $showForceStopConfirmation) {
                    Button("Force Stop", role: .destructive) { selectedSession?.forceStop() }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("The virtual machine will be stopped immediately. Any unsaved data in the guest may be lost.")
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Virtual Machine…") {
                    manager.showCreateSheet = true
                }
                .keyboardShortcut("n", modifiers: .command)
            }

            CommandMenu("Virtual Machine") {
                Button("Start") {
                    if let session = selectedSession {
                        Task { await session.start() }
                    }
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(selectedSession == nil || isRunning)

                Button("Stop") {
                    selectedSession?.requestStop()
                }
                .keyboardShortcut(".", modifiers: .command)
                .disabled(selectedSession == nil || !isRunning)

                Button("Force Stop…") {
                    showForceStopConfirmation = true
                }
                .keyboardShortcut(".", modifiers: [.command, .option])
                .disabled(selectedSession == nil || !isRunning)

                Divider()

                Button("Configuration…") {
                    showConfigEditor = true
                }
                .keyboardShortcut(",", modifiers: .command)
                .disabled(selectedSession == nil)

                Button("Branches…") {
                    showBranchSheet = true
                }
                .keyboardShortcut("b", modifiers: .command)
                .disabled(selectedSession == nil || isRunning)

                Divider()

                Button("Add Directory Share…") {
                    showAddShareSheet = true
                }
                .disabled(!sharesEditable)
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
