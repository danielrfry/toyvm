//
//  VMRunner.swift
//  ToyVMCore
//

import Foundation
import Virtualization

/// Observable VM lifecycle manager for use in GUI contexts.
/// Wraps a `VZVirtualMachine` and its delegate, publishing state changes.
@available(macOS 14.0, *)
@Observable
public class VMRunner {
    public enum State: Equatable {
        case stopped
        case starting
        case running
        case stopping
        case error(String)

        public static func == (lhs: State, rhs: State) -> Bool {
            switch (lhs, rhs) {
            case (.stopped, .stopped), (.starting, .starting),
                 (.running, .running), (.stopping, .stopping):
                return true
            case (.error(let a), .error(let b)):
                return a == b
            default:
                return false
            }
        }

        public var isRunning: Bool {
            switch self {
            case .starting, .running: return true
            default: return false
            }
        }
    }

    public private(set) var state: State = .stopped
    private var vm: VZVirtualMachine?
    private var delegate: Delegate?

    public init() {}

    /// Start the VM with the given configuration.
    /// The configuration must already include serial port attachments.
    @MainActor
    public func start(configuration: VZVirtualMachineConfiguration) async throws {
        guard state == .stopped || state == .error("") || {
            if case .error = state { return true }
            return false
        }() else {
            throw ToyVMError("VM is already running or starting")
        }

        state = .starting

        let delegate = Delegate { [weak self] in
            self?.state = .stopped
        } onError: { [weak self] error in
            self?.state = .error(error.localizedDescription)
        }
        self.delegate = delegate

        let vm = VZVirtualMachine(configuration: configuration)
        vm.delegate = delegate
        self.vm = vm

        do {
            try await vm.start()
            state = .running
        } catch {
            state = .error(error.localizedDescription)
            self.vm = nil
            self.delegate = nil
            throw error
        }
    }

    /// Request a graceful shutdown via the guest OS.
    @MainActor
    public func requestStop() throws {
        guard let vm, state == .running else {
            throw ToyVMError("VM is not running")
        }
        state = .stopping
        try vm.requestStop()
    }

    /// Force-stop the VM immediately.
    @MainActor
    public func forceStop() {
        guard let vm else { return }
        state = .stopping
        vm.stop { [weak self] error in
            if let error {
                self?.state = .error(error.localizedDescription)
            } else {
                self?.state = .stopped
            }
        }
    }

    // MARK: - Private delegate

    private class Delegate: NSObject, VZVirtualMachineDelegate {
        let onStop: () -> Void
        let onError: (Error) -> Void

        init(onStop: @escaping () -> Void, onError: @escaping (Error) -> Void) {
            self.onStop = onStop
            self.onError = onError
        }

        func guestDidStop(_ virtualMachine: VZVirtualMachine) {
            DispatchQueue.main.async { self.onStop() }
        }

        func virtualMachine(_ virtualMachine: VZVirtualMachine, didStopWithError error: Error) {
            DispatchQueue.main.async { self.onError(error) }
        }
    }
}
