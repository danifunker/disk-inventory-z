//
//  DIXSnapshotInfo.h
//  Disk Inventory Z
//
//  Copyright (C) 2026 Dani Sarfati.
//
//  This program is free software; you can redistribute it and/or
//  modify it under the terms of the GNU General Public License
//  as published by the Free Software Foundation; either version 3
//  of the License, or any later version.
//
//  Lightweight: counts APFS local snapshots on a mounted volume and
//  estimates the disk space they're holding. Cached in-process so the
//  transformer can read it cheaply during cell drawing.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

// Refresh the cached snapshot info for `volumeURL`. Cheap when there are no
// snapshots (single NSTask returning quickly). Call from rebuildVolumesArray.
extern void DIXRefreshSnapshotInfoForVolume(NSURL *volumeURL);

// Return a one-line summary like "3 snapshots (~1.2 GB)" suitable for display,
// or nil if the volume has no snapshots or hasn't been refreshed yet.
extern NSString * _Nullable DIXSnapshotInfoStringForVolume(NSURL *volumeURL);

NS_ASSUME_NONNULL_END
