//
//  DIXPieChartView.m
//  Disk Inventory Z
//

#import "DIXPieChartView.h"

@implementation DIXPieChartView

+ (NSColor*) otherUsedWedgeColor
{
    return [NSColor systemPurpleColor];
}

+ (NSColor*) freeWedgeColor
{
    // Appearance-aware neutral: light gray on Aqua, dark gray on dark
    // mode. Avoids the "this looks like usage too" feel of green/blue
    // and reads as empty/available without being totally invisible.
    return [NSColor colorWithName: @"DIXFreeWedge"
                  dynamicProvider: ^NSColor* (NSAppearance *appearance)
    {
        NSAppearanceName name = [appearance bestMatchFromAppearancesWithNames:
            @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]];
        if ( [name isEqualToString: NSAppearanceNameDarkAqua] )
            return [NSColor colorWithWhite: 0.30 alpha: 1.0];
        return [NSColor colorWithWhite: 0.88 alpha: 1.0];
    }];
}

- (void) setScannedBytes: (unsigned long long) scanned
          otherUsedBytes: (unsigned long long) otherUsed
               freeBytes: (unsigned long long) free
{
    if ( _scannedBytes == scanned && _otherUsedBytes == otherUsed && _freeBytes == free )
        return;
    _scannedBytes = scanned;
    _otherUsedBytes = otherUsed;
    _freeBytes = free;
    [self setNeedsDisplay: YES];
}

- (BOOL) isFlipped { return NO; }

// Draw a label centered on the wedge, but only if it'd fit comfortably.
// Returns YES if a label was drawn.
- (BOOL) drawWedgeLabel: (NSString*) text
                 center: (NSPoint) center
                 radius: (CGFloat) radius
             startAngle: (CGFloat) startDeg
             sweepAngle: (CGFloat) sweepDeg
              textColor: (NSColor*) textColor
{
    if ( sweepDeg < 10 ) return NO;  // even small font won't read this thin

    // Label sits along the wedge's bisecting angle. We try progressively
    // smaller fonts until the longest line fits inside the wedge's chord
    // at the label radius.
    CGFloat midAngleDeg = startDeg - sweepDeg / 2.0;
    CGFloat midAngleRad = midAngleDeg * (M_PI / 180.0);
    CGFloat labelRadius = radius * 0.60;
    NSPoint labelCenter = NSMakePoint(
        center.x + labelRadius * cos(midAngleRad),
        center.y + labelRadius * sin(midAngleRad));
    CGFloat chord = 2 * labelRadius * sin( sweepDeg * (M_PI / 180.0) / 2.0 );

    NSMutableParagraphStyle *para = [[[NSMutableParagraphStyle alloc] init] autorelease];
    [para setAlignment: NSTextAlignmentCenter];

    CGFloat tryPointSizes[] = { 11, 10, 9 };
    for ( unsigned i = 0; i < sizeof(tryPointSizes)/sizeof(tryPointSizes[0]); i++ )
    {
        NSDictionary *attrs = @{
            NSFontAttributeName: [NSFont boldSystemFontOfSize: tryPointSizes[i]],
            NSForegroundColorAttributeName: textColor,
            NSParagraphStyleAttributeName: para,
        };
        NSSize sz = [text sizeWithAttributes: attrs];

        if ( sz.width > chord * 0.95 )
            continue;  // doesn't fit at this size; shrink

        NSRect labelRect = NSMakeRect(
            labelCenter.x - sz.width/2,
            labelCenter.y - sz.height/2,
            sz.width, sz.height);
        [text drawInRect: labelRect withAttributes: attrs];
        return YES;
    }
    return NO;  // didn't fit at the smallest tried size
}

// Two lines, centered: "NN GB (NN%)" on top, name underneath.
// Putting the longer line on top makes the shorter name read cleanly
// below, and the chord-fit check uses the wider line either way.
- (NSString*) shortLabelForBytes: (unsigned long long) bytes
                         ofTotal: (unsigned long long) total
                            name: (NSString*) name
{
    if ( total == 0 ) return @"";
    double gb = (double)bytes / (1000.0 * 1000.0 * 1000.0);
    double pct = 100.0 * (double)bytes / (double)total;
    return [NSString stringWithFormat: @"%.0f GB (%.0f%%)\n%@", gb, pct, name];
}

- (void) drawRect: (NSRect) dirtyRect
{
    NSRect b = [self bounds];

    [[NSColor windowBackgroundColor] setFill];
    NSRectFill(b);

    unsigned long long total = _scannedBytes + _otherUsedBytes + _freeBytes;
    if ( total == 0 )
        return;

    CGFloat side = MIN(NSWidth(b), NSHeight(b)) - 16;
    if ( side < 32 ) return;
    NSRect circle = NSMakeRect(
        NSMidX(b) - side/2,
        NSMidY(b) - side/2,
        side, side);

    NSPoint center = NSMakePoint(NSMidX(circle), NSMidY(circle));
    CGFloat radius = side / 2;

    double fScanned   = (double) _scannedBytes   / (double) total;
    double fOtherUsed = (double) _otherUsedBytes / (double) total;

    // Color scheme: scanned = blue, other-used = green, free = neutral.
    // Free wedge gets its own stroked outline so it reads against the
    // panel background despite the low-saturation fill.
    NSColor *cScanned   = [NSColor systemBlueColor];
    NSColor *cOtherUsed = [[self class] otherUsedWedgeColor];
    NSColor *cFree      = [[self class] freeWedgeColor];

    CGFloat startAngle = 90;
    CGFloat sweepScanned   = (CGFloat)(fScanned   * 360.0);
    CGFloat sweepOtherUsed = (CGFloat)(fOtherUsed * 360.0);
    CGFloat sweepFree      = 360 - sweepScanned - sweepOtherUsed;

    void (^drawWedge)(CGFloat, CGFloat, NSColor*, BOOL) =
        ^(CGFloat startDeg, CGFloat sweepDeg, NSColor *color, BOOL stroke)
    {
        if ( sweepDeg <= 0 ) return;
        NSBezierPath *p = [NSBezierPath bezierPath];
        [p moveToPoint: center];
        [p appendBezierPathWithArcWithCenter: center
                                      radius: radius
                                  startAngle: startDeg
                                    endAngle: startDeg - sweepDeg
                                   clockwise: YES];
        [p closePath];
        [color setFill];
        [p fill];
        if ( stroke )
        {
            [[NSColor separatorColor] setStroke];
            [p setLineWidth: 0.75];
            [p stroke];
        }
    };

    drawWedge(startAngle,                                 sweepScanned,   cScanned,   NO);
    drawWedge(startAngle - sweepScanned,                  sweepOtherUsed, cOtherUsed, NO);
    drawWedge(startAngle - sweepScanned - sweepOtherUsed, sweepFree,      cFree,      YES);

    // Inline labels: white text on the colored wedges, label-color on
    // the neutral free wedge. Each label is three lines: GB / % / name.
    [self drawWedgeLabel: [self shortLabelForBytes: _scannedBytes ofTotal: total
                                              name: NSLocalizedString(@"Scanned", @"Pie wedge name")]
                  center: center radius: radius
              startAngle: startAngle sweepAngle: sweepScanned
               textColor: [NSColor whiteColor]];
    [self drawWedgeLabel: [self shortLabelForBytes: _otherUsedBytes ofTotal: total
                                              name: NSLocalizedString(@"Other", @"Pie wedge name (short form; legend uses 'Other used')")]
                  center: center radius: radius
              startAngle: startAngle - sweepScanned sweepAngle: sweepOtherUsed
               textColor: [NSColor whiteColor]];
    [self drawWedgeLabel: [self shortLabelForBytes: _freeBytes ofTotal: total
                                              name: NSLocalizedString(@"Free", @"Pie wedge name")]
                  center: center radius: radius
              startAngle: startAngle - sweepScanned - sweepOtherUsed sweepAngle: sweepFree
               textColor: [NSColor labelColor]];

    // Outline the whole circle for definition.
    NSBezierPath *outline = [NSBezierPath bezierPathWithOvalInRect: circle];
    [[NSColor separatorColor] setStroke];
    [outline setLineWidth: 0.5];
    [outline stroke];
}

@end
