//
//  ToyVMDelegate.h
//  toyvm
//
//  Created by Dan Fry on 21/11/2020.
//

#import <Cocoa/Cocoa.h>
#import <Virtualization/Virtualization.h>

NS_ASSUME_NONNULL_BEGIN

@interface ToyVMDelegate : NSObject<VZVirtualMachineDelegate>

- (void)guestDidStopVirtualMachine:(VZVirtualMachine *)virtualMachine;
- (void)virtualMachine:(VZVirtualMachine *)virtualMachine didStopWithError:(NSError *)error;

@property(nullable) NSError *error;

@end

NS_ASSUME_NONNULL_END
