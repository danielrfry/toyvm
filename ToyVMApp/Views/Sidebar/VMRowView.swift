//
//  VMRowView.swift
//  ToyVMApp
//

import SwiftUI
import ToyVMCore

@available(macOS 14.0, *)
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
            if let session, session.runner?.state.isRunning == true {
                Image(systemName: "play.circle.fill")
                    .foregroundStyle(.green)
                    .help("Running")
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
