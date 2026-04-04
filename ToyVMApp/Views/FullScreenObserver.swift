//
//  FullScreenObserver.swift
//  ToyVMApp
//

import AppKit
import SwiftUI

/// Monitors the full screen state of the hosting window via NSWindow notifications.
@available(macOS 14.0, *)
@Observable
final class FullScreenObserver {
    var isFullScreen = false

    private var observers: [NSObjectProtocol] = []

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func observe(window: NSWindow) {
        // Remove any previous observers
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()

        isFullScreen = window.styleMask.contains(.fullScreen)

        observers.append(NotificationCenter.default.addObserver(
            forName: NSWindow.didEnterFullScreenNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.isFullScreen = true
        })

        observers.append(NotificationCenter.default.addObserver(
            forName: NSWindow.didExitFullScreenNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.isFullScreen = false
        })
    }
}

/// A view modifier that finds the hosting NSWindow and feeds its full screen
/// state into a binding.
@available(macOS 14.0, *)
struct FullScreenTracker: NSViewRepresentable {
    let observer: FullScreenObserver

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        // Defer window lookup to the next run loop tick so the view is in the hierarchy
        DispatchQueue.main.async {
            if let window = view.window {
                observer.observe(window: window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let window = nsView.window {
            observer.observe(window: window)
        }
    }
}
