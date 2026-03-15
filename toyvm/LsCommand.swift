//
//  LsCommand.swift
//  toyvm
//

import ArgumentParser
import Foundation
#if canImport(ToyVMCore)
import ToyVMCore
#endif

extension ToyVM {
    struct LsCommand: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "ls",
            abstract: "List VMs in ~/.toyvm"
        )

        func run() throws {
            let fm = FileManager.default
            let dir = fm.homeDirectoryForCurrentUser.appendingPathComponent(".toyvm", isDirectory: true)
            var isDir: ObjCBool = false
            if !fm.fileExists(atPath: dir.path, isDirectory: &isDir) || !isDir.boolValue {
                return
            }
            let items = try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
            let names = items
                .filter { $0.pathExtension == "bundle" }
                .map { $0.deletingPathExtension().lastPathComponent }
                .sorted()
            for name in names {
                print(name)
            }
        }
    }
}
