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
                    .disabled(sizeText.isEmpty || locationURL == nil || isCreating || (initialise && volumeLabel.isEmpty))
            }
            .padding()
        }
        .frame(minWidth: 400)
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

        Task {
            do {
                let size = try parseSize(sizeText)
                try createDisk(at: url, size: size, format: format)

                if initialise {
                    try initialiseDisk(at: url, volumeLabel: volumeLabel.isEmpty ? "Data" : volumeLabel)
                }

                try await session.attachUSBDisk(url: url, readOnly: readOnly)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isCreating = false
            }
        }
    }
}
