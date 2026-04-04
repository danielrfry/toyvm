//
//  VMDetailView.swift
//  ToyVMApp
//

import SwiftUI
#if canImport(ToyVMCore)
import ToyVMCore
#endif

@available(macOS 14.0, *)
struct VMDetailView: View {
    @Bindable var session: VMSession
    let manager: VMManager
    @State private var showConfigEditor = false

    private var isRunning: Bool {
        session.runner?.state.isRunning == true
    }

    private var runnerState: VMRunner.State {
        session.runner?.state ?? .stopped
    }

    var body: some View {
        VStack(spacing: 0) {
            if isRunning {
                VMDisplayView(session: session)
            } else {
                configSummary
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if isRunning {
                    Button {
                        session.requestStop()
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                    }
                    .help("Request graceful shutdown")

                    Button {
                        session.forceStop()
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
                    showConfigEditor = true
                } label: {
                    Label("Configure", systemImage: "gearshape")
                }
                .disabled(isRunning)
                .help("Edit VM configuration")
            }
        }
        .navigationTitle(VMManager.displayName(for: session.bundle))
        .sheet(isPresented: $showConfigEditor) {
            ConfigEditView(session: session)
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
                    LabeledContent("Kernel", value: session.bundle.config.kernel)
                    if let initrd = session.bundle.config.initrd {
                        LabeledContent("Initrd", value: initrd)
                    }
                    LabeledContent("Command Line", value: session.bundle.config.kernelCommandLine.joined(separator: " "))
                }

                GroupBox("Branch") {
                    LabeledContent("Active Branch", value: session.bundle.meta.activeBranch)
                    if session.bundle.activeBranchInfo?.readOnly == true {
                        LabeledContent("Read-Only", value: "Yes")
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
}
