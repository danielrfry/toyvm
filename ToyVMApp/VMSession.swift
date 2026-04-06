//
//  VMSession.swift
//  ToyVMApp
//

import AppKit
import Foundation
import Virtualization
import SwiftTerm
#if canImport(ToyVMCore)
import ToyVMCore
#endif

/// Represents the runtime state of a single VM, including its runner,
/// serial port pipes, and display mode.
@available(macOS 15.0, *)
@Observable
class VMSession {
    enum DisplayMode {
        case terminal
        case graphics
    }

    var bundle: VMBundle
    var runner: VMRunner?
    var displayMode: DisplayMode = .terminal
    var errorMessage: String?
    var automaticDisplayResize: Bool = true

    /// Terminal emulator view. Created on first terminal-mode start and kept
    /// alive for the lifetime of the session so the scroll buffer is preserved.
    private(set) var terminalView: TerminalView?

    /// Pipes are private — I/O is wired entirely within VMSession.
    private var inputPipe: Pipe?
    private var outputPipe: Pipe?

    private var startContext: VMStartContext?
    private var terminalCoordinator: TerminalCoordinator?

    init(bundle: VMBundle) {
        self.bundle = bundle
    }

    // MARK: - Lifecycle

    func reloadBundle() {
        do {
            bundle = try VMBundle.load(from: bundle.bundleURL)
        } catch {
            errorMessage = "Failed to reload bundle: \(error.localizedDescription)"
        }
    }

    @MainActor
    func start() async {
        guard runner?.state.isRunning != true else { return }

        reloadBundle()
        errorMessage = nil

        do {
            let ctx = try VirtualMachineBuilder.buildConfiguration(from: bundle)
            self.startContext = ctx

            displayMode = ctx.hasGraphicsDevice ? .graphics : .terminal

            let input = Pipe()
            let output = Pipe()
            inputPipe = input
            outputPipe = output

            if displayMode == .terminal {
                setupTerminalIfNeeded()
                // Wire the output pipe to the terminal for the lifetime of this run.
                output.fileHandleForReading.readabilityHandler = { [weak self] handle in
                    let data = handle.availableData
                    guard !data.isEmpty else { return }
                    let bytes = ArraySlice([UInt8](data))
                    DispatchQueue.main.async { self?.terminalView?.feed(byteArray: bytes) }
                }
            }

            let consoleCfg = VZVirtioConsoleDeviceSerialPortConfiguration()
            consoleCfg.attachment = VZFileHandleSerialPortAttachment(
                fileHandleForReading: input.fileHandleForReading,
                fileHandleForWriting: output.fileHandleForWriting
            )
            ctx.configuration.serialPorts = [consoleCfg]

            let runner = VMRunner()
            self.runner = runner

            try await runner.start(configuration: ctx.configuration)
        } catch {
            errorMessage = error.localizedDescription
            cleanup()
        }
    }

    @MainActor
    func requestStop() {
        do {
            try runner?.requestStop()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    func forceStop() {
        runner?.forceStop()
        cleanup()
    }

    private func cleanup() {
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        startContext?.cleanup()
        startContext = nil
        inputPipe = nil
        outputPipe = nil
    }

    // MARK: - Terminal setup

    /// Creates the TerminalView and its coordinator on first use. Subsequent
    /// calls are no-ops, preserving the existing view and its scroll buffer.
    @MainActor
    private func setupTerminalIfNeeded() {
        guard terminalView == nil else { return }

        let tv = TerminalView(frame: .zero)
        tv.configureNativeColors()
        tv.getTerminal().resize(cols: 120, rows: 40)

        let coord = TerminalCoordinator(session: self)
        tv.terminalDelegate = coord

        terminalCoordinator = coord
        terminalView = tv
    }

    // MARK: - Terminal coordinator

    /// Handles keyboard input from the terminal view and forwards it to the
    /// VM's serial input pipe. Lives on VMSession so it persists across
    /// SwiftUI view recreation.
    private class TerminalCoordinator: NSObject, TerminalViewDelegate {
        weak var session: VMSession?

        init(session: VMSession) {
            self.session = session
        }

        func send(source: TerminalView, data: ArraySlice<UInt8>) {
            session?.inputPipe?.fileHandleForWriting.write(Data(data))
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
