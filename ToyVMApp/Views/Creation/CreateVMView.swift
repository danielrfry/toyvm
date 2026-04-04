//
//  CreateVMView.swift
//  ToyVMApp
//

import SwiftUI
#if canImport(ToyVMCore)
import ToyVMCore
#endif

@available(macOS 14.0, *)
struct CreateVMView: View {
    @Bindable var manager: VMManager
    @Environment(\.dismiss) private var dismiss

    @State private var vmName = ""
    @State private var bootMode: BootMode = .linux
    @State private var kernelPath = ""
    @State private var initrdPath = ""
    @State private var cpus = 2
    @State private var memoryGB = 2
    @State private var diskSizeText = "20G"
    @State private var audio = false
    @State private var network = true
    @State private var rosetta = false
    @State private var usbDiskPath = ""
    @State private var restoreImagePath = ""
    @State private var errorMessage: String?
    @State private var isCreating = false
    #if arch(arm64)
    @State private var restoreImageManager = RestoreImageManager()
    @State private var installManager = MacOSInstallManager()
    @State private var isInstalling = false
    @State private var isDownloading = false
    #endif

    /// Boot modes available for creation (macOS only on arm64).
    private var availableBootModes: [BootMode] {
        #if arch(arm64)
        return BootMode.allCases
        #else
        return [.linux, .efi]
        #endif
    }

    var body: some View {
        VStack(spacing: 0) {
            #if arch(arm64)
            if isInstalling {
                installProgressContent
            } else if isDownloading {
                downloadProgressContent
            } else {
                formContent
            }
            #else
            formContent
            #endif
        }
        .frame(minWidth: 450, minHeight: 450)
    }

    private var formContent: some View {
        VStack(spacing: 0) {
            Form {
                Section("General") {
                    TextField("Name", text: $vmName)
                        .textFieldStyle(.roundedBorder)
                    Picker("Boot Mode", selection: $bootMode) {
                        ForEach(availableBootModes, id: \.self) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                }

                if bootMode == .linux {
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
                }

                if bootMode == .efi {
                    Section("Installation Media") {
                        HStack {
                            TextField("USB Disk / ISO (optional)", text: $usbDiskPath)
                                .textFieldStyle(.roundedBorder)
                            Button("Browse…") {
                                chooseFile(title: "Select ISO or Disk Image") { url in
                                    usbDiskPath = url.path
                                }
                            }
                        }
                    }
                }

                #if arch(arm64)
                if bootMode == .macOS {
                    Section("Restore Image") {
                        HStack {
                            TextField("Restore image (.ipsw)", text: $restoreImagePath)
                                .textFieldStyle(.roundedBorder)
                            Button("Browse…") {
                                chooseFile(title: "Select macOS Restore Image", types: ["ipsw"]) { url in
                                    restoreImagePath = url.path
                                }
                            }
                        }
                        Button("Download Latest from Apple…") {
                            startDownload()
                        }
                    }
                }
                #endif

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
                    if bootMode != .macOS {
                        Toggle("Rosetta", isOn: $rosetta)
                    }
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
                .disabled(!isCreateEnabled)
            }
            .padding()
        }
    }

    private var isCreateEnabled: Bool {
        if vmName.isEmpty || isCreating { return false }
        if bootMode == .linux && kernelPath.isEmpty { return false }
        #if arch(arm64)
        if bootMode == .macOS && restoreImagePath.isEmpty { return false }
        #endif
        return true
    }

    #if arch(arm64)
    private var installProgressContent: some View {
        InstallationProgressView(installManager: installManager) {
            installManager.cancel()
            isInstalling = false
        }
    }

    private var downloadProgressContent: some View {
        VStack(spacing: 16) {
            Spacer()

            Text("Downloading macOS restore image…")
                .font(.headline)

            ProgressView(value: restoreImageManager.downloadProgress)
                .progressViewStyle(.linear)

            Text("\(Int(restoreImageManager.downloadProgress * 100))%")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("Cancel") {
                restoreImageManager.cancel()
                isDownloading = false
            }

            Spacer()
        }
        .padding(32)
        .frame(minWidth: 350, minHeight: 200)
    }

    private func startDownload() {
        let panel = NSSavePanel()
        panel.title = "Save Restore Image"
        panel.nameFieldStringValue = "RestoreImage.ipsw"
        panel.allowedContentTypes = [.init(filenameExtension: "ipsw")!]
        guard panel.runModal() == .OK, let destination = panel.url else { return }

        isDownloading = true
        errorMessage = nil

        Task {
            do {
                try await restoreImageManager.downloadLatest(to: destination)
                restoreImagePath = destination.path
                isDownloading = false
            } catch is CancellationError {
                isDownloading = false
            } catch {
                errorMessage = error.localizedDescription
                isDownloading = false
            }
        }
    }
    #endif

    private func create() {
        isCreating = true
        errorMessage = nil

        do {
            let bundleURL = try resolveBundlePath(vmName, createParentIfNeeded: true)

            if bootMode == .linux {
                guard FileManager.default.fileExists(atPath: kernelPath) else {
                    throw ToyVMError("Kernel file not found: \(kernelPath)")
                }
            }

            var options = CreateOptions()
            options.cpus = cpus
            options.memoryGB = memoryGB
            options.audio = audio
            options.network = network
            options.rosetta = rosetta
            options.bootMode = bootMode

            let trimmedDisk = diskSizeText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedDisk.isEmpty {
                let (format, size) = try parseDiskSpec(trimmedDisk)
                options.disks = [(format: format, size: size, readOnly: false)]
            }

            // USB disk for EFI mode
            let trimmedUSB = usbDiskPath.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedUSB.isEmpty {
                options.usbDisks = [USBDiskConfig(path: trimmedUSB, readOnly: true)]
            }

            let kernelURL: URL? = bootMode == .linux ? URL(fileURLWithPath: kernelPath) : nil
            let initrd: URL? = initrdPath.isEmpty ? nil : URL(fileURLWithPath: initrdPath)

            var bundle = try VMBundle.create(
                at: bundleURL,
                kernelPath: kernelURL,
                initrdPath: initrd,
                options: options
            )

            #if arch(arm64)
            if bootMode == .macOS {
                isInstalling = true
                Task {
                    do {
                        try await installManager.install(
                            bundle: &bundle,
                            restoreImageURL: URL(fileURLWithPath: restoreImagePath)
                        )
                        manager.refresh()
                        manager.selectedBundleURL = bundle.bundleURL
                        dismiss()
                    } catch {
                        // Delete the partially-initialized bundle
                        try? FileManager.default.removeItem(at: bundleURL)
                        errorMessage = error.localizedDescription
                        isInstalling = false
                        isCreating = false
                    }
                }
                return
            }
            #endif

            manager.refresh()
            manager.selectedBundleURL = bundle.bundleURL
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            isCreating = false
        }
    }

    private func chooseFile(title: String, types: [String]? = nil, completion: @escaping (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.title = title
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        if let types {
            panel.allowedContentTypes = types.compactMap { .init(filenameExtension: $0) }
        }
        if panel.runModal() == .OK, let url = panel.url {
            completion(url)
        }
    }
}
