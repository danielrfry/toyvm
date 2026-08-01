//
//  ToyVM.swift
//  toyvm
//

import ArgumentParser
import Foundation

#if !TOYVM_TESTING
@main
#endif
struct ToyVM: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "toyvm",
        abstract: "Toy Linux VM using Virtualization.framework",
        subcommands: [StartCommand.self, CreateCommand.self, ConfigCommand.self, LsCommand.self, BranchCommand.self]
    )
}

struct ToyVMError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}
