//
//  TerminalDisplayView.swift
//  ToyVMApp
//

import SwiftUI
import SwiftTerm
#if canImport(ToyVMCore)
import ToyVMCore
#endif

/// Thin NSViewRepresentable wrapper around the `TerminalView` owned by `VMSession`.
/// All I/O wiring and the terminal delegate live on `VMSession`, so terminal state
/// (including the scroll back buffer) is fully preserved when switching between VMs.
@available(macOS 15.0, *)
struct TerminalDisplayView: NSViewRepresentable {
    let session: VMSession

    func makeNSView(context: Context) -> TerminalView {
        // The TerminalView is created by VMSession.start() and kept alive there.
        // Return a fallback empty view if called before the VM has started.
        session.terminalView ?? TerminalView(frame: .zero)
    }

    func updateNSView(_ nsView: TerminalView, context: Context) {}
}
