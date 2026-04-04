//
//  MacOSInstallManager.swift
//  ToyVMCore
//

import Foundation
import Virtualization

/// Manages the macOS guest installation lifecycle: loading a restore image,
/// extracting hardware requirements, saving artifacts to a VM bundle, and
/// running VZMacOSInstaller with progress tracking.
#if arch(arm64)
@available(macOS 14.0, *)
@Observable
public class MacOSInstallManager: @unchecked Sendable {
    public enum State: Sendable {
        case idle
        case loadingImage
        case preparingVM
        case installing
        case completed
        case failed(String)
    }

    public var state: State = .idle
    public var installProgress: Double = 0

    private var progressObservation: NSKeyValueObservation?
    private var installTask: Task<Void, Error>?

    public init() {}

    /// Runs the full macOS installation into the given VM bundle.
    ///
    /// 1. Loads the restore image and extracts hardware requirements
    /// 2. Saves hardware model + machine identifier to the bundle
    /// 3. Creates auxiliary storage
    /// 4. Builds a VM configuration and starts the VM
    /// 5. Runs VZMacOSInstaller
    /// 6. Stops the VM on completion
    @MainActor
    public func install(bundle: inout VMBundle, restoreImageURL: URL) async throws {
        state = .loadingImage
        installProgress = 0

        // 1. Load restore image
        let restoreImage = try await VZMacOSRestoreImage.image(from: restoreImageURL)

        guard let requirements = restoreImage.mostFeaturefulSupportedConfiguration else {
            throw ToyVMError("This Mac does not support the macOS version in the restore image")
        }

        guard requirements.hardwareModel.isSupported else {
            throw ToyVMError("The hardware model from the restore image is not supported on this Mac")
        }

        // 2. Save artifacts to bundle
        state = .preparingVM

        let hardwareModel = requirements.hardwareModel
        let machineIdentifier = VZMacMachineIdentifier()

        try bundle.saveMacOSArtifacts(
            hardwareModel: hardwareModel.dataRepresentation,
            machineIdentifier: machineIdentifier.dataRepresentation
        )

        // Enforce minimum CPU/memory from restore image requirements
        let minCPU = requirements.minimumSupportedCPUCount
        let minMem = requirements.minimumSupportedMemorySize
        let effectiveCPUs = max(bundle.config.cpus, minCPU)
        let effectiveMemory = max(UInt64(bundle.config.memoryGB) * 1024 * 1024 * 1024, minMem)

        // 3. Create auxiliary storage (keep the object — do NOT re-read from URL)
        let auxStorage = try VZMacAuxiliaryStorage(
            creatingStorageAt: bundle.auxiliaryStorageURL,
            hardwareModel: hardwareModel,
            options: [.allowOverwrite]
        )

        // 4. Build VM configuration
        let diskPaths = bundle.config.disks.map { disk in
            (url: bundle.config.diskURL(in: bundle.activeBranchURL, disk: disk), readOnly: disk.readOnly)
        }

        let ctx = try VirtualMachineBuilder.buildMacOSConfiguration(
            hardwareModelData: hardwareModel.dataRepresentation,
            machineIdentifierData: machineIdentifier.dataRepresentation,
            auxiliaryStorage: auxStorage,
            cpuCount: effectiveCPUs,
            memoryGB: Int(effectiveMemory / (1024 * 1024 * 1024)),
            enableNetwork: bundle.config.network,
            enableAudio: bundle.config.audio,
            diskPaths: diskPaths,
            shares: bundle.config.shares,
            usbDisks: bundle.config.usbDisks
        )

        // 5. Install macOS
        state = .installing

        let vm = VZVirtualMachine(configuration: ctx.configuration)
        let installer = VZMacOSInstaller(virtualMachine: vm, restoringFromImageAt: restoreImageURL)

        progressObservation = installer.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
            Task { @MainActor [weak self] in
                self?.installProgress = progress.fractionCompleted
            }
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            installer.install { result in
                switch result {
                case .success:
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }

        progressObservation = nil

        state = .completed
        installProgress = 1.0
    }

    /// Cancels an in-progress installation.
    public func cancel() {
        installTask?.cancel()
        installTask = nil
        progressObservation = nil
        state = .idle
        installProgress = 0
    }
}
#endif
