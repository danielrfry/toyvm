//
//  TerminalDisplayView.swift
//  ToyVMApp
//

import SwiftUI
import SwiftTerm
#if canImport(ToyVMCore)
import ToyVMCore
#endif

/// Wraps SwiftTerm's `TerminalView` (AppKit NSView) for use in SwiftUI.
/// Connects to a VMSession's serial port pipe pair for bidirectional I/O.
@available(macOS 15.0, *)
struct TerminalDisplayView: NSViewRepresentable {
    let session: VMSession

    func makeNSView(context: Context) -> TerminalView {
        let termView = TerminalView(frame: .zero)
        termView.terminalDelegate = context.coordinator
        termView.configureNativeColors()

        let terminal = termView.getTerminal()
        terminal.resize(cols: 120, rows: 40)

        context.coordinator.terminalView = termView
        context.coordinator.connectPipes(
            input: session.inputPipe,
            output: session.outputPipe
        )

        return termView
    }

    func updateNSView(_ nsView: TerminalView, context: Context) {
        // Reconnect if session pipes changed (e.g. VM restarted)
        context.coordinator.connectPipes(
            input: session.inputPipe,
            output: session.outputPipe
        )
    }

    static func dismantleNSView(_ nsView: TerminalView, coordinator: Coordinator) {
        coordinator.disconnect()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject, TerminalViewDelegate {
        weak var terminalView: TerminalView?
        private weak var connectedInputPipe: Pipe?
        private weak var connectedOutputPipe: Pipe?

        func connectPipes(input: Pipe?, output: Pipe?) {
            guard output !== connectedOutputPipe else { return }

            disconnect()

            connectedInputPipe = input
            connectedOutputPipe = output

            output?.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                let bytes = ArraySlice([UInt8](data))
                DispatchQueue.main.async {
                    self?.terminalView?.feed(byteArray: bytes)
                }
            }
        }

        func disconnect() {
            connectedOutputPipe?.fileHandleForReading.readabilityHandler = nil
            connectedOutputPipe = nil
            connectedInputPipe = nil
        }

        deinit {
            disconnect()
        }

        // MARK: - TerminalViewDelegate

        func send(source: TerminalView, data: ArraySlice<UInt8>) {
            connectedInputPipe?.fileHandleForWriting.write(Data(data))
        }

        func scrolled(source: TerminalView, position: Double) {}
        func setTerminalTitle(source: TerminalView, title: String) {}
        func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
        func clipboardCopy(source: TerminalView, content: Data) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setData(content, forType: .string)
        }
        func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
    }
}
