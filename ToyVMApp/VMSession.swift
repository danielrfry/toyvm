//
//  VMSession.swift
//  ToyVMApp
//

import Foundation
import Virtualization
#if canImport(ToyVMCore)
import ToyVMCore
#endif

/// Represents the runtime state of a single VM, including its runner,
/// serial port pipes, and display mode.
@available(macOS 15.0, *)
@Observable
class VMSession: Identifiable {
    enum DisplayMode {
        case terminal
        case graphics
    }

    var bundle: VMBundle
    var runner: VMRunner?
    var displayMode: DisplayMode = .terminal
    var errorMessage: String?
    var automaticDisplayResize: Bool = true

    /// Pipes connecting the VM serial port to the terminal emulator.
    /// inputPipe: terminal → VM; outputPipe: VM → terminal.
    /// Exposed read-only so TerminalDisplayView can wire its readabilityHandler.
    private(set) var inputPipe: Pipe?
    private(set) var outputPipe: Pipe?

    /// Stable identity for SwiftUI ForEach.
    var id: URL { bundle.bundleURL }

    private var startContext: VMStartContext?

    init(bundle: VMBundle) {
        self.bundle = bundle
    }

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
        startContext?.cleanup()
        startContext = nil
        inputPipe = nil
        outputPipe = nil
    }
}
