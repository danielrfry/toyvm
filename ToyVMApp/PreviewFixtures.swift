//
//  PreviewFixtures.swift
//  ToyVMApp
//

import Foundation
import SwiftUI
#if canImport(ToyVMCore)
import ToyVMCore
#endif

#if DEBUG
@available(macOS 15.0, *)
enum PreviewFixtures {
    static let primaryBundle = makeBundle(
        name: "Preview Linux",
        bootMode: .linux,
        sharePath: "/preview/shares/linux",
        usbDiskPath: "/preview/media/linux.iso"
    )

    static let secondaryBundle = makeBundle(
        name: "Preview EFI",
        bootMode: .efi,
        sharePath: "/preview/shares/efi",
        usbDiskPath: "/preview/media/efi.iso"
    )

    static let primarySession = VMSession(bundle: primaryBundle)
    static let secondarySession = VMSession(bundle: secondaryBundle)

    static let manager: VMManager = {
        VMManager(
            previewBundles: [primaryBundle, secondaryBundle],
            selectedBundleURL: primaryBundle.bundleURL,
            sessions: [
                primaryBundle.bundleURL: primarySession,
                secondaryBundle.bundleURL: secondarySession,
            ]
        )
    }()

    static func emptyManager() -> VMManager {
        VMManager(previewBundles: [])
    }

    static func session(for bundle: VMBundle = primaryBundle) -> VMSession {
        VMSession(bundle: bundle)
    }

    #if arch(arm64)
    static func installManager(
        state: MacOSInstallManager.State,
        progress: Double = 0.5
    ) -> MacOSInstallManager {
        let manager = MacOSInstallManager()
        manager.state = state
        manager.installProgress = progress
        return manager
    }
    #endif

    private static func makeBundle(
        name: String,
        bootMode: BootMode,
        sharePath: String,
        usbDiskPath: String
    ) -> VMBundle {
        let fm = FileManager.default
        let rootURL = fm.temporaryDirectory
            .appendingPathComponent("ToyVMPreview", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fixturesURL = rootURL.appendingPathComponent("fixtures", isDirectory: true)
        let bundleURL = rootURL.appendingPathComponent("\(name.replacingOccurrences(of: " ", with: "-")).bundle", isDirectory: true)

        do {
            try fm.createDirectory(at: fixturesURL, withIntermediateDirectories: true)

            let kernelURL = fixturesURL.appendingPathComponent("vmlinuz")
            let initrdURL = fixturesURL.appendingPathComponent("initrd.img")
            try Data("preview-kernel".utf8).write(to: kernelURL)
            try Data("preview-initrd".utf8).write(to: initrdURL)

            var options = CreateOptions()
            options.cpus = 4
            options.memoryGB = 8
            options.audio = true
            options.network = true
            options.rosetta = false
            options.bootMode = bootMode
            options.kernelCommandLine = ["console=hvc0", "quiet"]
            options.shares = [
                ShareConfig(tag: "code", path: sharePath, readOnly: false),
            ]
            options.usbDisks = [
                USBDiskConfig(path: usbDiskPath, readOnly: true),
            ]

            var bundle = try VMBundle.create(
                at: bundleURL,
                kernelPath: bootMode == .linux ? kernelURL : nil,
                initrdPath: bootMode == .linux ? initrdURL : nil,
                options: options
            )

            if bootMode == .linux {
                try? bundle.createBranch(named: "sandbox", from: "main")
                try? bundle.selectBranch(named: "main")
            }

            return bundle
        } catch {
            fatalError("Failed to create preview bundle: \(error)")
        }
    }
}
#endif
