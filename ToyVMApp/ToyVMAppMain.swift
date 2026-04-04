//
//  ToyVMAppMain.swift
//  ToyVMApp
//

import SwiftUI

@available(macOS 14.0, *)
@main
struct ToyVMAppMain: App {
    @State private var manager = VMManager()

    var body: some Scene {
        WindowGroup {
            ContentView(manager: manager)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Virtual Machine…") {
                    manager.showCreateSheet = true
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }
    }
}
