//
//  DiskCreateSheet.swift
//  ToyVMApp
//

import SwiftUI
#if canImport(ToyVMCore)
import ToyVMCore
#endif

@available(macOS 15.0, *)
struct DiskCreateSheet: View {
    @Bindable var session: VMSession
    @Environment(\.dismiss) private var dismiss

    @State private var sizeText: String = "20G"
    @State private var format: DiskFormat = .raw
    @State private var readOnly: Bool = false
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
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Create") { create() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(sizeText.isEmpty || isCreating)
            }
            .padding()
        }
        .frame(minWidth: 350)
    }

    private func create() {
        isCreating = true
        errorMessage = nil

        do {
            let size = try parseSize(sizeText)
            try session.bundle.addDisk(format: format, size: size, readOnly: readOnly)
            try session.bundle.saveConfig()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            isCreating = false
        }
    }
}

#if DEBUG
@available(macOS 15.0, *)
#Preview("Create Disk") {
    DiskCreateSheet(session: PreviewFixtures.primarySession)
}
#endif
