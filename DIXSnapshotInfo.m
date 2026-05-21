//
//  DIXSnapshotInfo.m
//  Disk Inventory Y
//
//  Copyright (C) 2026 Dani Sarfati.
//
//  This program is free software; you can redistribute it and/or
//  modify it under the terms of the GNU General Public License
//  as published by the Free Software Foundation; either version 3
//  of the License, or any later version.
//

#import "DIXSnapshotInfo.h"

// Path of /usr/bin/tmutil — present on every supported macOS version.
static NSString * const kTMUtilPath = @"/usr/bin/tmutil";

// volumePath (NSString) -> @{ @"count": NSNumber, @"bytes": NSNumber }
static NSMutableDictionary<NSString *, NSDictionary *> *gSnapshotCache;
static dispatch_queue_t gCacheQueue;

static void DIXEnsureCacheInited(void)
{
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        gSnapshotCache = [[NSMutableDictionary alloc] init];
        gCacheQueue    = dispatch_queue_create("io.github.danifunker.dix.snapshotcache",
                                                DISPATCH_QUEUE_SERIAL);
    });
}

// Run tmutil listlocalsnapshots and count lines that look like snapshot names.
static NSUInteger DIXCountSnapshotsAtPath(NSString *volumePath)
{
    NSTask *task = [[NSTask alloc] init];
    [task setLaunchPath: kTMUtilPath];
    [task setArguments: @[ @"listlocalsnapshots", volumePath ]];
    [task setStandardOutput: [NSPipe pipe]];
    [task setStandardError:  [NSPipe pipe]];   // suppress stderr noise

    NSFileHandle *out = [[task.standardOutput fileHandleForReading] retain];

    @try {
        [task launch];
    } @catch ( NSException *e ) {
        [out release];
        [task release];
        return 0;
    }

    NSData *data = [out readDataToEndOfFile];
    [task waitUntilExit];

    NSString *output = [[[NSString alloc] initWithData: data encoding: NSUTF8StringEncoding] autorelease];
    [out release];
    [task release];

    if ( output.length == 0 )
        return 0;

    // Snapshot names start with "com.apple." — count those lines.
    __block NSUInteger count = 0;
    [output enumerateLinesUsingBlock: ^(NSString *line, BOOL *stop) {
        NSString *trimmed = [line stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceCharacterSet]];
        if ( [trimmed hasPrefix: @"com.apple."] )
            count++;
    }];
    return count;
}

// Estimate purgeable bytes (mostly snapshots) on a volume.
static unsigned long long DIXEstimatePurgeableBytes(NSURL *volumeURL)
{
    NSError *err = nil;
    NSDictionary *vals = [volumeURL resourceValuesForKeys: @[
        NSURLVolumeAvailableCapacityKey,
        NSURLVolumeAvailableCapacityForImportantUsageKey,
    ] error: &err];

    NSNumber *base       = vals[NSURLVolumeAvailableCapacityKey];
    NSNumber *important  = vals[NSURLVolumeAvailableCapacityForImportantUsageKey];
    if ( base == nil || important == nil )
        return 0;

    long long delta = [important longLongValue] - [base longLongValue];
    return delta > 0 ? (unsigned long long) delta : 0ULL;
}

void DIXRefreshSnapshotInfoForVolume(NSURL *volumeURL)
{
    if ( volumeURL == nil )
        return;
    DIXEnsureCacheInited();

    NSString *path = [volumeURL path];
    if ( path.length == 0 )
        return;

    NSUInteger count       = DIXCountSnapshotsAtPath(path);
    unsigned long long est = (count > 0) ? DIXEstimatePurgeableBytes(volumeURL) : 0ULL;

    dispatch_sync(gCacheQueue, ^{
        gSnapshotCache[path] = @{
            @"count": @(count),
            @"bytes": @(est),
        };
    });
}

NSString * DIXSnapshotInfoStringForVolume(NSURL *volumeURL)
{
    if ( volumeURL == nil )
        return nil;
    DIXEnsureCacheInited();

    NSString *path = [volumeURL path];
    if ( path.length == 0 )
        return nil;

    __block NSDictionary *entry = nil;
    dispatch_sync(gCacheQueue, ^{
        entry = [gSnapshotCache[path] retain];
    });
    [entry autorelease];

    if ( entry == nil )
        return nil;

    NSUInteger count       = [entry[@"count"] unsignedIntegerValue];
    unsigned long long est = [entry[@"bytes"] unsignedLongLongValue];
    if ( count == 0 )
        return nil;

    NSString *byteStr = [NSByteCountFormatter stringFromByteCount: (long long) est
                                                       countStyle: NSByteCountFormatterCountStyleFile];
    NSString *snapWord = (count == 1) ? @"snapshot" : @"snapshots";

    if ( est == 0 )
        return [NSString stringWithFormat: @"%lu %@", (unsigned long) count, snapWord];
    return [NSString stringWithFormat: @"%lu %@ (~%@)",
            (unsigned long) count, snapWord, byteStr];
}
