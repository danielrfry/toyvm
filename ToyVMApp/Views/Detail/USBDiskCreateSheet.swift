//
//  USBDiskCreateSheet.swift
//  ToyVMApp
//

import SwiftUI
import AppKit
#if canImport(ToyVMCore)
import ToyVMCore
#endif

@available(macOS 15.0, *)
struct USBDiskCreateSheet: View {
    @Bindable var session: VMSession
    @Environment(\.dismiss) private var dismiss

    @State private var sizeText: String = "20G"
    @State private var format: DiskFormat = .raw
    @State private var initialise: Bool = false
    @State private var volumeLabel: String = "Data"
    @State private var readOnly: Bool = false
    @State private var locationURL: URL?
    @State private var errorMessage: String?
    @State private var isCreating = false

    var body: some View {
        VStack(spacing: 0) {
            Form {
                TextField("Size:", text: $sizeText)
                    .help("e.g. 512M, 20G, 1T")

                Picker("Format:", selection: $format) {
                    Text("Raw (.img)").tag(DiskFormat.raw)
                    Text("ASIF (.asif)").tag(DiskFormat.asif)
                }

                HStack {
                    if let locationURL {
                        Text(locationURL.path)
                            .truncationMode(.middle)
                            .lineLimit(1)
                    } else {
                        Text("No location selected")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Choose…") { chooseLocation() }
                }

                Toggle("Initialise (GPT + ExFAT)", isOn: $initialise)
                    .help("Format the disk with a GPT partition scheme and ExFAT filesystem")

                if initialise {
                    TextField("Volume label:", text: $volumeLabel)
                    if let err = volumeLabelError {
                        Text(err).foregroundStyle(.red).font(.caption)
                    }
                }

                Toggle("Read-only", isOn: $readOnly)
            }
            .formStyle(.grouped)
            .padding()

            if isCreating {
                ProgressView("Creating disk image…")
                    .padding(.horizontal)
            }

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.caption)
                    .padding(.horizontal)
            }

            Divider()

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Create") { performCreate() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(sizeText.isEmpty || locationURL == nil || isCreating || volumeLabelError != nil)
            }
            .padding()
        }
        .frame(minWidth: 400)
    }

    private var volumeLabelError: String? {
        guard initialise else { return nil }
        return exFATVolumeLabelError(volumeLabel)
    }

    private func chooseLocation() {
        let panel = NSSavePanel()
        panel.title = "Save Disk Image"
        panel.nameFieldStringValue = "disk.\(format.fileExtension)"
        panel.allowedContentTypes = []
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }
        locationURL = url
    }

    private func performCreate() {
        guard let url = locationURL else { return }
        isCreating = true
        errorMessage = nil

        let isRunning = session.runner?.state.isRunning == true

        Task {
            do {
                let size = try parseSize(sizeText)
                try createDisk(at: url, size: size, format: format)
                do {
                    if initialise {
                        try initialiseDisk(at: url, volumeLabel: volumeLabel)
                    }
                    if isRunning {
                        try await session.attachUSBDisk(url: url, readOnly: readOnly)
                    } else {
                        try session.addUSBDiskToConfig(url: url, readOnly: readOnly)
                    }
                } catch {
                    try? FileManager.default.removeItem(at: url)
                    throw error
                }
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isCreating = false
            }
        }
    }
}

#if DEBUG
@available(macOS 15.0, *)
#Preview("Create USB Disk") {
    USBDiskCreateSheet(session: PreviewFixtures.primarySession)
}
#endif
