//
//  VMDisplayView.swift
//  ToyVMApp
//

import SwiftUI

/// Abstraction layer for VM display. Currently shows the terminal emulator;
/// in future, can switch to VZVirtualMachineView for graphical guests.
@available(macOS 14.0, *)
struct VMDisplayView: View {
    let session: VMSession

    var body: some View {
        switch session.displayMode {
        case .terminal:
            TerminalDisplayView(session: session)
        case .graphics:
            ContentUnavailableView(
                "Graphics Display",
                systemImage: "display",
                description: Text("Graphical display support is not yet implemented. Use terminal mode for now.")
            )
        }
    }
}
