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

static const uint16_t kLitraVendorID = 0x046d;
static const uint16_t kLitraUsagePage = 0xff43;
static NSMutableSet *activeCameras;

void SetLitraLight(BOOL on) {
    NSLog(@"Litra light %@", on ? @"ON" : @"OFF");

    IOHIDManagerRef litraManager = IOHIDManagerCreate(kCFAllocatorDefault, kIOHIDManagerOptionNone);
    IOHIDManagerSetDeviceMatching(litraManager, (CFDictionaryRef)@{
        @(kIOHIDVendorIDKey): @(kLitraVendorID),
        @(kIOHIDDeviceUsagePageKey): @(kLitraUsagePage),
    });
    IOHIDManagerOpen(litraManager, kIOHIDOptionsTypeNone);

    CFSetRef deviceSet = IOHIDManagerCopyDevices(litraManager);
    if (!deviceSet || CFSetGetCount(deviceSet) == 0) {
        NSLog(@"No Litra device found");
        if (deviceSet) CFRelease(deviceSet);
        IOHIDManagerClose(litraManager, kIOHIDOptionsTypeNone);
        CFRelease(litraManager);
        return;
    }

    CFIndex count = CFSetGetCount(deviceSet);
    IOHIDDeviceRef *devices = (IOHIDDeviceRef *)malloc(sizeof(IOHIDDeviceRef) * count);
    CFSetGetValues(deviceSet, (const void **)devices);

    for (CFIndex i = 0; i < count; i++) {
        IOHIDDeviceRef device = devices[i];

        int32_t productID = 0;
        CFNumberRef productIDRef = IOHIDDeviceGetProperty(device, CFSTR(kIOHIDProductIDKey));
        if (productIDRef) CFNumberGetValue(productIDRef, kCFNumberSInt32Type, &productID);

        uint8_t prefix = (productID == 0xc903) ? 0x06 : 0x04;
        uint8_t onByte = on ? 0x01 : 0x00;

        uint8_t report[20] = {
            0x11, 0xff, prefix, 0x1c, onByte,
            0x00, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00,
        };

        IOReturn openResult = IOHIDDeviceOpen(device, kIOHIDOptionsTypeNone);
        if (openResult != kIOReturnSuccess) {
            NSLog(@"Failed to open Litra device: 0x%08x", openResult);
            continue;
        }

        IOReturn result = IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, report[0], report, sizeof(report));
        if (result == kIOReturnSuccess) {
            NSLog(@"Sent %s command to Litra (product 0x%04x)", on ? "ON" : "OFF", productID);
        } else {
            NSLog(@"Failed to send command to Litra: 0x%08x", result);
        }

        IOHIDDeviceClose(device, kIOHIDOptionsTypeNone);
    }

    free(devices);
    CFRelease(deviceSet);
    IOHIDManagerClose(litraManager, kIOHIDOptionsTypeNone);
    CFRelease(litraManager);
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
