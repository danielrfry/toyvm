//
//  VMRowView.swift
//  ToyVMApp
//

import SwiftUI
#if canImport(ToyVMCore)
import ToyVMCore
#endif

@available(macOS 15.0, *)
struct VMRowView: View {
    let bundle: VMBundle
    var session: VMSession?
    let isRenaming: Bool
    @Binding var renameText: String
    let onNameClick: () -> Void
    let onRenameCommit: () -> Void
    let onRenameCancel: () -> Void

    @FocusState private var renameFieldFocused: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                nameField
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let session {
                switch session.runner?.state {
                case .starting, .running:
                    Image(systemName: "play.circle.fill")
                        .foregroundStyle(.green)
                        .help("Running")
                case .stopping:
                    Image(systemName: "stop.circle.fill")
                        .foregroundStyle(.orange)
                        .help("Stopping")
                default:
                    EmptyView()
                }
            }
        }
        .padding(.vertical, 2)
        .onChange(of: isRenaming) { _, editing in
            if editing {
                renameFieldFocused = true
            }
        }
    }

    private var subtitle: String {
        let branch = bundle.meta.activeBranch
        let cpus = bundle.config.cpus
        let mem = bundle.config.memoryGB
        return "\(branch) · \(cpus) CPU · \(mem) GB"
    }

    @ViewBuilder
    private var nameField: some View {
        if isRenaming {
            TextField("Virtual Machine Name", text: $renameText)
                .textFieldStyle(.roundedBorder)
                .font(.body.weight(.medium))
                .focused($renameFieldFocused)
                .onSubmit(onRenameCommit)
                .onExitCommand(perform: onRenameCancel)
                .onChange(of: renameFieldFocused) { _, isFocused in
                    if !isFocused && isRenaming {
                        onRenameCommit()
                    }
                }
        } else {
            Text(VMManager.displayName(for: bundle))
                .font(.body)
                .fontWeight(.medium)
                .contentShape(Rectangle())
                .onTapGesture(perform: onNameClick)
        }
    }
}
