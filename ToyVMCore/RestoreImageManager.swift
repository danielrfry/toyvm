//
//  RestoreImageManager.swift
//  ToyVMCore
//

import Foundation
import Virtualization

/// Manages downloading macOS restore images (.ipsw) from Apple with progress tracking.
#if arch(arm64)
@available(macOS 14.0, *)
@Observable
public class RestoreImageManager: @unchecked Sendable {
    public enum State: Sendable {
        case idle
        case fetching
        case downloading
        case completed(URL)
        case failed(String)
    }

    public var state: State = .idle
    public var downloadProgress: Double = 0

    private var downloadTask: URLSessionDownloadTask?
    private var progressDelegate: DownloadProgressDelegate?

    public init() {}

    /// Fetches the URL for the latest supported macOS restore image from Apple.
    public func fetchLatestImageInfo() async throws -> (url: URL, buildVersion: String) {
        let image = try await VZMacOSRestoreImage.latestSupported
        return (url: image.url, buildVersion: image.buildVersion)
    }

    /// Downloads the latest restore image to the specified destination URL.
    /// Updates `state` and `downloadProgress` throughout the operation.
    @MainActor
    public func downloadLatest(to destination: URL) async throws {
        state = .fetching
        downloadProgress = 0

        do {
            let (url, _) = try await fetchLatestImageInfo()
            state = .downloading

            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let delegate = DownloadProgressDelegate(
                    destination: destination,
                    onProgress: { [weak self] fraction in
                        Task { @MainActor [weak self] in
                            self?.downloadProgress = fraction
                        }
                    },
                    onComplete: { [weak self] result in
                        Task { @MainActor [weak self] in
                            switch result {
                            case .success:
                                self?.state = .completed(destination)
                                continuation.resume()
                            case .failure(let error):
                                if (error as NSError).code == NSURLErrorCancelled {
                                    self?.state = .idle
                                    continuation.resume(throwing: CancellationError())
                                } else {
                                    self?.state = .failed(error.localizedDescription)
                                    continuation.resume(throwing: error)
                                }
                            }
                        }
                    }
                )
                self.progressDelegate = delegate
                let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
                let task = session.downloadTask(with: url)
                self.downloadTask = task
                task.resume()
            }
        } catch is CancellationError {
            // Cancelled by user — state already set to .idle
        } catch {
            state = .failed(error.localizedDescription)
            throw error
        }
    }

    /// Cancels an in-progress download.
    public func cancel() {
        downloadTask?.cancel()
        downloadTask = nil
        progressDelegate = nil
        state = .idle
        downloadProgress = 0
    }
}

@available(macOS 14.0, *)
private class DownloadProgressDelegate: NSObject, URLSessionDownloadDelegate {
    let destination: URL
    let onProgress: @Sendable (Double) -> Void
    let onComplete: @Sendable (Result<Void, Error>) -> Void

    init(
        destination: URL,
        onProgress: @escaping @Sendable (Double) -> Void,
        onComplete: @escaping @Sendable (Result<Void, Error>) -> Void
    ) {
        self.destination = destination
        self.onProgress = onProgress
        self.onComplete = onComplete
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        do {
            let fm = FileManager.default
            if fm.fileExists(atPath: destination.path) {
                try fm.removeItem(at: destination)
            }
            try fm.moveItem(at: location, to: destination)
            onComplete(.success(()))
        } catch {
            onComplete(.failure(error))
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let fraction = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        onProgress(fraction)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            onComplete(.failure(error))
        }
    }
}
#endif
