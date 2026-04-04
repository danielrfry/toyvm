//
//  CreateVMView.swift
//  ToyVMApp
//

import SwiftUI
import ToyVMCore

@available(macOS 14.0, *)
struct CreateVMView: View {
    @Bindable var manager: VMManager
    @Environment(\.dismiss) private var dismiss

    @State private var vmName = ""
    @State private var kernelPath = ""
    @State private var initrdPath = ""
    @State private var cpus = 2
    @State private var memoryGB = 2
    @State private var diskSizeText = "20G"
    @State private var audio = false
    @State private var network = true
    @State private var rosetta = false
    @State private var errorMessage: String?
    @State private var isCreating = false

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("General") {
                    TextField("Name", text: $vmName)
                        .textFieldStyle(.roundedBorder)
                }

                Section("Boot Images") {
                    HStack {
                        TextField("Kernel", text: $kernelPath)
                            .textFieldStyle(.roundedBorder)
                        Button("Browse…") {
                            chooseFile(title: "Select Kernel Image") { url in
                                kernelPath = url.path
                            }
                        }
                    }
                    HStack {
                        TextField("Initrd (optional)", text: $initrdPath)
                            .textFieldStyle(.roundedBorder)
                        Button("Browse…") {
                            chooseFile(title: "Select Initrd Image") { url in
                                initrdPath = url.path
                            }
                        }
                    }
                }

                Section("Resources") {
                    Stepper("CPUs: \(cpus)", value: $cpus, in: 1...64)
                    Stepper("Memory: \(memoryGB) GB", value: $memoryGB, in: 1...256)
                }

                Section("Storage") {
                    TextField("Disk size (e.g. 20G, 512M)", text: $diskSizeText)
                        .textFieldStyle(.roundedBorder)
                }

                Section("Devices") {
                    Toggle("Network", isOn: $network)
                    Toggle("Audio", isOn: $audio)
                    #if arch(arm64)
                    Toggle("Rosetta", isOn: $rosetta)
                    #endif
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

                Button("Create") {
                    create()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(vmName.isEmpty || kernelPath.isEmpty || isCreating)
            }
            .padding()
        }
        .frame(minWidth: 450, minHeight: 450)
    }

    private func create() {
        isCreating = true
        errorMessage = nil

        do {
            let bundleURL = try resolveBundlePath(vmName, createParentIfNeeded: true)

            guard FileManager.default.fileExists(atPath: kernelPath) else {
                throw ToyVMError("Kernel file not found: \(kernelPath)")
            }

            var options = CreateOptions()
            options.cpus = cpus
            options.memoryGB = memoryGB
            options.audio = audio
            options.network = network
            options.rosetta = rosetta

            let trimmedDisk = diskSizeText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedDisk.isEmpty {
                let (format, size) = try parseDiskSpec(trimmedDisk)
                options.disks = [(format: format, size: size, readOnly: false)]
            }

            let initrd: URL? = initrdPath.isEmpty ? nil : URL(fileURLWithPath: initrdPath)

            let bundle = try VMBundle.create(
                at: bundleURL,
                kernelPath: URL(fileURLWithPath: kernelPath),
                initrdPath: initrd,
                options: options
            )

            manager.refresh()
            manager.selectedBundleURL = bundle.bundleURL
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            isCreating = false
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
