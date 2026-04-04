//
//  VMDisplayView.swift
//  ToyVMApp
//

import SwiftUI

/// Abstraction layer for VM display. Routes to terminal emulator for
/// Linux boot mode or VZVirtualMachineView for EFI/graphical boot mode.
@available(macOS 14.0, *)
struct VMDisplayView: View {
    let session: VMSession

    var body: some View {
        switch session.displayMode {
        case .terminal:
            TerminalDisplayView(session: session)
        case .graphics:
            GraphicsDisplayView(session: session)
        }
    }
}
