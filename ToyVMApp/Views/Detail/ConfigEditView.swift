//
//  ConfigEditView.swift
//  ToyVMApp
//

import SwiftUI
#if canImport(ToyVMCore)
import ToyVMCore
#endif

@available(macOS 14.0, *)
struct ConfigEditView: View {
    @Bindable var session: VMSession
    @Environment(\.dismiss) private var dismiss

    @State private var cpus: Int
    @State private var memoryGB: Int
    @State private var audio: Bool
    @State private var network: Bool
    @State private var rosetta: Bool
    @State private var kernelCommandLine: String
    @State private var errorMessage: String?

    init(session: VMSession) {
        self.session = session
        let config = session.bundle.config
        _cpus = State(initialValue: config.cpus)
        _memoryGB = State(initialValue: config.memoryGB)
        _audio = State(initialValue: config.audio)
        _network = State(initialValue: config.network)
        _rosetta = State(initialValue: config.rosetta)
        _kernelCommandLine = State(initialValue: config.kernelCommandLine.joined(separator: " "))
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Resources") {
                    Stepper("CPUs: \(cpus)", value: $cpus, in: 1...64)
                    Stepper("Memory: \(memoryGB) GB", value: $memoryGB, in: 1...256)
                }

                Section("Devices") {
                    Toggle("Network", isOn: $network)
                    Toggle("Audio", isOn: $audio)
                    #if arch(arm64)
                    Toggle("Rosetta", isOn: $rosetta)
                    #endif
                }

                Section("Boot") {
                    LabeledContent("Kernel", value: session.bundle.config.kernel)
                    if let initrd = session.bundle.config.initrd {
                        LabeledContent("Initrd", value: initrd)
                    }
                    TextField("Kernel Command Line", text: $kernelCommandLine)
                        .textFieldStyle(.roundedBorder)
                }

                if !session.bundle.config.disks.isEmpty {
                    Section("Disks") {
                        ForEach(session.bundle.config.disks, id: \.file) { disk in
                            LabeledContent(disk.file) {
                                Text("\(disk.format.rawValue), \(disk.readOnly ? "ro" : "rw")")
                            }
                        }
                    }
                }

                if !session.bundle.config.shares.isEmpty {
                    Section("Directory Shares") {
                        ForEach(session.bundle.config.shares, id: \.tag) { share in
                            LabeledContent(share.tag) {
                                Text("\(share.path) (\(share.readOnly ? "ro" : "rw"))")
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(minWidth: 450, minHeight: 400)
    }

    private func save() {
        do {
            session.bundle.config.cpus = cpus
            session.bundle.config.memoryGB = memoryGB
            session.bundle.config.audio = audio
            session.bundle.config.network = network
            session.bundle.config.rosetta = rosetta

            let args = kernelCommandLine.trimmingCharacters(in: .whitespacesAndNewlines)
            session.bundle.config.kernelCommandLine = args.isEmpty
                ? ["console=hvc0"]
                : args.components(separatedBy: " ").filter { !$0.isEmpty }

            try session.bundle.saveConfig()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
