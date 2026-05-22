//
//  DiskUsagePieController.m
//  Disk Inventory Z
//

#import "DiskUsagePieController.h"
#import "DIXPieChartView.h"
#import "FileSystemDoc.h"
#import "FSItem.h"
#import "FileSizeFormatter.h"

@implementation DiskUsagePieController

- (instancetype) initWithDocument: (FileSystemDoc*) doc
                     parentWindow: (NSWindow*) parentWindow
{
    NSParameterAssert( doc != nil );
    NSParameterAssert( parentWindow != nil );

    NSRect contentRect = NSMakeRect(0, 0, 300, 420);
    NSWindowStyleMask style = NSWindowStyleMaskTitled
                            | NSWindowStyleMaskClosable
                            | NSWindowStyleMaskResizable
                            | NSWindowStyleMaskUtilityWindow;

    NSPanel *panel = [[NSPanel alloc] initWithContentRect: contentRect
                                                styleMask: style
                                                  backing: NSBackingStoreBuffered
                                                    defer: YES];
    [panel setTitle: NSLocalizedString( @"Disk Usage", @"Pie chart panel title" )];
    [panel setFloatingPanel: YES];
    [panel setBecomesKeyOnlyIfNeeded: YES];
    [panel setHidesOnDeactivate: NO];
    [panel setReleasedWhenClosed: NO];
    [panel setFrameAutosaveName: @"DIXDiskUsagePiePanel"];
    [panel setContentMinSize: NSMakeSize(260, 380)];

    self = [super initWithWindow: panel];
    [panel release];
    if ( self == nil ) return nil;

    _document = doc;                    // weak
    _parentWindow = [parentWindow retain];

    [self buildContent];
    [self refresh];

    // Observe doc-level item changes (refresh, move-to-trash) so the
    // pie updates when the model changes after the initial scan.
    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(onItemsChanged:)
                                                 name: FSItemsChangedNotification
                                               object: _document];

    return self;
}

- (void) dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver: self];
    [_parentWindow release];
    [super dealloc];
}

- (void) buildContent
{
    NSView *content = [[self window] contentView];
    NSRect b = [content bounds];

    // Bottom-up layout:
    //   y=8..68    explainer (60pt for ~4 lines of wrapped small text)
    //   y=76..148  legend (3 rows × 24pt with 6pt header gap)
    //   y=148..H   pie (square, fills remaining height)
    const CGFloat explainerY = 8;
    const CGFloat explainerH = 60;
    const CGFloat legendY    = explainerY + explainerH + 8;
    const CGFloat legendH    = 72;
    const CGFloat pieBottom  = legendY + legendH;

    NSRect pieFrame = NSMakeRect(0, pieBottom, NSWidth(b), NSHeight(b) - pieBottom);
    DIXPieChartView *pie = [[[DIXPieChartView alloc] initWithFrame: pieFrame] autorelease];
    [pie setAutoresizingMask: NSViewWidthSizable | NSViewHeightSizable];
    [content addSubview: pie];
    _pieView = pie;

    // Legend (top-to-bottom: scanned / other / free), colors match the pie.
    _scannedLabel   = [self addLegendRowAtY: legendY + 48
                                       color: [NSColor systemBlueColor]
                                        text: @"…"];
    _otherUsedLabel = [self addLegendRowAtY: legendY + 24
                                       color: [DIXPieChartView otherUsedWedgeColor]
                                        text: @"…"];
    _freeLabel      = [self addLegendRowAtY: legendY + 0
                                       color: [DIXPieChartView freeWedgeColor]
                                        text: @"…"];

    // Explainer: small italic text describing what "Other" might be.
    NSRect explainerFrame = NSMakeRect(14, explainerY, NSWidth(b) - 28, explainerH);
    NSTextField *explainer = [[[NSTextField alloc] initWithFrame: explainerFrame] autorelease];
    [explainer setEditable: NO];
    [explainer setSelectable: YES];
    [explainer setBezeled: NO];
    [explainer setBordered: NO];
    [explainer setDrawsBackground: NO];
    [explainer setFont: [NSFont systemFontOfSize: 10]];
    [explainer setTextColor: [NSColor secondaryLabelColor]];
    [[explainer cell] setWraps: YES];
    [[explainer cell] setLineBreakMode: NSLineBreakByWordWrapping];
    [explainer setStringValue: NSLocalizedString(
        @"“Other used” covers space we can’t account for: APFS local snapshots, sibling system volumes (Preboot, Recovery, VM), other users’ home folders, and protected areas (Mail, Messages, etc.) that require Full Disk Access.",
        @"Pie panel explainer for Other-used wedge")];
    [explainer setAutoresizingMask: NSViewWidthSizable | NSViewMaxYMargin];
    [content addSubview: explainer];
}

- (NSTextField*) addLegendRowAtY: (CGFloat) y
                           color: (NSColor*) color
                            text: (NSString*) text
{
    NSView *content = [[self window] contentView];
    CGFloat w = NSWidth([content bounds]);

    NSRect swatchFrame = NSMakeRect(14, y + 4, 12, 12);
    NSView *swatch = [[[NSView alloc] initWithFrame: swatchFrame] autorelease];
    [swatch setWantsLayer: YES];
    [[swatch layer] setBackgroundColor: [color CGColor]];
    [[swatch layer] setCornerRadius: 2];
    [swatch setAutoresizingMask: NSViewMaxYMargin];
    [content addSubview: swatch];

    NSRect labelFrame = NSMakeRect(34, y, w - 44, 20);
    NSTextField *label = [[[NSTextField alloc] initWithFrame: labelFrame] autorelease];
    [label setEditable: NO];
    [label setSelectable: NO];
    [label setBezeled: NO];
    [label setBordered: NO];
    [label setDrawsBackground: NO];
    [label setFont: [NSFont systemFontOfSize: [NSFont smallSystemFontSize]]];
    [label setTextColor: [NSColor labelColor]];
    [label setStringValue: text];
    [label setAutoresizingMask: NSViewWidthSizable | NSViewMaxYMargin];
    [content addSubview: label];

    return label;
}

- (void) showPanel
{
    NSWindow *panel = [self window];

    // First show: park to the right of the parent window. Autosave takes
    // over after that.
    if ( ![panel setFrameUsingName: @"DIXDiskUsagePiePanel"] && _parentWindow != nil )
    {
        NSRect pf = [_parentWindow frame];
        NSRect wf = [panel frame];
        wf.origin.x = NSMaxX(pf) + 12;
        wf.origin.y = NSMaxY(pf) - NSHeight(wf);
        [panel setFrame: wf display: NO];
    }

    [self refresh];
    [panel orderFront: nil];
}

- (void) onItemsChanged: (NSNotification*) note
{
    [self refresh];
}

- (void) refresh
{
    if ( _document == nil ) return;
    NSURL *scanURL = [_document fileURL];
    if ( scanURL == nil ) return;

    NSError *err = nil;
    NSDictionary *fsAttrs = [[NSFileManager defaultManager]
                             attributesOfFileSystemForPath: [scanURL path]
                             error: &err];
    if ( fsAttrs == nil )
        return;

    unsigned long long totalBytes = [[fsAttrs objectForKey: NSFileSystemSize] unsignedLongLongValue];
    unsigned long long freeBytes  = [[fsAttrs objectForKey: NSFileSystemFreeSize] unsignedLongLongValue];
    unsigned long long usedBytes  = (totalBytes > freeBytes) ? (totalBytes - freeBytes) : 0;

    FSItem *root = [_document rootItem];
    unsigned long long scannedBytes = (root != nil) ? [root sizeValue] : 0;

    // If our scanned figure exceeds the volume's reported used (can happen
    // with copy-on-write filesystems counting logical sizes), clamp to used
    // so the "other used" wedge doesn't go negative.
    if ( scannedBytes > usedBytes ) scannedBytes = usedBytes;
    unsigned long long otherUsed = usedBytes - scannedBytes;

    [_pieView setScannedBytes: scannedBytes
               otherUsedBytes: otherUsed
                    freeBytes: freeBytes];

    [_scannedLabel   setStringValue: [self legendTextFor: scannedBytes ofTotal: totalBytes
                                                   label: NSLocalizedString(@"Scanned",    @"")]];
    [_otherUsedLabel setStringValue: [self legendTextFor: otherUsed    ofTotal: totalBytes
                                                   label: NSLocalizedString(@"Other used", @"")]];
    [_freeLabel      setStringValue: [self legendTextFor: freeBytes    ofTotal: totalBytes
                                                   label: NSLocalizedString(@"Free",       @"")]];
}

// Format a wedge legend line as "Label: 123.4 GB  (12.3%)".
// Always GB so the three legend rows are easy to compare.
- (NSString*) legendTextFor: (unsigned long long) bytes
                    ofTotal: (unsigned long long) total
                      label: (NSString*) label
{
    double gb = (double) bytes / (1000.0 * 1000.0 * 1000.0);
    double pct = total > 0 ? (100.0 * (double) bytes / (double) total) : 0;
    return [NSString stringWithFormat: @"%@: %.1f GB  (%.1f%%)", label, gb, pct];
}

@end
