//
//  ShareEditSheet.swift
//  ToyVMApp
//

import SwiftUI
import AppKit
#if canImport(ToyVMCore)
import ToyVMCore
#endif

@available(macOS 15.0, *)
struct ShareEditSheet: View {
    @Bindable var session: VMSession
    let existing: ShareConfig?
    let onDismiss: () -> Void

    @State private var tag: String = ""
    @State private var path: String = ""
    @State private var readOnly: Bool = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    private var isEditing: Bool { existing != nil }

    private var isValid: Bool {
        !tag.isEmpty && !path.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                TextField("Tag:", text: $tag)
                    .help("Mount tag used by the guest OS to identify this share")

                HStack {
                    TextField("Path:", text: $path)
                        .truncationMode(.middle)
                    Button("Browse…") { browseForDirectory() }
                }

                Toggle("Read-only", isOn: $readOnly)
            }
            .formStyle(.grouped)
            .padding()

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.caption)
                    .padding(.horizontal)
            }

            Divider()

            HStack {
                Button("Cancel") {
                    onDismiss()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Spacer()
                Button(isEditing ? "Save" : "Add") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
            }
            .padding()
        }
        .frame(minWidth: 400)
        .onAppear {
            if let existing {
                tag = existing.tag
                path = existing.path
                readOnly = existing.readOnly
            }
        }
    }

    private func browseForDirectory() {
        let panel = NSOpenPanel()
        panel.title = "Select Directory to Share"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if !path.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: path)
        }

        guard panel.runModal() == .OK, let url = panel.url else { return }
        path = url.path
        if tag.isEmpty {
            tag = url.lastPathComponent
        }
    }

    private func save() {
        // If editing and the tag changed, remove the old entry first
        if let existing, existing.tag != tag {
            do {
                try session.bundle.removeShare(tag: existing.tag)
            } catch {
                errorMessage = error.localizedDescription
                return
            }
        }

        let share = ShareConfig(tag: tag, path: path, readOnly: readOnly)
        session.bundle.addShare(share)

        do {
            try session.bundle.saveConfig()
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        session.updateRuntimeShares()

        onDismiss()
        dismiss()
    }
}

#if DEBUG
@available(macOS 15.0, *)
#Preview("Add Share") {
    ShareEditSheet(session: PreviewFixtures.primarySession, existing: nil) {}
}
#endif
