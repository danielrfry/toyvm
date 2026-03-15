//
//  Prompt.swift
//  toyvm
//

import Foundation

/// Ask the user for a yes/no confirmation. The prompt is printed to stderr and
/// returns true only if the user types exactly "yes" (case-insensitive).
func confirm(_ prompt: String) -> Bool {
    fputs(prompt, stderr)
    fflush(stderr)
    guard let response = readLine(strippingNewline: true)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
        return false
    }
    return response == "yes"
}
