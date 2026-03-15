//
//  ToyVM.swift
//  toyvm
//

import ArgumentParser
import Foundation

@main
struct ToyVM: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "toyvm",
        abstract: "Toy Linux VM using Virtualization.framework",
        subcommands: [Start.self, Create.self, Info.self]
    )
}

struct ToyVMError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}
