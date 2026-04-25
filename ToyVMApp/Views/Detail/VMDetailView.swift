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
    @State private var configInitialTab: ConfigTab = .system
    @State private var showBranchSheet = false
    @State private var deviceToDetach: VMSession.AttachedUSBDevice?
    @State private var configUSBDiskIndexToRemove: Int?
    @State private var showShareSheet = false
    @State private var editingShare: ShareConfig?
    @State private var shareToRemove: ShareConfig?
    @State private var showUSBDiskCreateSheet = false
    @State private var showForceStopConfirmation = false

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
                usbMenu
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
                        showForceStopConfirmation = true
                    } label: {
                        Label("Force Stop", systemImage: "xmark.circle.fill")
                    }
                    .help("Force stop the VM immediately")
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
                    configInitialTab = .system
                    showConfigEditor = true
                } label: {
                    Label("Configure", systemImage: "gearshape")
                }
                .help("Edit VM configuration")
            }

            ToolbarItem(placement: .automatic) {
                Button {
                    showBranchSheet = true
                } label: {
                    Label("Branches", systemImage: "arrow.triangle.branch")
                }
                .disabled(isRunningOrStopping)
                .help("Manage branches")
            }
        }
        .navigationTitle(VMManager.displayName(for: session.bundle))
        .sheet(isPresented: $showConfigEditor) {
            ConfigEditView(session: session, initialTab: configInitialTab, isRunning: isRunningOrStopping)
        }
        .sheet(isPresented: $showBranchSheet) {
            BranchManagementSheet(session: session)
        }
        .alert("Force Stop Virtual Machine?", isPresented: $showForceStopConfirmation) {
            Button("Force Stop", role: .destructive) { session.forceStop() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The virtual machine will be stopped immediately. Any unsaved data in the guest may be lost.")
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
        .confirmationDialog(
            "Remove USB Disk",
            isPresented: .init(
                get: { configUSBDiskIndexToRemove != nil },
                set: { if !$0 { configUSBDiskIndexToRemove = nil } }
            )
        ) {
            Button("Remove", role: .destructive) {
                if let index = configUSBDiskIndexToRemove {
                    do {
                        try session.removeUSBDiskFromConfig(at: index)
                    } catch {
                        session.errorMessage = error.localizedDescription
                    }
                    configUSBDiskIndexToRemove = nil
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            let name: String = {
                if let index = configUSBDiskIndexToRemove,
                   index < session.bundle.config.usbDisks.count {
                    return URL(fileURLWithPath: session.bundle.config.usbDisks[index].path).lastPathComponent
                }
                return "this disk"
            }()
            Text("Remove '\(name)' from the virtual machine configuration?")
        }
        .sheet(isPresented: $showShareSheet) {
            ShareEditSheet(session: session, existing: editingShare) {
                editingShare = nil
            }
        }
        .sheet(isPresented: $showUSBDiskCreateSheet) {
            USBDiskCreateSheet(session: session)
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

    private let summaryLabelWidth: CGFloat = 140

    private var hasStorageSummary: Bool {
        !session.bundle.config.disks.isEmpty || !session.bundle.config.usbDisks.isEmpty
    }

    private var configSummary: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                statusBanner

                summaryCard("System") {
                    editButton(for: .system)
                } content: {
                    summaryRows {
                        summaryRow("CPUs", value: "\(session.bundle.config.cpus)")
                        summaryRow("Memory", value: "\(session.bundle.config.memoryGB) GB")
                        summaryRow("Network") { stateBadge(enabled: session.bundle.config.network) }
                        summaryRow("Audio") { stateBadge(enabled: session.bundle.config.audio) }
                        summaryRow("Rosetta") { stateBadge(enabled: session.bundle.config.rosetta) }
                    }
                }

                summaryCard("Boot") {
                    editButton(for: .boot)
                } content: {
                    summaryRows {
                        summaryRow("Boot Mode", value: session.bundle.config.bootMode.label)
                        if session.bundle.config.bootMode != .macOS {
                            if let kernel = session.bundle.config.kernel {
                                summaryRow("Kernel", value: kernel)
                            }
                            if let initrd = session.bundle.config.initrd {
                                summaryRow("Initrd", value: initrd)
                            }
                            if session.bundle.config.bootMode == .linux {
                                summaryRow("Command Line", value: session.bundle.config.kernelCommandLine.joined(separator: " "))
                            }
                        }
                    }
                }

                if hasStorageSummary {
                    summaryCard("Storage") {
                        editButton(for: .storage)
                    } content: {
                        VStack(alignment: .leading, spacing: 18) {
                            if !session.bundle.config.disks.isEmpty {
                                summarySubsection("Disks")
                                VStack(alignment: .leading, spacing: 10) {
                                    ForEach(session.bundle.config.disks, id: \.file) { disk in
                                        summaryItem(
                                            title: disk.file,
                                            subtitle: disk.format.rawValue.uppercased(),
                                            detail: disk.readOnly ? "Read-only" : "Read/write"
                                        )
                                    }
                                }
                            }

                            if !session.bundle.config.usbDisks.isEmpty {
                                if !session.bundle.config.disks.isEmpty {
                                    Divider()
                                }
                                summarySubsection("USB Disks")
                                VStack(alignment: .leading, spacing: 10) {
                                    ForEach(Array(session.bundle.config.usbDisks.enumerated()), id: \.offset) { _, usbDisk in
                                        summaryItem(
                                            title: URL(fileURLWithPath: usbDisk.path).lastPathComponent,
                                            subtitle: usbDisk.readOnly ? "Read-only" : "Read/write"
                                        )
                                    }
                                }
                            }
                        }
                    }
                }

                if !session.bundle.config.shares.isEmpty {
                    summaryCard("Directory Shares") {
                        editButton(for: .sharing)
                    } content: {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(session.bundle.config.shares, id: \.tag) { share in
                                summaryItem(
                                    title: share.tag,
                                    subtitle: share.path,
                                    detail: share.readOnly ? "Read-only" : "Read/write"
                                )
                            }
                        }
                    }
                }

                summaryCard("Branch") {
                    Button("Manage…") { showBranchSheet = true }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                        .disabled(isRunningOrStopping)
                } content: {
                    summaryRows {
                        summaryRow("Active Branch") {
                            HStack(alignment: .center, spacing: 10) {
                                valueText(session.bundle.meta.activeBranch)
                                if session.bundle.activeBranchInfo?.readOnly == true {
                                    Label("Read-only", systemImage: "lock.fill")
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(
                                            Capsule(style: .continuous)
                                                .fill(Color.secondary.opacity(0.12))
                                        )
                                        .help("Read-only")
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: 860, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
        }
    }

    private func summaryCard<HeaderAction: View, Content: View>(
        _ title: String,
        @ViewBuilder action: () -> HeaderAction,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 12) {
                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)

                Spacer(minLength: 12)

                action()
            }

            content()
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08))
        )
    }

    private func editButton(for tab: ConfigTab) -> some View {
        Button {
            configInitialTab = tab
            showConfigEditor = true
        } label: {
            Label("Edit…", systemImage: "pencil")
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
    }

    private func summaryRows<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            content()
        }
    }

    private func summaryRow<Value: View>(
        _ label: String,
        @ViewBuilder value: () -> Value
    ) -> some View {
        HStack(alignment: .top, spacing: 18) {
            Text(label)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: summaryLabelWidth, alignment: .leading)

            value()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func summaryRow(_ label: String, value: String) -> some View {
        summaryRow(label) {
            valueText(value)
        }
    }

    private func valueText(_ text: String) -> some View {
        Text(text)
            .font(.body.weight(.medium))
            .multilineTextAlignment(.leading)
            .textSelection(.enabled)
    }

    private func stateBadge(enabled: Bool) -> some View {
        Text(enabled ? "Enabled" : "Disabled")
            .font(.callout.weight(.medium))
            .foregroundStyle(enabled ? Color.green : Color.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill((enabled ? Color.green : Color.secondary).opacity(0.12))
            )
    }

    private func summarySubsection(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private func summaryItem(title: String, subtitle: String, detail: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.body.weight(.medium))
                .textSelection(.enabled)

            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
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
            if isRunningOrStopping {
                // Running: show hot-plugged devices with detach option
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
            } else {
                // Stopped: show configured disks with remove option
                if !session.bundle.config.usbDisks.isEmpty {
                    ForEach(Array(session.bundle.config.usbDisks.enumerated()), id: \.offset) { idx, usbDisk in
                        Button {
                            configUSBDiskIndexToRemove = idx
                        } label: {
                            Label(
                                "\(URL(fileURLWithPath: usbDisk.path).lastPathComponent) (\(usbDisk.readOnly ? "ro" : "rw"))",
                                systemImage: usbDisk.readOnly ? "lock.fill" : "externaldrive.fill"
                            )
                        }
                    }
                    Divider()
                }
            }

            Button {
                if isRunningOrStopping {
                    attachUSBDisk()
                } else {
                    addUSBDiskToConfig()
                }
            } label: {
                Label("Add USB Device…", systemImage: "plus")
            }
            .disabled(isStopping)

            Button {
                showUSBDiskCreateSheet = true
            } label: {
                Label("Create USB Disk Image…", systemImage: "plus.rectangle.on.folder")
            }
            .disabled(isStopping)
        } label: {
            Label("USB Devices", systemImage: "externaldrive.badge.plus")
        }
        .help("Attach or detach USB storage devices")
    }

    /// Whether directory shares can be modified while the VM is running.
    /// Only macOS guests support hot-plug via VZMultipleDirectoryShare.
    private var sharesAreEditable: Bool {
        !isRunningOrStopping || session.bundle.config.bootMode == .macOS
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
                        .disabled(!sharesAreEditable)
                        Button(role: .destructive) {
                            shareToRemove = share
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                        .disabled(!sharesAreEditable)
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
            .disabled(!sharesAreEditable)
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

    private func addUSBDiskToConfig() {
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

        do {
            try session.addUSBDiskToConfig(url: url, readOnly: readOnly)
        } catch {
            session.errorMessage = error.localizedDescription
        }
    }
}

#if DEBUG
@available(macOS 15.0, *)
#Preview("Stopped") {
    VMDetailView(session: PreviewFixtures.primarySession, manager: PreviewFixtures.manager)
        .frame(width: 1100, height: 760)
}
#endif
