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

    /// A USB mass storage device attached at runtime (not persisted in VM config).
    struct AttachedUSBDevice: Identifiable {
        let id = UUID()
        let url: URL
        let readOnly: Bool
        let device: VZUSBMassStorageDevice

        var filename: String { url.lastPathComponent }
    }

    var bundle: VMBundle
    var runner: VMRunner?
    var displayMode: DisplayMode = .terminal
    var errorMessage: String?
    var automaticDisplayResize: Bool = true
    var attachedUSBDevices: [AttachedUSBDevice] = []

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

    // MARK: - USB hot-plug

    @MainActor
    func attachUSBDisk(url: URL, readOnly: Bool) async throws {
        guard let vm = runner?.virtualMachine,
              let controller = vm.usbControllers.first else {
            throw ToyVMError("No USB controller available")
        }

        let attachment = try VZDiskImageStorageDeviceAttachment(url: url, readOnly: readOnly)
        let config = VZUSBMassStorageDeviceConfiguration(attachment: attachment)
        let device = VZUSBMassStorageDevice(configuration: config)

        try await controller.attach(device: device)
        attachedUSBDevices.append(AttachedUSBDevice(url: url, readOnly: readOnly, device: device))
    }

    @MainActor
    func detachUSBDevice(id: UUID) async throws {
        guard let index = attachedUSBDevices.firstIndex(where: { $0.id == id }) else { return }
        guard let vm = runner?.virtualMachine,
              let controller = vm.usbControllers.first else {
            throw ToyVMError("No USB controller available")
        }

        let entry = attachedUSBDevices[index]
        try await controller.detach(device: entry.device)
        attachedUSBDevices.remove(at: index)
    }

    private func cleanup() {
        startContext?.cleanup()
        startContext = nil
        inputPipe = nil
        outputPipe = nil
        attachedUSBDevices = []
    }
}
