//
//  TerminalDisplayView.swift
//  ToyVMApp
//

import AppKit
import SwiftUI
import SwiftTerm
#if canImport(ToyVMCore)
import ToyVMCore
#endif

/// Wraps SwiftTerm's `TerminalView` for use in SwiftUI.
/// Intended for use inside `TerminalLayerView`, which keeps one instance per session
/// permanently in the view hierarchy so the scroll buffer is never lost.
@available(macOS 15.0, *)
struct TerminalDisplayView: NSViewRepresentable {
    let session: VMSession

    func makeNSView(context: Context) -> TerminalView {
        let tv = TerminalView(frame: .zero)
        tv.configureNativeColors()
        tv.getTerminal().resize(cols: 120, rows: 40)
        tv.terminalDelegate = context.coordinator
        context.coordinator.terminalView = tv
        return tv
    }

    func updateNSView(_ nsView: TerminalView, context: Context) {
        context.coordinator.connectPipes(input: session.inputPipe, output: session.outputPipe)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator: NSObject, TerminalViewDelegate {
        weak var terminalView: TerminalView?
        private var connectedInput: Pipe?
        private var connectedOutput: Pipe?

        /// Connect to a new pipe pair. Disconnects the previous pair first.
        /// Guards against redundant reconnects using object identity.
        func connectPipes(input: Pipe?, output: Pipe?) {
            guard output !== connectedOutput else { return }

            connectedOutput?.fileHandleForReading.readabilityHandler = nil
            connectedInput = input
            connectedOutput = output

            output?.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty else {
                    // EOF: write end of pipe closed (VM stopped). Self-disconnect.
                    handle.readabilityHandler = nil
                    return
                }
                let bytes = ArraySlice([UInt8](data))
                DispatchQueue.main.async { self?.terminalView?.feed(byteArray: bytes) }
            }
        }

        // MARK: - TerminalViewDelegate

        func send(source: TerminalView, data: ArraySlice<UInt8>) {
            connectedInput?.fileHandleForWriting.write(Data(data))
        }

        func clipboardCopy(source: TerminalView, content: Data) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setData(content, forType: .string)
        }

        func scrolled(source: TerminalView, position: Double) {}
        func setTerminalTitle(source: TerminalView, title: String) {}
        func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
        func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
    }
}
