//
//  main.m
//  toyvm
//
//  Created by Dan Fry on 20/11/2020.
//

#import <Foundation/Foundation.h>
#import <Virtualization/Virtualization.h>

#import "ToyVMDelegate.h"

#include <termios.h>
#include <getopt.h>

static struct option longopts[] = {
    { "memory",     required_argument,  NULL,   'm' },
    { "kernel",     required_argument,  NULL,   'k' },
    { "initrd",     required_argument,  NULL,   'i' },
    { "disk",       required_argument,  NULL,   'd' },
    { "disk-ro",    required_argument,  NULL,   'r' },
    { "cpus",       required_argument,  NULL,   'p' },
    { NULL,         0,                  NULL,   0 }
};

VZVirtioBlockDeviceConfiguration *create_storage_device(const char *imagePath, BOOL readonly) {
    NSURL *imageURL = [NSURL fileURLWithPath:@(imagePath)];
    NSError *err = nil;
    VZDiskImageStorageDeviceAttachment *attachment = [[VZDiskImageStorageDeviceAttachment alloc] initWithURL:imageURL readOnly:readonly error:&err];
    if (err) {
        NSLog(@"Error creating virtual disk:");
        NSLog(@"%@", err);
        return nil;
    }
    VZVirtioBlockDeviceConfiguration *blockDev = [[VZVirtioBlockDeviceConfiguration alloc] initWithAttachment:attachment];
    return blockDev;
}

BOOL add_storage_device(const char *imagePath, BOOL readonly, NSMutableArray *destArray) {
    VZVirtioBlockDeviceConfiguration *dev = create_storage_device(imagePath, readonly);
    if (dev) {
        [destArray addObject:dev];
        return YES;
    } else {
        return NO;
    }
}

int usage() {
    fprintf(stderr, "usage: toyvm [options] [kernel command line]\n"
                    "\n"
                    "Options:\n"
                    "  -k --kernel <path>       Path to the kernel image to load [required]\n"
                    "  -i --initrd <path>       Path to an initrd image to load\n"
                    "  -d --disk <path>         Add a read/write virtual storage device backed by the\n"
                    "                           specified raw disk image file\n"
                    "  -r --disk-ro <path>      Add a read-only virtual storage device backed by the\n"
                    "                           specified raw disk image file\n"
                    "  -p --cpus <number>       Number of CPU (core)s to make available to the VM\n"
                    "                           (default: 2)\n"
                    "  -m --memory <amount>     Amount of memory to reserve for the VM in gigabytes\n"
                    "                           (default: 2)\n");
    return 1;
}

int main(int argc, char * argv[]) {
    NSURL *kernelURL = nil;
    NSURL *initrdURL = nil;
    unsigned long long memorySize = 2l * 1024 * 1024 * 1024;
    NSMutableArray *disks = [NSMutableArray array];
    int cpus = 2;
    
    // Parse command line
    int ch;
    while ((ch = getopt_long(argc, argv, "m:k:i:d:r:p:", longopts, NULL)) != -1) {
        switch (ch) {
            case 'm':
                memorySize = strtol(optarg, NULL, 10) * 1024 * 1024 * 1024;
                break;
            case 'k':
                kernelURL = [NSURL fileURLWithPath:@(optarg)];
                break;
            case 'i':
                initrdURL = [NSURL fileURLWithPath:@(optarg)];
                break;
            case 'd':
                if (!add_storage_device(optarg, NO, disks))
                    return 1;
                break;
            case 'r':
                if (!add_storage_device(optarg, YES, disks))
                    return 1;
                break;
            case 'p':
                cpus = (int)strtol(optarg, NULL, 10);
                break;
            default:
                return usage();
        }
    }
    
    argc -= optind;
    argv += optind;
    
    NSMutableArray *nonOptArgs = [NSMutableArray array];
    for (int i = 0; i < argc; i++) {
        [nonOptArgs addObject:@(argv[i])];
    }
    
    NSString *cmdLine;
    if ([nonOptArgs count] == 0) {
        cmdLine = @"console=hvc0";
    } else {
        cmdLine = [nonOptArgs componentsJoinedByString:@" "];
    }
    
    if (!kernelURL)
        return usage();
    
    // VM config
    VZVirtualMachineConfiguration *config = [[VZVirtualMachineConfiguration alloc] init];

    // Network device
    VZNATNetworkDeviceAttachment *natAttachment = [[VZNATNetworkDeviceAttachment alloc] init];
    VZVirtioNetworkDeviceConfiguration *netDevCfg = [[VZVirtioNetworkDeviceConfiguration alloc] init];
    netDevCfg.attachment = natAttachment;
    config.networkDevices = @[netDevCfg];

    // Console
    VZVirtioConsoleDeviceSerialPortConfiguration *consoleCfg = [[VZVirtioConsoleDeviceSerialPortConfiguration alloc] init];
    NSFileHandle *hStdout = [NSFileHandle fileHandleWithStandardOutput];
    NSFileHandle *hStdin = [NSFileHandle fileHandleWithStandardInput];
    VZFileHandleSerialPortAttachment *consoleAttachment = [[VZFileHandleSerialPortAttachment alloc] initWithFileHandleForReading:hStdin fileHandleForWriting:hStdout];
    consoleCfg.attachment = consoleAttachment;
    config.serialPorts = @[consoleCfg];
    
    // Bootloader
    VZLinuxBootLoader *bootLoader = [[VZLinuxBootLoader alloc] initWithKernelURL:kernelURL];
    if (initrdURL)
        bootLoader.initialRamdiskURL = initrdURL;
    bootLoader.commandLine = cmdLine;

    config.bootLoader = bootLoader;
    config.memorySize = memorySize;
    config.storageDevices = disks;
    config.CPUCount = cpus;
    
    // Validate
    NSError *err;
    if (![config validateWithError:&err]) {
        NSLog(@"Configuration error:");
        NSLog(@"%@", [err description]);
        return 1;
    }
    
    ToyVMDelegate *vmDelegate = [[ToyVMDelegate alloc] init];
    
    VZVirtualMachine *vm = [[VZVirtualMachine alloc] initWithConfiguration:config];
    vm.delegate = vmDelegate;
    [vm startWithCompletionHandler:^(NSError * _Nullable errorOrNil) {
        if (errorOrNil) {
            NSLog(@"Error starting VM:");
            NSLog(@"%@", errorOrNil);
        }
    }];
    
    // Set stdin to raw mode
    struct termios termInfo;
    struct termios termInfoRaw;
    tcgetattr(STDIN_FILENO, &termInfo);
    termInfoRaw = termInfo;
    cfmakeraw(&termInfoRaw);
    tcsetattr(STDIN_FILENO, TCSANOW, &termInfoRaw);

    CFRunLoopRun();
    
    // Reset stdin mode before exiting
    tcsetattr(STDIN_FILENO, TCSANOW, &termInfo);
    
    if (vmDelegate.error) {
        NSLog(@"%@", vmDelegate.error);
    }
    
    return 0;
}
