//
//  GraphicsDisplayView.swift
//  ToyVMApp
//

import SwiftUI
import Virtualization
#if canImport(ToyVMCore)
import ToyVMCore
#endif

/// NSViewRepresentable wrapping `VZVirtualMachineView` for graphical VM display.
@available(macOS 14.0, *)
struct GraphicsDisplayView: NSViewRepresentable {
    let session: VMSession

    func makeNSView(context: Context) -> VZVirtualMachineView {
        let view = VZVirtualMachineView()
        view.capturesSystemKeys = true
        view.virtualMachine = session.runner?.virtualMachine
        return view
    }

    func updateNSView(_ nsView: VZVirtualMachineView, context: Context) {
        nsView.virtualMachine = session.runner?.virtualMachine
    }
}
