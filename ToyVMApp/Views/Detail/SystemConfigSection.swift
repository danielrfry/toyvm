//
//  SystemConfigSection.swift
//  ToyVMApp
//

import SwiftUI
#if canImport(ToyVMCore)
import ToyVMCore
#endif

/// Reusable form sections for CPU, memory, and device configuration.
/// Used by both ConfigEditView and CreateVMView.
@available(macOS 15.0, *)
struct SystemConfigSection: View {
    @Binding var cpus: Int
    @Binding var memoryGB: Int
    @Binding var network: Bool
    @Binding var audio: Bool
    @Binding var rosetta: Bool
    var hideRosetta: Bool = false

    var body: some View {
        Section("Resources") {
            Stepper("CPUs: \(cpus)", value: $cpus, in: 1...64)
            Stepper("Memory: \(memoryGB) GB", value: $memoryGB, in: 1...256)
        }

        Section("Devices") {
            Toggle("Network", isOn: $network)
            Toggle("Audio", isOn: $audio)
            #if arch(arm64)
            if !hideRosetta {
                Toggle("Rosetta", isOn: $rosetta)
            }
            #endif
        }
    }
}
