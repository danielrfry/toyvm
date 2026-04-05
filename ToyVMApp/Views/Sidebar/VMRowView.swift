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

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(VMManager.displayName(for: bundle))
                    .font(.body)
                    .fontWeight(.medium)
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
    }

    private var subtitle: String {
        let branch = bundle.meta.activeBranch
        let cpus = bundle.config.cpus
        let mem = bundle.config.memoryGB
        return "\(branch) · \(cpus) CPU · \(mem) GB"
    }
}
