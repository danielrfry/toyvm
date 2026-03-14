//
//  ToyVMDelegate.swift
//  toyvm
//

import CoreFoundation
import Virtualization

class ToyVMDelegate: NSObject, VZVirtualMachineDelegate {
    var error: Error?

    func guestDidStop(_ virtualMachine: VZVirtualMachine) {
        error = nil
        CFRunLoopStop(CFRunLoopGetMain())
    }

    func virtualMachine(_ virtualMachine: VZVirtualMachine, didStopWithError error: Error) {
        self.error = error
        CFRunLoopStop(CFRunLoopGetMain())
    }
}
