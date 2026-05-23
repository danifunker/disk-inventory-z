//
//  DIXVolumeKind.h
//  Disk Inventory Z
//
//  Copyright (C) 2026 Dani Sarfati.
//
//  This program is free software; you can redistribute it and/or
//  modify it under the terms of the GNU General Public License
//  as published by the Free Software Foundation; either version 3
//  of the License, or any later version.
//

#import <Cocoa/Cocoa.h>

typedef NS_ENUM(NSInteger, DIXVolumeKind) {
    DIXVolumeKindInternal,    // built-in disk
    DIXVolumeKindExternal,    // USB, Thunderbolt, SD, FireWire, eSATA, external NVMe
    DIXVolumeKindNetwork,     // SMB, AFP, NFS, etc.
    DIXVolumeKindDiskImage,   // mounted .dmg / .iso / .sparsebundle / .sparseimage
};

// Classify a mounted volume by inspecting NSURL keys and DiskArbitration
// metadata. Defaults to DIXVolumeKindInternal if classification fails.
extern DIXVolumeKind DIXClassifyVolume(NSURL *volumeURL);
