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
@available(macOS 14.0, *)
@Observable
class VMSession {
    enum DisplayMode {
        case terminal
        case graphics  // Future: VZVirtualMachineView
    }

    var bundle: VMBundle
    var runner: VMRunner?
    var displayMode: DisplayMode = .terminal
    var errorMessage: String?

    /// Pipe pair connecting the VM serial port to the terminal emulator.
    /// inputPipe: terminal writes → VM reads
    /// outputPipe: VM writes → terminal reads
    private(set) var inputPipe: Pipe?
    private(set) var outputPipe: Pipe?

    private var startContext: VMStartContext?

    init(bundle: VMBundle) {
        self.bundle = bundle
    }

    /// Reload bundle configuration from disk.
    func reloadBundle() {
        do {
            bundle = try VMBundle.load(from: bundle.bundleURL)
        } catch {
            errorMessage = "Failed to reload bundle: \(error.localizedDescription)"
        }
    }

    /// Start the VM using the bundle's active branch configuration.
    @MainActor
    func start() async {
        guard runner?.state.isRunning != true else { return }

        reloadBundle()
        errorMessage = nil

        do {
            let ctx = try VirtualMachineBuilder.buildConfiguration(from: bundle)
            self.startContext = ctx

            // Determine display mode from boot configuration
            displayMode = ctx.hasGraphicsDevice ? .graphics : .terminal

            // Create pipe pair for serial ↔ terminal
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

    /// Request graceful shutdown.
    @MainActor
    func requestStop() {
        do {
            try runner?.requestStop()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Force-stop the VM immediately.
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
