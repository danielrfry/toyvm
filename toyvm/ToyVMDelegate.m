//
//  ToyVMDelegate.m
//  toyvm
//
//  Created by Dan Fry on 21/11/2020.
//

#import "ToyVMDelegate.h"

@implementation ToyVMDelegate

- (id)init {
    self = [super init];
    if (self) {
        self.error = nil;
    }
    return self;
}

- (void)guestDidStopVirtualMachine:(VZVirtualMachine *)virtualMachine {
    self.error = nil;
    CFRunLoopStop(CFRunLoopGetMain());
}

- (void)virtualMachine:(VZVirtualMachine *)virtualMachine didStopWithError:(NSError *)error {
    self.error = error;
    CFRunLoopStop(CFRunLoopGetMain());
}

@end
