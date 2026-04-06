//
//  VMDetailView.swift
//  ToyVMApp
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers
#if canImport(ToyVMCore)
import ToyVMCore
#endif

@available(macOS 15.0, *)
struct VMDetailView: View {
    @Bindable var session: VMSession
    let manager: VMManager
    @State private var showConfigEditor = false
    @State private var showBranchSheet = false
    @State private var deviceToDetach: VMSession.AttachedUSBDevice?
    @State private var showShareSheet = false
    @State private var editingShare: ShareConfig?
    @State private var shareToRemove: ShareConfig?

    private var runnerState: VMRunner.State {
        session.runner?.state ?? .stopped
    }

    private var isRunningOrStopping: Bool {
        switch runnerState {
        case .starting, .running, .stopping:
            return true
        default:
            return false
        }
    }

    private var isStopping: Bool {
        runnerState == .stopping
    }

    /// Show an opaque background (to cover TerminalLayerView) unless the terminal
    /// should be visible — i.e. when the VM is running/stopping in terminal mode.
    private var showsOpaqueBackground: Bool {
        !isRunningOrStopping || session.displayMode == .graphics
    }

    var body: some View {
        VStack(spacing: 0) {
            if isRunningOrStopping {
                if session.displayMode == .graphics {
                    GraphicsDisplayView(session: session)
                }
                // Terminal mode: body is empty and transparent so TerminalLayerView shows through.
            } else {
                configSummary
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(showsOpaqueBackground ? Color(nsColor: .windowBackgroundColor) : Color.clear)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                if isRunningOrStopping && !isStopping {
                    usbMenu
                }
            }

            ToolbarItem(placement: .automatic) {
                sharesMenu
            }

            ToolbarItemGroup(placement: .primaryAction) {
                if isRunningOrStopping {
                    Button {
                        session.requestStop()
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                    }
                    .help("Request graceful shutdown")
                    .disabled(isStopping)

                    Button {
                        session.forceStop()
                    } label: {
                        Label("Force Stop", systemImage: "xmark.circle.fill")
                    }
                    .help("Force stop the VM immediately")
                    .disabled(isStopping)
                } else {
                    Button {
                        Task { await session.start() }
                    } label: {
                        Label("Start", systemImage: "play.fill")
                    }
                    .help("Start the virtual machine")
                    .disabled(session.bundle.activeBranchInfo?.readOnly == true)
                }
            }

            ToolbarItem(placement: .automatic) {
                Button {
                    showConfigEditor = true
                } label: {
                    Label("Configure", systemImage: "gearshape")
                }
                .disabled(isRunningOrStopping)
                .help("Edit VM configuration")
            }
        }
        .navigationTitle(VMManager.displayName(for: session.bundle))
        .sheet(isPresented: $showConfigEditor) {
            ConfigEditView(session: session)
        }
        .sheet(isPresented: $showBranchSheet) {
            BranchManagementSheet(session: session)
        }
        .alert("Error", isPresented: .init(
            get: { session.errorMessage != nil },
            set: { if !$0 { session.errorMessage = nil } }
        )) {
            Button("OK") { session.errorMessage = nil }
        } message: {
            if let msg = session.errorMessage {
                Text(msg)
            }
        }
        .confirmationDialog(
            "Detach USB Device",
            isPresented: .init(
                get: { deviceToDetach != nil },
                set: { if !$0 { deviceToDetach = nil } }
            ),
            presenting: deviceToDetach
        ) { device in
            Button("Detach", role: .destructive) {
                Task {
                    do {
                        try await session.detachUSBDevice(id: device.id)
                    } catch {
                        session.errorMessage = error.localizedDescription
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { device in
            Text("Detach '\(device.filename)' from the virtual machine?")
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
                    session.errorMessage = error.localizedDescription
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { share in
            Text("Remove the directory share '\(share.tag)'?")
        }
    }

    private var configSummary: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                statusBanner

                GroupBox("System") {
                    LabeledContent("CPUs", value: "\(session.bundle.config.cpus)")
                    LabeledContent("Memory", value: "\(session.bundle.config.memoryGB) GB")
                    LabeledContent("Network", value: session.bundle.config.network ? "Enabled" : "Disabled")
                    LabeledContent("Audio", value: session.bundle.config.audio ? "Enabled" : "Disabled")
                    LabeledContent("Rosetta", value: session.bundle.config.rosetta ? "Enabled" : "Disabled")
                }

                GroupBox("Boot") {
                    LabeledContent("Boot Mode", value: session.bundle.config.bootMode.label)
                    if session.bundle.config.bootMode != .macOS {
                        if let kernel = session.bundle.config.kernel {
                            LabeledContent("Kernel", value: kernel)
                        }
                        if let initrd = session.bundle.config.initrd {
                            LabeledContent("Initrd", value: initrd)
                        }
                        if session.bundle.config.bootMode == .linux {
                            LabeledContent("Command Line", value: session.bundle.config.kernelCommandLine.joined(separator: " "))
                        }
                    }
                }

                GroupBox("Branch") {
                    HStack {
                        LabeledContent("Active Branch", value: session.bundle.meta.activeBranch)
                        if session.bundle.activeBranchInfo?.readOnly == true {
                            Image(systemName: "lock.fill")
                                .foregroundStyle(.secondary)
                                .help("Read-only")
                        }
                        Spacer()
                        Button("Manage…") { showBranchSheet = true }
                            .disabled(isRunningOrStopping)
                    }
                }

                if !session.bundle.config.disks.isEmpty {
                    GroupBox("Disks") {
                        ForEach(session.bundle.config.disks, id: \.file) { disk in
                            LabeledContent(disk.file) {
                                Text("\(disk.format.rawValue), \(disk.readOnly ? "read-only" : "read/write")")
                            }
                        }
                    }
                }

                if !session.bundle.config.usbDisks.isEmpty {
                    GroupBox("USB Disks") {
                        ForEach(Array(session.bundle.config.usbDisks.enumerated()), id: \.offset) { _, usbDisk in
                            LabeledContent(URL(fileURLWithPath: usbDisk.path).lastPathComponent) {
                                Text(usbDisk.readOnly ? "read-only" : "read/write")
                            }
                        }
                    }
                }

                if !session.bundle.config.shares.isEmpty {
                    GroupBox("Directory Shares") {
                        ForEach(session.bundle.config.shares, id: \.tag) { share in
                            LabeledContent(share.tag) {
                                Text("\(share.path) (\(share.readOnly ? "ro" : "rw"))")
                            }
                        }
                    }
                }
            }
            .padding()
        }
    }

    @ViewBuilder
    private var statusBanner: some View {
        switch runnerState {
        case .stopped:
            EmptyView()
        case .starting:
            Label("Starting…", systemImage: "hourglass")
                .foregroundStyle(.secondary)
        case .running:
            Label("Running", systemImage: "play.circle.fill")
                .foregroundStyle(.green)
        case .stopping:
            Label("Stopping…", systemImage: "hourglass")
                .foregroundStyle(.orange)
        case .error(let msg):
            Label("Error: \(msg)", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        }
    }

    private var usbMenu: some View {
        Menu {
            if !session.attachedUSBDevices.isEmpty {
                ForEach(session.attachedUSBDevices) { device in
                    Button {
                        deviceToDetach = device
                    } label: {
                        Label(
                            device.filename,
                            systemImage: device.readOnly ? "lock.fill" : "externaldrive.fill"
                        )
                    }
                }
                Divider()
            }
            
            Button {
                attachUSBDisk()
            } label: {
                Label("Add USB Device…", systemImage: "plus")
            }
        } label: {
            Label("USB Devices", systemImage: "externaldrive.badge.plus")
        }
        .help("Attach or detach USB storage devices")
    }

    private var sharesMenu: some View {
        Menu {
            if !session.bundle.config.shares.isEmpty {
                ForEach(session.bundle.config.shares, id: \.tag) { share in
                    Menu(share.tag) {
                        Text("\(share.path)")
                        Text(share.readOnly ? "Read-only" : "Read/write")
                        Divider()
                        Button {
                            editingShare = share
                            showShareSheet = true
                        } label: {
                            Label("Edit…", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            shareToRemove = share
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    }
                }
                Divider()
            }

            Button {
                editingShare = nil
                showShareSheet = true
            } label: {
                Label("Add Share…", systemImage: "plus")
            }
        } label: {
            Label("Directory Shares", systemImage: "folder.badge.plus")
        }
        .help("Manage directory shares")
    }

    private func attachUSBDisk() {
        let panel = NSOpenPanel()
        panel.title = "Select Disk Image"
        panel.allowedContentTypes = [
            UTType(filenameExtension: "img"),
            UTType(filenameExtension: "iso"),
            UTType(filenameExtension: "raw"),
            UTType(filenameExtension: "asif"),
        ].compactMap { $0 }
        panel.allowsOtherFileTypes = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        let accessoryView = NSButton(checkboxWithTitle: "Read-only", target: nil, action: nil)
        accessoryView.state = .on
        panel.accessoryView = accessoryView
        panel.isAccessoryViewDisclosed = true

        guard panel.runModal() == .OK, let url = panel.url else { return }
        let readOnly = accessoryView.state == .on

        Task {
            do {
                try await session.attachUSBDisk(url: url, readOnly: readOnly)
            } catch {
                session.errorMessage = error.localizedDescription
            }
        }
    }
}
