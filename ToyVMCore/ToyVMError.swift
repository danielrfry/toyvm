//
//  ToyVMError.swift
//  ToyVMCore
//

import Foundation

public struct ToyVMError: LocalizedError {
    public let errorDescription: String?
    public init(_ message: String) { errorDescription = message }
}
