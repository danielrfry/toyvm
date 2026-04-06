//
//  TerminalLayerView.swift
//  ToyVMApp
//

import SwiftUI
#if canImport(ToyVMCore)
import ToyVMCore
#endif

/// Persistent layer that holds one `TerminalDisplayView` for every session that has
/// been started in terminal mode. Views are never removed from the hierarchy — only
/// hidden — so the scroll buffer and terminal state are preserved when switching VMs.
///
/// `TerminalDisplayView.updateNSView` reads `session.inputPipe`, which establishes an
/// `@Observable` dependency so SwiftUI calls `updateNSView` again when the pipe
/// changes (e.g. on VM start or stop), keeping the pipe connection up to date.
@available(macOS 15.0, *)
struct TerminalLayerView: View {
    let manager: VMManager

    var body: some View {
        ZStack {
            ForEach(terminalSessions) { session in
                TerminalDisplayView(session: session)
                    .opacity(session.bundle.bundleURL == manager.selectedBundleURL ? 1 : 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Sessions that are or have been running in terminal mode.
    private var terminalSessions: [VMSession] {
        manager.sessions.values
            .filter { $0.runner != nil && $0.displayMode == .terminal }
            .sorted { $0.bundle.bundleURL.path < $1.bundle.bundleURL.path }
    }
}
