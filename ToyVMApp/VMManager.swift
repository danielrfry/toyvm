//
//  VMManager.swift
//  ToyVMApp
//

import Foundation
import SwiftUI
#if canImport(ToyVMCore)
import ToyVMCore
#endif

/// Discovers and manages VM bundles stored in ~/.toyvm.
@available(macOS 14.0, *)
@Observable
class VMManager {
    var bundles: [VMBundle] = []
    var sessions: [URL: VMSession] = [:]
    var selectedBundleURL: URL?
    var showCreateSheet = false
    var errorMessage: String?

    private let vmDirectory: URL

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.vmDirectory = home.appendingPathComponent(".toyvm", isDirectory: true)
        refresh()
    }

    /// Scan ~/.toyvm for .bundle directories and load them.
    func refresh() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: vmDirectory.path) else {
            bundles = []
            return
        }

        do {
            let contents = try fm.contentsOfDirectory(
                at: vmDirectory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            bundles = contents
                .filter { $0.pathExtension == "bundle" }
                .compactMap { url in
                    try? VMBundle.load(from: url)
                }
                .sorted { $0.bundleURL.lastPathComponent < $1.bundleURL.lastPathComponent }
        } catch {
            bundles = []
        }
    }

    /// Get or create a session for a VM bundle.
    func session(for bundle: VMBundle) -> VMSession {
        if let existing = sessions[bundle.bundleURL] {
            return existing
        }
        let session = VMSession(bundle: bundle)
        sessions[bundle.bundleURL] = session
        return session
    }

    /// Delete a VM bundle from disk and remove its session.
    @MainActor
    func delete(bundle: VMBundle) throws {
        let session = sessions[bundle.bundleURL]
        if session?.runner?.state.isRunning == true {
            session?.forceStop()
        }
        sessions.removeValue(forKey: bundle.bundleURL)
        try FileManager.default.removeItem(at: bundle.bundleURL)
        if selectedBundleURL == bundle.bundleURL {
            selectedBundleURL = nil
        }
        refresh()
    }

    /// Display name for a bundle (filename without .bundle extension).
    static func displayName(for bundle: VMBundle) -> String {
        let filename = bundle.bundleURL.lastPathComponent
        if filename.hasSuffix(".bundle") {
            return String(filename.dropLast(".bundle".count))
        }
        return filename
    }
}
