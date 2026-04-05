//
//  InstallationProgressView.swift
//  ToyVMApp
//

import SwiftUI
#if canImport(ToyVMCore)
import ToyVMCore
#endif

#if arch(arm64)
@available(macOS 15.0, *)
struct InstallationProgressView: View {
    let installManager: MacOSInstallManager
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            statusLabel

            ProgressView(value: installManager.installProgress)
                .progressViewStyle(.linear)

            Text(percentText)
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("Cancel") {
                onCancel()
            }

            Spacer()
        }
        .padding(32)
        .frame(minWidth: 350, minHeight: 200)
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch installManager.state {
        case .idle:
            Text("Waiting…")
                .font(.headline)
        case .loadingImage:
            Text("Loading restore image…")
                .font(.headline)
        case .preparingVM:
            Text("Preparing virtual machine…")
                .font(.headline)
        case .installing:
            Text("Installing macOS…")
                .font(.headline)
        case .completed:
            Label("Installation complete", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .foregroundStyle(.green)
        case .failed(let msg):
            Label("Installation failed", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.red)
            Text(msg)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var percentText: String {
        let pct = Int(installManager.installProgress * 100)
        return "\(pct)%"
    }
}
#endif
