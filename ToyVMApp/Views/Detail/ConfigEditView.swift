//
//  ConfigEditView.swift
//  ToyVMApp
//

import SwiftUI
import AppKit
#if canImport(ToyVMCore)
import ToyVMCore
#endif

/// Categories for the configuration editor.
enum ConfigTab: String, CaseIterable, Hashable, Identifiable {
    case system
    case boot
    case storage
    case sharing

    var id: Self { self }

    var title: String {
        switch self {
        case .system: "System"
        case .boot: "Boot"
        case .storage: "Storage"
        case .sharing: "Sharing"
        }
    }

    var systemImage: String {
        switch self {
        case .system: "cpu"
        case .boot: "power"
        case .storage: "externaldrive"
        case .sharing: "folder"
        }
    }
}

@available(macOS 15.0, *)
struct ConfigEditView: View {
    @Bindable var session: VMSession
    let isRunning: Bool
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTab: ConfigTab
    @State private var cpus: Int
    @State private var memoryGB: Int
    @State private var audio: Bool
    @State private var network: Bool
    @State private var rosetta: Bool
    @State private var kernelCommandLine: String
    @State private var bootMode: BootMode
    @State private var usbDisks: [USBDiskConfig]
    @State private var errorMessage: String?
    @State private var showDiskCreateSheet = false
    @State private var diskToRemove: DiskConfig?
    @State private var showShareSheet = false
    @State private var editingShare: ShareConfig?
    @State private var shareToRemove: ShareConfig?

    init(session: VMSession, initialTab: ConfigTab = .system, isRunning: Bool = false) {
        self.session = session
        self.isRunning = isRunning
        let config = session.bundle.config
        _selectedTab = State(initialValue: initialTab)
        _cpus = State(initialValue: config.cpus)
        _memoryGB = State(initialValue: config.memoryGB)
        _audio = State(initialValue: config.audio)
        _network = State(initialValue: config.network)
        _rosetta = State(initialValue: config.rosetta)
        _kernelCommandLine = State(initialValue: config.kernelCommandLine.joined(separator: " "))
        _bootMode = State(initialValue: config.bootMode)
        _usbDisks = State(initialValue: config.usbDisks)
    }

    /// Whether shares can be edited (stopped, or running macOS guest).
    private var sharesEditable: Bool {
        !isRunning || session.bundle.config.bootMode == .macOS
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                sidebar
                Divider()
                detailPane
            }

            Divider()

            VStack(spacing: 0) {
                if let errorMessage {
                    HStack {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                }

                HStack {
                    Spacer()
                    if isRunning {
                        Button("Done") { dismiss() }
                            .keyboardShortcut(.defaultAction)
                    } else {
                        Button("Cancel") { dismiss() }
                            .keyboardShortcut(.cancelAction)
                        Button("Save") { save() }
                            .keyboardShortcut(.defaultAction)
                    }
                }
                .padding()
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 760, minHeight: 520)
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $showDiskCreateSheet) {
            DiskCreateSheet(session: session)
        }
        .confirmationDialog(
            "Remove Disk",
            isPresented: .init(
                get: { diskToRemove != nil },
                set: { if !$0 { diskToRemove = nil } }
            ),
            presenting: diskToRemove
        ) { disk in
            Button("Remove", role: .destructive) {
                do {
                    try session.bundle.removeDisk(named: disk.file)
                    try session.bundle.saveConfig()
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { disk in
            Text("Remove '\(disk.file)'? The disk image will be permanently deleted.")
        }
        .sheet(isPresented: $showShareSheet) {
            ShareEditSheet(session: session, existing: editingShare) {
                editingShare = nil
            }
        }
        .confirmationDialog(
            "Remove Directory Share",
            isPresented: .init(
                get: { shareToRemove != nil },
                set: { if !$0 { shareToRemove = nil } }
            ),
            presenting: shareToRemove
        ) { share in
            Button("Remove", role: .destructive) {
                do {
                    try session.bundle.removeShare(tag: share.tag)
                    try session.bundle.saveConfig()
                    session.updateRuntimeShares()
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { share in
            Text("Remove the directory share '\(share.tag)'?")
        }
    }

    // MARK: - Layout

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(ConfigTab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    Label(tab.title, systemImage: tab.systemImage)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(selectedTab == tab ? Color.accentColor.opacity(0.16) : .clear)
                }
            }

            Spacer()
        }
        .padding(12)
        .frame(width: 180)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var detailPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(selectedTab.title)
                .font(.title2.weight(.semibold))
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 4)

            selectedTabContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private var selectedTabContent: some View {
        switch selectedTab {
        case .system:
            systemTab
        case .boot:
            bootTab
        case .storage:
            storageTab
        case .sharing:
            sharingTab
        }
    }

    private func editorForm<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        Form {
            content()
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - System Tab

    private var systemTab: some View {
        editorForm {
            SystemConfigSection(
                cpus: $cpus,
                memoryGB: $memoryGB,
                network: $network,
                audio: $audio,
                rosetta: $rosetta
            )
        }
        .disabled(isRunning)
    }

    // MARK: - Boot Tab

    private var bootTab: some View {
        editorForm {
            if session.bundle.config.bootMode == .macOS {
                Section("Boot Mode") {
                    LabeledContent("Boot Mode", value: "macOS")
                }
            } else {
                Section("Boot Mode") {
                    Picker("Boot Mode", selection: $bootMode) {
                        ForEach(BootMode.allCases.filter({ $0 != .macOS }), id: \.self) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                }

                Section("Boot Images") {
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
        }
        .disabled(isRunning)
    }

    // MARK: - Storage Tab

    private var storageTab: some View {
        editorForm {
            Section("Disks") {
                if session.bundle.config.disks.isEmpty {
                    Text("No disks configured")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(session.bundle.config.disks, id: \.file) { disk in
                        LabeledContent(disk.file) {
                            HStack {
                                Text("\(disk.format.rawValue), \(disk.readOnly ? "ro" : "rw")")
                                Button(role: .destructive) {
                                    diskToRemove = disk
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                }
                Button("Add Disk…") { showDiskCreateSheet = true }
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
        }
        .disabled(isRunning)
    }

    // MARK: - Sharing Tab

    private var sharingTab: some View {
        editorForm {
            Section("Directory Shares") {
                if session.bundle.config.shares.isEmpty {
                    Text("No directory shares configured")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(session.bundle.config.shares, id: \.tag) { share in
                        LabeledContent(share.tag) {
                            HStack {
                                Text("\(share.path) (\(share.readOnly ? "ro" : "rw"))")
                                Button {
                                    editingShare = share
                                    showShareSheet = true
                                } label: {
                                    Image(systemName: "pencil")
                                }
                                .buttonStyle(.borderless)
                                Button(role: .destructive) {
                                    shareToRemove = share
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                }
                Button("Add Share…") {
                    editingShare = nil
                    showShareSheet = true
                }
            }
        }
        .disabled(!sharesEditable)
    }

    // MARK: - Actions

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

#if DEBUG
@available(macOS 15.0, *)
#Preview("System") {
    ConfigEditView(session: PreviewFixtures.primarySession, initialTab: .system)
}

@available(macOS 15.0, *)
#Preview("Storage") {
    ConfigEditView(session: PreviewFixtures.primarySession, initialTab: .storage)
}
#endif
