//
//  ToyVM.swift
//  toyvm
//

import ArgumentParser
import Foundation
#if canImport(ToyVMCore)
import ToyVMCore
#endif

@main
struct ToyVM: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "toyvm",
        abstract: "Toy Linux VM using Virtualization.framework",
        subcommands: [StartCommand.self, CreateCommand.self, ConfigCommand.self, LsCommand.self, BranchCommand.self]
    )
}
