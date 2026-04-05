//
//  ConfigEditView.swift
//  ToyVMApp
//

import SwiftUI
#if canImport(ToyVMCore)
import ToyVMCore
#endif

@available(macOS 15.0, *)
struct ConfigEditView: View {
    @Bindable var session: VMSession
    @Environment(\.dismiss) private var dismiss

    @State private var cpus: Int
    @State private var memoryGB: Int
    @State private var audio: Bool
    @State private var network: Bool
    @State private var rosetta: Bool
    @State private var kernelCommandLine: String
    @State private var bootMode: BootMode
    @State private var usbDisks: [USBDiskConfig]
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
        _bootMode = State(initialValue: config.bootMode)
        _usbDisks = State(initialValue: config.usbDisks)
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
                    if session.bundle.config.bootMode == .macOS {
                        LabeledContent("Boot Mode", value: "macOS")
                    } else {
                        Picker("Boot Mode", selection: $bootMode) {
                            ForEach(BootMode.allCases.filter({ $0 != .macOS }), id: \.self) { mode in
                                Text(mode.label).tag(mode)
                            }
                        }
                        if let kernel = session.bundle.config.kernel {
                            LabeledContent("Kernel", value: kernel)
                        }
                        if let initrd = session.bundle.config.initrd {
                            LabeledContent("Initrd", value: initrd)
                        }
                        if bootMode == .linux {
                            TextField("Kernel Command Line", text: $kernelCommandLine)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
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

                Section("USB Disks") {
                    if usbDisks.isEmpty {
                        Text("No USB disks configured")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(usbDisks.enumerated()), id: \.offset) { idx, usbDisk in
                            LabeledContent(URL(fileURLWithPath: usbDisk.path).lastPathComponent) {
                                HStack {
                                    Text(usbDisk.readOnly ? "read-only" : "read/write")
                                    Button(role: .destructive) {
                                        usbDisks.remove(at: idx)
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                    .buttonStyle(.borderless)
                                }
                            }
                        }
                    }
                    Button("Add USB Disk…") {
                        chooseFile(title: "Select ISO or Disk Image") { url in
                            usbDisks.append(USBDiskConfig(path: url.path, readOnly: true))
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
            session.bundle.config.bootMode = bootMode
            session.bundle.config.usbDisks = usbDisks

            if bootMode == .linux {
                let args = kernelCommandLine.trimmingCharacters(in: .whitespacesAndNewlines)
                session.bundle.config.kernelCommandLine = args.isEmpty
                    ? ["console=hvc0"]
                    : args.components(separatedBy: " ").filter { !$0.isEmpty }
            }

            try session.bundle.saveConfig()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func chooseFile(title: String, completion: @escaping (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.title = title
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        if panel.runModal() == .OK, let url = panel.url {
            completion(url)
        }
    }
}
