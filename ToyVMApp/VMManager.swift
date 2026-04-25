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
@available(macOS 15.0, *)
@Observable
class VMManager {
    var bundles: [VMBundle] = []
    var sessions: [URL: VMSession] = [:]
    var selectedBundleURL: URL?
    var showCreateSheet = false
    var errorMessage: String?

    private let vmDirectory: URL
    private var directoryMonitorSource: DispatchSourceFileSystemObject?
    private var directoryMonitorFD: Int32 = -1

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.vmDirectory = home.appendingPathComponent(".toyvm", isDirectory: true)
        refresh()
        startDirectoryMonitor()
    }

#if DEBUG
    init(
        previewBundles: [VMBundle],
        selectedBundleURL: URL? = nil,
        sessions: [URL: VMSession] = [:]
    ) {
        self.vmDirectory = URL(fileURLWithPath: "/preview/toyvm-manager", isDirectory: true)
        self.bundles = previewBundles
        self.sessions = sessions
        self.selectedBundleURL = selectedBundleURL ?? previewBundles.first?.bundleURL
    }
#endif

    deinit {
        stopDirectoryMonitor()
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
        NSWorkspace.shared.recycle([bundle.bundleURL])
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

    // MARK: - Directory Monitoring

    private func startDirectoryMonitor() {
        let fm = FileManager.default
        // Ensure the directory exists
        if !fm.fileExists(atPath: vmDirectory.path) {
            try? fm.createDirectory(at: vmDirectory, withIntermediateDirectories: true)
        }

        let fd = open(vmDirectory.path, O_EVTONLY)
        guard fd >= 0 else { return }
        directoryMonitorFD = fd

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            self?.refresh()
        }
        source.setCancelHandler { [weak self] in
            if let fd = self?.directoryMonitorFD, fd >= 0 {
                close(fd)
                self?.directoryMonitorFD = -1
            }
        }
        source.resume()
        directoryMonitorSource = source
    }

    private func stopDirectoryMonitor() {
        directoryMonitorSource?.cancel()
        directoryMonitorSource = nil
    }
}
