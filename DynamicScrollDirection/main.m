//
//  main.m
//  DynamicScrollDirection
//
//  Created by Ford Parsons on 10/23/17.
//  Copyright © 2017 Ford Parsons. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <IOKit/hid/IOHIDLib.h>
#import <CoreMediaIO/CMIOHardware.h>

// Undocumented CoreGraphics methods, from <https://github.com/dustinrue/ControlPlane/issues/150#issuecomment-5721542>
extern int _CGSDefaultConnection(void);
extern void CGSSetSwipeScrollDirection(int cid, BOOL dir);

#pragma mark - Scroll Direction

void SetNaturalScroll(BOOL naturalScroll) {
    // Actually change the scroll direction, using `CGSSetSwipeScrollDirection`, an undocumented CoreGraphics method.
    CGSSetSwipeScrollDirection(_CGSDefaultConnection(), naturalScroll);

    // Update the ~/Library/Preferences/.GlobalPreferences.plist file. Equivalent to `defaults write NSGlobalDomain com.apple.swipescrolldirection -bool YES`.
    CFPreferencesSetAppValue(CFSTR("com.apple.swipescrolldirection"), (CFBooleanRef)@(naturalScroll), kCFPreferencesAnyApplication);
    CFPreferencesAppSynchronize(kCFPreferencesAnyApplication);

    // Send `SwipeScrollDirectionDidChangeNotification` notification so System Preferences can update its UI.
    [NSDistributedNotificationCenter.defaultCenter postNotificationName:@"SwipeScrollDirectionDidChangeNotification" object:nil];
}

IOHIDManagerRef hidManager;

void DeviceMatchingCallback(void *context, IOReturn result, void *sender, IOHIDDeviceRef device) {
    NSLog(@"Attached %@", IOHIDDeviceGetProperty(device, CFSTR(kIOHIDProductKey)));
    SetNaturalScroll(NO);
}

void DeviceRemovalCallback(void *context, IOReturn result, void *sender, IOHIDDeviceRef device) {
    NSLog(@"Removed %@", IOHIDDeviceGetProperty(device, CFSTR(kIOHIDProductKey)));
    CFSetRef devices = IOHIDManagerCopyDevices(hidManager);
    Boolean deviceInList = CFSetContainsValue(devices, device);
    CFIndex deviceCount = CFSetGetCount(devices);
    CFIndex remainingDeviceCount = deviceCount - ((int)deviceInList);
    CFRelease(devices);
    SetNaturalScroll(remainingDeviceCount <= 0);
}

#pragma mark - Litra Light (Camera Monitoring)

static NSString *const kLitraPath = @"/opt/homebrew/bin/litra";
static NSMutableSet *activeCameras;

void SetLitraLight(BOOL on) {
    NSLog(@"Litra light %@", on ? @"ON" : @"OFF");
    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:kLitraPath];
    task.arguments = @[on ? @"on" : @"off"];
    NSError *error = nil;
    [task launchAndReturnError:&error];
    if (error) {
        NSLog(@"Failed to run litra: %@", error);
    }
}

void CameraStateChanged(CMIOObjectID device) {
    CMIOObjectPropertyAddress isRunningAddress = {
        kCMIODevicePropertyDeviceIsRunningSomewhere,
        kCMIOObjectPropertyScopeWildcard,
        kCMIOObjectPropertyElementWildcard
    };

    UInt32 isRunning = 0;
    UInt32 dataSize = sizeof(isRunning);
    OSStatus status = CMIOObjectGetPropertyData(device, &isRunningAddress, 0, NULL, sizeof(isRunning), &dataSize, &isRunning);
    if (status != kCMIOHardwareNoError) return;

    if (isRunning) {
        [activeCameras addObject:@(device)];
    } else {
        [activeCameras removeObject:@(device)];
    }

    NSLog(@"Camera device %u %s (%lu active)", device, isRunning ? "started" : "stopped", (unsigned long)activeCameras.count);
    SetLitraLight(activeCameras.count > 0);
}

void SetupCameraMonitoring(void) {
    activeCameras = [NSMutableSet set];

    // Get all CoreMediaIO devices
    CMIOObjectPropertyAddress devicesAddress = {
        kCMIOHardwarePropertyDevices,
        kCMIOObjectPropertyScopeGlobal,
        0 // kCMIOObjectPropertyElementMain
    };

    UInt32 dataSize = 0;
    CMIOObjectGetPropertyDataSize(kCMIOObjectSystemObject, &devicesAddress, 0, NULL, &dataSize);

    UInt32 deviceCount = dataSize / sizeof(CMIODeviceID);
    if (deviceCount == 0) {
        NSLog(@"No camera devices found");
        return;
    }

    CMIODeviceID *devices = (CMIODeviceID *)malloc(dataSize);
    CMIOObjectGetPropertyData(kCMIOObjectSystemObject, &devicesAddress, 0, NULL, dataSize, &dataSize, devices);

    CMIOObjectPropertyAddress isRunningAddress = {
        kCMIODevicePropertyDeviceIsRunningSomewhere,
        kCMIOObjectPropertyScopeWildcard,
        kCMIOObjectPropertyElementWildcard
    };

    for (UInt32 i = 0; i < deviceCount; i++) {
        CMIODeviceID device = devices[i];

        if (!CMIOObjectHasProperty(device, &isRunningAddress)) continue;

        // Get device name for logging
        CMIOObjectPropertyAddress nameAddress = {
            kCMIOObjectPropertyName,
            kCMIOObjectPropertyScopeGlobal,
            0
        };
        CFStringRef deviceName = NULL;
        UInt32 nameSize = sizeof(deviceName);
        CMIOObjectGetPropertyData(device, &nameAddress, 0, NULL, sizeof(deviceName), &nameSize, &deviceName);
        NSLog(@"Monitoring camera: %@ (id %u)", deviceName, device);
        if (deviceName) CFRelease(deviceName);

        CMIOObjectAddPropertyListenerBlock(device, &isRunningAddress, dispatch_get_main_queue(), ^(UInt32 numberAddresses, const CMIOObjectPropertyAddress addresses[]) {
            CameraStateChanged(device);
        });
    }

    free(devices);
}

#pragma mark - Main

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        // Mouse monitoring (scroll direction)
        hidManager = IOHIDManagerCreate(kCFAllocatorDefault, kIOHIDManagerOptionNone);
        IOHIDManagerSetDeviceMatching(hidManager, (CFDictionaryRef)@{@(kIOProviderClassKey):@(kIOHIDDeviceKey),
                                                    @(kIOHIDTransportKey):@(kIOHIDTransportUSBValue),
                                                    @(kIOHIDDeviceUsagePageKey):@(kHIDPage_GenericDesktop),
                                                    @(kIOHIDDeviceUsageKey):@(kHIDUsage_GD_Mouse)});
        IOHIDManagerRegisterDeviceMatchingCallback(hidManager, DeviceMatchingCallback, nil);
        IOHIDManagerRegisterDeviceRemovalCallback(hidManager, DeviceRemovalCallback, nil);
        IOHIDManagerScheduleWithRunLoop(hidManager, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);

        // Camera monitoring (Litra light)
        SetupCameraMonitoring();

        [NSRunLoop.currentRunLoop runUntilDate:NSDate.distantFuture];
    }
    return 0;
}
