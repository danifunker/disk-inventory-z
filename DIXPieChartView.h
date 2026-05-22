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

// Returns a color that adapts to the current appearance: a light, neutral
// gray in light mode; a dark, neutral gray in dark mode. Used for the
// "free" wedge so it doesn't read as "this is also usage" the way the
// system colors do.
+ (NSColor*) freeWedgeColor;

// Color used for the "other used" wedge. Centralized so the controller's
// legend swatch matches whatever the pie draws.
+ (NSColor*) otherUsedWedgeColor;

@end
