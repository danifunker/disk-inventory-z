//
//  DIXVolumeKind.m
//  Disk Inventory Y
//
//  Copyright (C) 2026 Dani Sarfati.
//
//  This program is free software; you can redistribute it and/or
//  modify it under the terms of the GNU General Public License
//  as published by the Free Software Foundation; either version 3
//  of the License, or any later version.
//

#import "DIXVolumeKind.h"
#import <DiskArbitration/DiskArbitration.h>

DIXVolumeKind DIXClassifyVolume(NSURL *volumeURL)
{
    if ( volumeURL == nil )
        return DIXVolumeKindInternal;

    // Step 1: network is unambiguous from NSURL alone.
    NSNumber *isLocal = nil;
    [volumeURL getResourceValue: &isLocal forKey: NSURLVolumeIsLocalKey error: nil];
    if ( isLocal != nil && ![isLocal boolValue] )
        return DIXVolumeKindNetwork;

    // Step 2: ask DiskArbitration whether this is a disk-image-backed mount.
    // Disk images report DeviceProtocol "Virtual Interface". Do this BEFORE
    // the removable/internal checks because disk images often look ejectable.
    BOOL isDiskImage = NO;
    DASessionRef session = DASessionCreate(kCFAllocatorDefault);
    if ( session != NULL )
    {
        DADiskRef disk = DADiskCreateFromVolumePath(kCFAllocatorDefault, session, (__bridge CFURLRef)volumeURL);
        if ( disk != NULL )
        {
            CFDictionaryRef desc = DADiskCopyDescription(disk);
            if ( desc != NULL )
            {
                CFStringRef protocol = CFDictionaryGetValue(desc, kDADiskDescriptionDeviceProtocolKey);
                if ( protocol != NULL
                     && CFStringCompare(protocol, CFSTR("Virtual Interface"), 0) == kCFCompareEqualTo )
                {
                    isDiskImage = YES;
                }
                CFRelease(desc);
            }
            CFRelease(disk);
        }
        CFRelease(session);
    }
    if ( isDiskImage )
        return DIXVolumeKindDiskImage;

    // Step 3: removable/ejectable media is "external" even when the device
    // sits on an internal bus. This catches SD cards in a Mac's built-in
    // reader (PCIe-internal but obviously user-removable) and USB sticks.
    NSNumber *isRemovable = nil;
    NSNumber *isEjectable = nil;
    [volumeURL getResourceValue: &isRemovable forKey: NSURLVolumeIsRemovableKey error: nil];
    [volumeURL getResourceValue: &isEjectable forKey: NSURLVolumeIsEjectableKey error: nil];
    if ( (isRemovable != nil && [isRemovable boolValue])
      || (isEjectable != nil && [isEjectable boolValue]) )
        return DIXVolumeKindExternal;

    // Step 4: now trust the internal-bus signal.
    NSNumber *isInternal = nil;
    [volumeURL getResourceValue: &isInternal forKey: NSURLVolumeIsInternalKey error: nil];
    if ( isInternal != nil && [isInternal boolValue] )
        return DIXVolumeKindInternal;

    // Fallback: unknown bus topology — treat as external (safer than hiding it).
    return DIXVolumeKindExternal;
}
