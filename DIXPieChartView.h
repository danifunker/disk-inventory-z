//
//  DIXPieChartView.h
//  Disk Inventory Z
//
//  Three-wedge pie chart for disk usage:
//    scanned     — the FSItem tree the user is currently looking at
//    other used  — total filesystem used minus scanned
//    free        — free space on the volume
//
//  Sizes are in bytes (unsigned long long). The view re-draws on -setValues:.
//

#import <Cocoa/Cocoa.h>

@interface DIXPieChartView : NSView
{
    unsigned long long _scannedBytes;
    unsigned long long _otherUsedBytes;
    unsigned long long _freeBytes;
}

- (void) setScannedBytes: (unsigned long long) scanned
          otherUsedBytes: (unsigned long long) otherUsed
               freeBytes: (unsigned long long) free;

// Canonical color for "free space" — used by the pie wedge, the treemap
// block, and the settings popover swatch. Adapts to the current appearance
// (light neutral gray in Aqua, dark neutral gray in Dark Mode) so it never
// reads as "this is also usage" the way a system color would.
+ (NSColor*) freeSpaceColor;

// Canonical color for "other used" — pie wedge, treemap block, and
// settings popover swatch all read from here so they stay in sync.
+ (NSColor*) otherSpaceColor;

@end
