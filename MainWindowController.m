//
//  MainWindowController.m
//  Disk Inventory Z
//
//  Created by Tjark Derlien on Mon Sep 29 2003.
//
//  Copyright (C) 2003 Tjark Derlien.
//  Modifications © 2026 Dani Sarfati.
//  
//  This program is free software; you can redistribute it and/or
//  modify it under the terms of the GNU General Public License
//  as published by the Free Software Foundation; either version 3
//  of the License, or any later version.
//

//

#import "MainWindowController.h"
#import "FSItem.h"
#import "InfoPanelController.h"
#import "SelectionListPanelController.h"
#import "DiskUsagePieController.h"
#import "Timing.h"
#import <TreeMapView/TreeMapView.h>
#import "FSItem-Utilities.h"
#import "FileSizeTransformer.h"
#import "AppsForItem.h"
#import "NSURL-Extensions.h"
#import "Preferences.h"
#import "DIXPieChartView.h"

// Popover content for the treemap-settings toolbar button. Three checkboxes
// bound to shared user defaults; treemap windows pick up changes via the
// KVO bridge in FileSystemDoc (ShowFreeSpace / ShowOtherSpace) and the
// at-zoom check in TreeMapViewController (AnimatedZooming).
@interface DIXTreeMapSettingsPopoverVC : NSViewController
@end

@interface MainWindowController(Private)
- (void) performMoveToTrashForItem: (FSItem*) selectedItem;
@end

@implementation MainWindowController

+ (void)initialize
{
    /* Make sure code only gets executed once. */
    static BOOL initialized = NO;
    if ( initialized )
		return;
    initialized = YES;
	
	//initalize support for the service menu
    NSArray *sendTypes = [NSArray arrayWithObjects: NSPasteboardTypeFileURL, nil];
    NSArray *returnTypes = [NSArray array];
	
	[NSApp registerServicesMenuSendTypes: sendTypes returnTypes: returnTypes];
}

- (id) initWithWindowNibName:(NSString *)windowNibName
{
	self = [super initWithWindowNibName: windowNibName];
	
	if ( self != nil )
	{
		//register volume transformers needed by various controls
		[NSValueTransformer setValueTransformer:[FileSizeTransformer transformer] forName: @"fileSizeTransformer"];
	}
	
	return self;
}

+ (FileSystemDoc*) documentForView: (NSView*) view
{
    FileSystemDoc* doc = nil;

    NSWindow *window = [view window];
    
    id delegate = [window delegate];
    NSAssert( delegate != nil, @"expecting to retrieve the document from the window controller, which should be the window's delegate; but the window has no delegte" );
    NSAssert( [delegate respondsToSelector: @selector(document)], @"window's delegate has no method 'document' to retrieve document object" );

	doc = [delegate document];
	NSAssert( [doc isKindOfClass: [FileSystemDoc class]], @"document object is not of expected kind 'FileSystemDoc'" );

    return doc;
}

+ (void) poofEffectInView: (NSView*)view inRect: (NSRect) rect //rect in view coords
{
	//center poof antimation in the rect
	NSPoint poofEffectPoint = NSMakePoint( NSMinX(rect) + NSWidth(rect)/2,
										   NSMinY(rect) + NSHeight(rect)/2);
	
	//coordinates for the poof effect must be in screen coordidates, so...
	//convert view to window coords
	poofEffectPoint = [view convertPoint: poofEffectPoint toView: nil];
	
	//convert window to screen coords
	poofEffectPoint = [[view window] convertPointToScreen: poofEffectPoint];
	
	NSSize size = NSMakeSize(NSWidth(rect), NSHeight(rect));
	
	//make sure the rect is not too small nor too large
	if ( fminf(size.width, size.height) <= 25 || ( size.width + size.height ) <= 80 )
		size = NSZeroSize;	//default size
	
	size.width = fminf( size.width, 200 );
	size.height = fminf( size.height, 200 );
	
	NSShowAnimationEffect(NSAnimationEffectPoof, poofEffectPoint, size, nil, (SEL)0, nil);
}

- (void) awakeFromNib
{
	// SplitWindowHorizontally controls the OUTER split orientation:
	// default (vertical=NO) → (files+kinds) on top, treemap on bottom.
	// If the user toggled "Split Vertically" historically, flip to L/R.
	if ( [[NSUserDefaults standardUserDefaults] boolForKey: SplitWindowHorizontally] )
	{
		[_splitter setVertical: NO];
	}

	// Use new autosave names: the old "MainWindowSplitter" key was written
	// by the previous files↔treemap OASplitView (vertical=YES, ~700pt wide)
	// and would now restore a geometrically meaningless divider position
	// into the new top/bottom outer split.
	//
	// setAutosaveName: is the modern API. The previous code called
	// setPositionAutosaveName:, which only existed on the OASplitView
	// wrapper class; the new splits are plain NSSplitView and would throw
	// "unrecognized selector".
	[_splitter setAutosaveName: @"DIXMainSplit_TopBottom"];
	[_kindsTopSplit setAutosaveName: @"DIXMainSplit_FilesKinds"];

	// Retain the loose selection-list view so it survives any future
	// re-parenting by the panel controller. The xib loader hands us a
	// top-level customView that no parent retains; without this it would
	// be released when first removed from a superview.
	[_selectionListPaneView retain];

	// Status bar at the bottom of the window with persistent scan totals.
	[self installStatusBar];
	[[NSNotificationCenter defaultCenter] addObserver: self
											 selector: @selector(updateStatusBar)
												 name: FSItemsChangedNotification
											   object: [self document]];
	[self updateStatusBar];

	// Stage 8.5 Wave 2: inline scan overlay (replaces the loading sheet).
	NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
	[nc addObserver: self selector: @selector(onScanStarted:)
			   name: DIXScanStartedNotification object: [self document]];
	[nc addObserver: self selector: @selector(onScanProgress:)
			   name: DIXScanProgressNotification object: [self document]];
	[nc addObserver: self selector: @selector(onScanFinished:)
			   name: DIXScanFinishedNotification object: [self document]];

	// The nib was authored on a larger display; the saved frame from
	// NSUserDefaults can exceed the user's current visibleFrame, pushing the
	// window's bottom (search field, status bar) off the screen. Clamp to
	// the screen's visibleFrame with a margin so every control is reachable.
	//
	// NSWindowController applies the saved frame (via -setFrameUsingName:)
	// during nib load, but on some launches the layout re-applies the saved
	// frame *after* awakeFromNib runs and undoes our clamp. Defer one extra
	// clamp to the next runloop turn so any post-awakeFromNib restoration
	// has settled by then.
	[self constrainWindowToScreen];
	dispatch_async(dispatch_get_main_queue(), ^{
		[self constrainWindowToScreen];

		// Replicate the layout cascade a manual window resize triggers —
		// the symptom we're fixing is that the table scrollViews start with
		// the document view positioned BEHIND the header, drawing row 0 at
		// the same Y as the column titles. AppKit's automatic re-tile only
		// fires when a scrollView's frame actually CHANGES, so an
		// unchanged-size relayout does nothing. Nudging the window's width
		// by 1pt and back forces the cascade.
		NSWindow *window = [self window];
		NSRect wf = [window frame];
		NSRect nudge = wf;
		nudge.size.width += 1;
		[window setFrame: nudge display: NO];
		[window setFrame: wf    display: YES];

		[self dixTileAllScrollViewsUnder: [[self window] contentView]];

		// The nudge can leave each scrollView's clipView with a non-zero
		// bounds origin, hiding row 0 above the visible area. Force-scroll
		// every NSTableView/NSOutlineView under contentView to row 0.
		[self dixScrollAllTableViewsToTopUnder: [[self window] contentView]];

		// Disk usage pie panel: auto-show when the scan root is a volume
		// mount point (i.e. a full-disk scan). Hidden for folder scans.
		[self showDiskUsagePieIfFullVolumeScan];

		// Move the singleton Info panel out of the way if its restored
		// frame covers the doc window's cancel overlay. Prefer placing
		// it directly under the disk-usage pie panel when that's up.
		[self repositionInfoPanelIfOverlapping];
	});
}

- (void) repositionInfoPanelIfOverlapping
{
	InfoPanelController *infoCtl = [InfoPanelController sharedController];
	if ( ![infoCtl panelIsVisible] )
		return;

	NSWindow *infoPanel = [infoCtl panel];
	NSWindow *docWindow = [self window];
	NSRect infoF = [infoPanel frame];
	NSRect docF  = [docWindow frame];

	NSWindow *pieWindow = (_diskUsagePiePanel != nil) ? [_diskUsagePiePanel window] : nil;
	BOOL coversPie = pieWindow != nil
	                 && [pieWindow isVisible]
	                 && NSIntersectsRect(infoF, [pieWindow frame]);
	BOOL coversDoc = NSIntersectsRect(infoF, docF);

	if ( !coversPie && !coversDoc )
		return;

	NSScreen *screen = [docWindow screen] ?: [NSScreen mainScreen];
	NSRect vis = [screen visibleFrame];

	if ( pieWindow != nil && [pieWindow isVisible] )
	{
		// Place directly under the pie panel, left-aligned to it.
		NSRect pieF = [pieWindow frame];
		infoF.origin.x = pieF.origin.x;
		infoF.origin.y = NSMinY(pieF) - infoF.size.height - 12;
		if ( infoF.origin.y < NSMinY(vis) )
			infoF.origin.y = NSMinY(vis);
	}
	else
	{
		// No pie panel — fall back to placing to the right of the doc.
		infoF.origin.x = NSMaxX(docF) + 20;
		if ( NSMaxX(infoF) > NSMaxX(vis) )
			infoF.origin.x = NSMaxX(vis) - infoF.size.width;
		infoF.origin.y = NSMaxY(docF) - infoF.size.height;
		if ( infoF.origin.y < NSMinY(vis) )
			infoF.origin.y = NSMinY(vis);
	}

	[infoPanel setFrame: infoF display: YES];
}

#pragma mark ----------------- Wave 2 inline scan overlay -----------------

// Build the centered scan-progress panel and attach it to the window's
// contentView so it floats above the splitter / outline / treemap. The
// doc window itself stays fully responsive (no sheet → no window-modal).
- (void) installScanOverlay
{
	if ( _scanOverlay != nil )
		return;

	NSView *content = [[self window] contentView];
	const CGFloat W = 460;
	const CGFloat H = 150;

	NSRect cf = [content bounds];
	NSRect overlayFrame = NSMakeRect( NSMidX(cf) - W/2, NSMidY(cf) - H/2, W, H );

	NSView *panel = [[NSView alloc] initWithFrame: overlayFrame];
	[panel setWantsLayer: YES];
	panel.layer.backgroundColor = [[NSColor windowBackgroundColor] CGColor];
	panel.layer.cornerRadius = 10;
	panel.layer.borderWidth = 1;
	panel.layer.borderColor = [[NSColor separatorColor] CGColor];
	[panel setAutoresizingMask: NSViewMinXMargin | NSViewMaxXMargin
								| NSViewMinYMargin | NSViewMaxYMargin];

	// Spinner (top-left)
	NSProgressIndicator *spinner = [[NSProgressIndicator alloc]
		initWithFrame: NSMakeRect(16, H - 36, 20, 20)];
	[spinner setStyle: NSProgressIndicatorStyleSpinning];
	[spinner setControlSize: NSControlSizeSmall];
	[spinner setDisplayedWhenStopped: NO];
	[spinner startAnimation: nil];
	[panel addSubview: spinner];

	// Title
	NSTextField *title = [NSTextField labelWithString:
		NSLocalizedString(@"Scanning…", @"")];
	[title setFrame: NSMakeRect(44, H - 36, W - 60, 20)];
	[title setFont: [NSFont boldSystemFontOfSize: [NSFont systemFontSize]]];
	[panel addSubview: title];

	// Path (single-line, truncating middle)
	NSTextField *path = [NSTextField labelWithString: @""];
	[path setFrame: NSMakeRect(16, H - 64, W - 32, 18)];
	[path setFont: [NSFont systemFontOfSize: [NSFont smallSystemFontSize]]];
	[path setTextColor: [NSColor secondaryLabelColor]];
	[[path cell] setLineBreakMode: NSLineBreakByTruncatingMiddle];
	[panel addSubview: path];
	_scanOverlayPathLabel = path;

	// Count
	NSTextField *count = [NSTextField labelWithString: @""];
	[count setFrame: NSMakeRect(16, H - 86, W - 32, 18)];
	[count setFont: [NSFont monospacedDigitSystemFontOfSize: [NSFont smallSystemFontSize]
													 weight: NSFontWeightRegular]];
	[count setTextColor: [NSColor secondaryLabelColor]];
	[panel addSubview: count];
	_scanOverlayCountLabel = count;

	// Elapsed wall clock
	NSTextField *elapsed = [NSTextField labelWithString: @"Elapsed: 00:00"];
	[elapsed setFrame: NSMakeRect(16, H - 108, W - 32, 18)];
	[elapsed setFont: [NSFont monospacedDigitSystemFontOfSize: [NSFont smallSystemFontSize]
													   weight: NSFontWeightRegular]];
	[elapsed setTextColor: [NSColor secondaryLabelColor]];
	[panel addSubview: elapsed];
	_scanOverlayElapsedLabel = elapsed;

	// Cancel button (bottom-right)
	NSButton *cancel = [NSButton buttonWithTitle: NSLocalizedString(@"Cancel", @"")
										  target: self
										  action: @selector(scanOverlayCancelPressed:)];
	NSRect bf = [cancel frame];
	bf.origin.x = W - bf.size.width - 16;
	bf.origin.y = 12;
	[cancel setFrame: bf];
	[cancel setKeyEquivalent: @"\e"]; // Esc
	[panel addSubview: cancel];
	_scanOverlayCancelButton = cancel;
	_scanOverlaySpinner = spinner;

	[content addSubview: panel];
	_scanOverlay = panel;
}

- (void) tearDownScanOverlay
{
	if ( _scanOverlayClockTimer != nil )
	{
		[_scanOverlayClockTimer invalidate];
		_scanOverlayClockTimer = nil; // unsafe-unretained (runloop owned)
	}
	[_scanOverlayStartedAt release];
	_scanOverlayStartedAt = nil;

	if ( _scanOverlay == nil )
		return;
	[_scanOverlaySpinner stopAnimation: nil];
	[_scanOverlay removeFromSuperview];
	[_scanOverlay release];
	_scanOverlay = nil;
	// Subviews dropped with the panel; clear cached refs.
	_scanOverlayPathLabel = nil;
	_scanOverlayCountLabel = nil;
	_scanOverlayElapsedLabel = nil;
	_scanOverlaySpinner = nil;
	_scanOverlayCancelButton = nil;
}

- (void) onScanStarted: (NSNotification*) note
{
	[self installScanOverlay];
	[_scanOverlayPathLabel setStringValue: note.userInfo[DIXScanPath] ?: @""];
	[_scanOverlayCountLabel setStringValue: @""];

	[_scanOverlayStartedAt release];
	_scanOverlayStartedAt = [[NSDate date] retain];
	// Runloop retains the timer; we hold an unsafe-unretained reference
	// just to call -invalidate from -tearDownScanOverlay.
	_scanOverlayClockTimer = [NSTimer scheduledTimerWithTimeInterval: 1.0
															  target: self
															selector: @selector(tickScanOverlayClock:)
															userInfo: nil
															 repeats: YES];
	[self tickScanOverlayClock: nil];
}

- (void) tickScanOverlayClock: (NSTimer*) t
{
	if ( _scanOverlayElapsedLabel == nil || _scanOverlayStartedAt == nil )
		return;
	NSTimeInterval secs = -[_scanOverlayStartedAt timeIntervalSinceNow];
	if ( secs < 0 ) secs = 0;
	unsigned long total = (unsigned long) secs;
	unsigned mm = (unsigned)(total / 60);
	unsigned ss = (unsigned)(total % 60);
	[_scanOverlayElapsedLabel setStringValue:
		[NSString stringWithFormat: NSLocalizedString(@"Elapsed: %02u:%02u", @""), mm, ss]];
}

- (void) onScanProgress: (NSNotification*) note
{
	if ( _scanOverlay == nil )
		return;
	NSString *path = note.userInfo[DIXScanPath] ?: @"";
	NSNumber *items = note.userInfo[DIXScanItemCount] ?: @0;

	NSNumberFormatter *fmt = [[[NSNumberFormatter alloc] init] autorelease];
	[fmt setNumberStyle: NSNumberFormatterDecimalStyle];
	[fmt setUsesGroupingSeparator: YES];

	[_scanOverlayPathLabel setStringValue: path];
	[_scanOverlayCountLabel setStringValue:
		[NSString stringWithFormat: NSLocalizedString(@"%@ items scanned", @""),
			[fmt stringFromNumber: items]]];
}

- (void) onScanFinished: (NSNotification*) note
{
	[self tearDownScanOverlay];
}

- (IBAction) scanOverlayCancelPressed: (id) sender
{
	[_scanOverlayCancelButton setEnabled: NO];
	[(FileSystemDoc*) [self document] requestCancelScan];
}

// YES if the doc's fileURL points at a volume mount point (the URL's
// own URL is its volume URL). NO for folder-only scans.
- (BOOL) docIsFullVolumeScan
{
	NSURL *url = [[self document] fileURL];
	if ( url == nil ) return NO;

	NSURL *volumeURL = nil;
	if ( ![url getResourceValue: &volumeURL
	                     forKey: NSURLVolumeURLKey
	                      error: nil]
	     || volumeURL == nil )
	{
		return NO;
	}

	// Compare resolved paths so trailing-slash / symlink differences
	// don't cause false negatives.
	NSString *a = [[url URLByStandardizingPath] path];
	NSString *b = [[volumeURL URLByStandardizingPath] path];
	return [a isEqualToString: b];
}

- (void) showDiskUsagePieIfFullVolumeScan
{
	if ( _diskUsagePiePanel != nil )
		return;  // already created/showing
	if ( ![self docIsFullVolumeScan] )
		return;

	_diskUsagePiePanel = [[DiskUsagePieController alloc]
		initWithDocument: (FileSystemDoc*) [self document]
		    parentWindow: [self window]];
	[_diskUsagePiePanel showPanel];
}

- (void) constrainWindowToScreen
{
	NSWindow *window = [self window];
	NSScreen *screen = [window screen] ?: [NSScreen mainScreen];
	if ( screen == nil )
		return;

	const CGFloat margin = 20;
	// Drawers are gone: the window no longer extends past its frame, so
	// the only constraint is "fit on the screen's visible area".
	NSRect visible = [screen visibleFrame];
	NSRect wf      = [window frame];

	BOOL changed = NO;

	CGFloat maxHeight = NSHeight(visible) - margin;
	if ( NSHeight(wf) > maxHeight )
	{
		wf.size.height = maxHeight;
		changed = YES;
	}

	CGFloat maxWidth = NSWidth(visible) - margin;
	if ( NSWidth(wf) > maxWidth )
	{
		wf.size.width = maxWidth;
		changed = YES;
	}

	// After resizing, re-park inside the visible frame.
	if ( NSMaxY(wf) > NSMaxY(visible) )
	{
		wf.origin.y = NSMaxY(visible) - NSHeight(wf);
		changed = YES;
	}
	if ( NSMinY(wf) < NSMinY(visible) )
	{
		wf.origin.y = NSMinY(visible);
		changed = YES;
	}
	if ( NSMaxX(wf) > NSMaxX(visible) )
	{
		wf.origin.x = NSMaxX(visible) - NSWidth(wf);
		changed = YES;
	}
	if ( NSMinX(wf) < NSMinX(visible) )
	{
		wf.origin.x = NSMinX(visible);
		changed = YES;
	}

	if ( changed )
		[window setFrame: wf display: YES];
}

#pragma mark ----------------- bottom status bar -----------------

// Inject a small text field along the bottom of the window's content view.
// Shows the original scan root, total size and file count -- stable through
// zooming, unlike the window title (which reflects the zoomed item).
// Recursively re-tile every NSScrollView under `root`. Called after we shift
// subview frames by setFrame: (same size, new origin) -- AppKit doesn't
// re-tile NSScrollView in that case so the header view ends up overlapping
// the first content row.
- (void) dixTileAllScrollViewsUnder: (NSView*) root
{
	if ( [root isKindOfClass: [NSScrollView class]] )
		[(NSScrollView*)root tile];
	for ( NSView *child in [root subviews] )
		[self dixTileAllScrollViewsUnder: child];
}

// Walk the view tree and scroll any NSTableView/NSOutlineView to its
// first row. Used after the initial layout nudge so users don't open a
// document with the file list pre-scrolled past the top.
- (void) dixScrollAllTableViewsToTopUnder: (NSView*) root
{
	if ( [root isKindOfClass: [NSTableView class]] )
	{
		NSTableView *tv = (NSTableView*) root;
		if ( [tv numberOfRows] > 0 )
			[tv scrollRowToVisible: 0];
	}
	for ( NSView *child in [root subviews] )
		[self dixScrollAllTableViewsToTopUnder: child];
}

- (void) installStatusBar
{
	NSView *content = [[self window] contentView];
	const CGFloat barHeight = 22;

	// Grow window upward so existing controls don't have to move down.
	NSRect wf = [[self window] frame];
	wf.origin.y    -= barHeight;
	wf.size.height += barHeight;
	[[self window] setFrame: wf display: NO];

	// Shift existing subviews up by barHeight so the bottom strip is free.
	// Then force any NSScrollView descendants to re-tile: setFrame: with the
	// same size only changes origin, and NSScrollView's internal layout
	// (header view position, clip view position) re-tiles automatically on
	// SIZE changes but not on pure origin shifts. Without the explicit -tile
	// the header and the first content row can end up at the same y inside
	// the scroll view, drawing on top of each other.
	for ( NSView *v in [content subviews] )
	{
		NSRect r = [v frame];
		r.origin.y += barHeight;
		[v setFrame: r];
	}
	[self dixTileAllScrollViewsUnder: content];

	NSTextField *f = [[NSTextField alloc] initWithFrame:
		NSMakeRect( 12, 3, [content bounds].size.width - 24, barHeight - 6 )];
	[f setEditable: NO];
	[f setSelectable: YES];
	[f setBezeled: NO];
	[f setBordered: NO];
	[f setDrawsBackground: NO];
	[f setFont: [NSFont systemFontOfSize: [NSFont smallSystemFontSize]]];
	[f setTextColor: [NSColor secondaryLabelColor]];
	[f setLineBreakMode: NSLineBreakByTruncatingMiddle];
	[f setStringValue: @""];
	[f setAutoresizingMask: NSViewWidthSizable | NSViewMaxYMargin];
	[content addSubview: f];
	_statusBar = f;
	[f release];
}

- (void) updateStatusBar
{
	if ( _statusBar == nil ) return;
	FileSystemDoc *doc = [self document];
	FSItem *root = [doc rootItem];
	if ( root == nil )
	{
		[_statusBar setStringValue: @""];
		return;
	}

	FileSizeFormatter *sizeFmt = [[[FileSizeFormatter alloc] init] autorelease];
	NSString *sizeStr = [sizeFmt stringForObjectValue: [root size]];

	NSNumberFormatter *numFmt = [[[NSNumberFormatter alloc] init] autorelease];
	[numFmt setNumberStyle: NSNumberFormatterDecimalStyle];
	[numFmt setUsesGroupingSeparator: YES];
	[numFmt setGroupingSeparator: @","];
	NSString *filesStr = [numFmt stringFromNumber: @((unsigned long) g_fileCount + (unsigned long) g_folderCount)];

	[_statusBar setStringValue: [NSString stringWithFormat: @"%@   ·   %@   ·   %@ files",
		[root path], sizeStr, filesStr]];
}

- (void) showSelectionListPanel
{
	if ( _selectionListPanel == nil )
	{
		_selectionListPanel = [[SelectionListPanelController alloc]
			initWithContentView: _selectionListPaneView
			       parentWindow: [self window]];
	}
	[_selectionListPanel showPanel];
}

#pragma mark -----------------menu and toolbar actions-----------------------

// Name kept (toggleFileKindsDrawer:) so existing menu/toolbar bindings work.
// Action now collapses/expands the kinds-table pane within the top split.
- (IBAction)toggleFileKindsDrawer:(id)sender
{
	if ( _kindsTopSplit == nil || _kindsPaneView == nil )
		return;

	NSRect splitBounds = [_kindsTopSplit bounds];
	CGFloat extent = [_kindsTopSplit isVertical] ? NSWidth(splitBounds) : NSHeight(splitBounds);

	// Check by actual pane width — more reliable than isSubviewCollapsed:
	// which can lie if we collapsed by pushing the divider rather than
	// using NSSplitView's first-class collapse API.
	NSRect kindsBounds = [_kindsPaneView frame];
	CGFloat kindsExtent = [_kindsTopSplit isVertical] ? NSWidth(kindsBounds) : NSHeight(kindsBounds);
	BOOL collapsed = ( kindsExtent < 2 );

	if ( collapsed )
	{
		// Expand: park the divider so the files pane occupies 67% of the
		// split, leaving 33% for the kinds pane (the designed default).
		[_kindsTopSplit setPosition: floor(extent * 0.67) ofDividerAtIndex: 0];
	}
	else
	{
		// Collapse: push the divider all the way to the trailing edge.
		[_kindsTopSplit setPosition: extent ofDividerAtIndex: 0];
	}
	[_kindsTopSplit adjustSubviews];
}

// Name kept; now toggles the floating selection-list panel.
- (IBAction) toggleSelectionListDrawer:(id)sender
{
	if ( _selectionListPanel == nil )
	{
		[self showSelectionListPanel];
		return;
	}
	[_selectionListPanel togglePanel: sender];
}

- (IBAction) openFile:(id)sender
{
	NSParameterAssert( [sender isKindOfClass: [NSMenuItem class]] );
	NSMenuItem *menuItem = (NSMenuItem*) sender;
	
	FSItem *selectedItem = [(FileSystemDoc*)[self document] selectedItem];
	NSURL *appURL = [menuItem representedObject];
	
	if ( appURL == nil )
		appURL = [[AppsForItem appsForItemURL: [selectedItem fileURL]] defaultAppURL];
	
	[AppsForItem openItemURL: [selectedItem fileURL] withAppURL: appURL];
}

- (IBAction) zoomIn:(id)sender
{
    FSItem *selectedItem = [(FileSystemDoc*)[self document] selectedItem];

    if ( selectedItem != nil && [selectedItem isFolder] )
    {
        [[self document] zoomIntoItem: selectedItem];

        [self synchronizeWindowTitleWithDocumentName];
    }
}

- (IBAction) zoomOut:(id)sender
{
    FileSystemDoc *doc = [self document];
    
    FSItem *currentZoomedItem = [doc zoomedItem];

    if ( currentZoomedItem != [doc rootItem] )
    {
        [doc zoomOutOneStep];

        [doc setSelectedItem: currentZoomedItem];

        [self synchronizeWindowTitleWithDocumentName];
    }
}

- (IBAction) zoomOutTo:(id)sender
{
    FileSystemDoc *doc = [self document];
	FSItem *item = [sender representedObject];
	
	NSParameterAssert( [doc rootItem] == [item root] );
	NSParameterAssert( [[doc zoomStack] indexOfObjectIdenticalTo: item] != NSNotFound );
	
    FSItem *currentZoomedItem = [doc zoomedItem];
		
	[doc zoomOutToItem: item];
	
	[doc setSelectedItem: currentZoomedItem];
	
	[self synchronizeWindowTitleWithDocumentName];
}

- (IBAction) showInFinder:(id)sender
{
    FSItem *selectedItem = [(FileSystemDoc*)[self document] selectedItem];

    if ( selectedItem != nil && [selectedItem exists] )
        [[NSWorkspace sharedWorkspace] selectFile: [selectedItem path] inFileViewerRootedAtPath: @""];
}

- (IBAction) refresh:(id)sender
{
	FileSystemDoc *doc = [self document];
    FSItem *selectedItem = [doc selectedItem];
	
	if ( selectedItem == nil )
		return;
	
	[doc refreshItem: selectedItem];
	
	//the zoomed item might have changed
	[self synchronizeWindowTitleWithDocumentName];
}	

- (IBAction) refreshAll:(id)sender
{
	[[self document] refreshItem: nil];
	
	//the zoomed item might have changed
	[self synchronizeWindowTitleWithDocumentName];
}	

- (IBAction) moveToTrash:(id)sender
{
	FileSystemDoc *doc = [self document];
    FSItem *selectedItem = [doc selectedItem];
	
	if ( selectedItem == nil || selectedItem == [doc zoomedItem] || [selectedItem isSpecialItem] )
		return;
	
	//if file/folder lies on a network volume, it will be deleted!
	//So warn the user and ask to proceed.
	//(only local items can be moved to trash)
	if ( ![[selectedItem fileURL] isLocalVolume] )
	{
		NSString *msg = [NSString stringWithFormat: NSLocalizedString(@"The item \"%@\" could not be moved to the trash.",@""),
													[selectedItem displayName]];

		NSAlert *alert = [[[NSAlert alloc] init] autorelease];
		alert.messageText = msg;
		alert.informativeText = NSLocalizedString(@"Would you like to delete it immediately?",@"");
		[alert addButtonWithTitle: NSLocalizedString(@"No",@"")];  //first button is default (Return key)
		[alert addButtonWithTitle: NSLocalizedString(@"Yes",@"")];
		[alert beginSheetModalForWindow: [self window] completionHandler: ^(NSModalResponse returnCode)
		{
			if ( returnCode == NSAlertSecondButtonReturn ) //"Yes"
				[self performMoveToTrashForItem: selectedItem];
		}];
	}
	else
	{
		[self performMoveToTrashForItem: selectedItem];
	}
}

- (IBAction) showPackageContents:(id)sender
{
    FileSystemDoc *doc = [self document];
	
    [doc setShowPackageContents: ![doc showPackageContents]];
}

- (IBAction) showFreeSpace:(id)sender
{
    FileSystemDoc *doc = [self document];
	
    [doc setShowFreeSpace: ![doc showFreeSpace]];
}

- (IBAction) showOtherSpace:(id)sender
{
    FileSystemDoc *doc = [self document];
	
    [doc setShowOtherSpace: ![doc showOtherSpace]];
}

- (IBAction) selectParentItem:(id)sender
{
    FileSystemDoc *doc = [self document];
    
    FSItem *selectedItem = [doc selectedItem];

	//don't set selection to parent if selected item is zoomed item or one of it's direct childs
    if ( selectedItem != [doc zoomedItem] && [selectedItem parent] != [doc zoomedItem] )
    {
        [doc setSelectedItem: [selectedItem parent]];
    }
}

- (IBAction) changeSplitting:(id)sender
{
	[_splitter setVertical: ![_splitter isVertical]];
	
	[[[self window] contentView] setNeedsDisplay: TRUE];
}

- (IBAction) showInformationPanel:(id)sender
{
	InfoPanelController *infoController = [InfoPanelController sharedController];
	
	if ( [infoController panelIsVisible] )
		[infoController hidePanel];
	else
	{
		FSItem *item = [(FileSystemDoc*)[self document] selectedItem];
		[infoController showPanelWithFSItem: item];
	}
}

- (IBAction) showPhysicalSizes:(id) sender
{
	FileSystemDoc *doc = [self document];
	
	[doc setShowPhysicalFileSize: ![doc showPhysicalFileSize]];
	
	[self synchronizeWindowTitleWithDocumentName];
}

- (IBAction) ignoreCreatorCode:(id) sender
{
	FileSystemDoc *doc = [self document];
	
	[doc setIgnoreCreatorCode: ![doc ignoreCreatorCode]];
}

- (IBAction) performRenderBenchmark:(id)sender
{
	uint64_t startTime = getTime();
	
	unsigned count = 20;
	
	[_treeMapView benchmarkRenderingWithImageSize: NSMakeSize( 1024, 768 ) count: count];
	
	uint64_t doneTime = getTime();
	
	NSString *msg = [NSString stringWithFormat: @"rendering %u times took %.2f seconds", count, subtractTime(doneTime, startTime)];
	NSAlert *alert = [[[NSAlert alloc] init] autorelease];
	alert.alertStyle = NSAlertStyleInformational;
	alert.messageText = msg;
	[alert beginSheetModalForWindow: [_splitter window] completionHandler: nil];
}

- (IBAction) performLayoutBenchmark:(id)sender
{
	uint64_t startTime = getTime();
	
	unsigned count = 100;
	
	[_treeMapView benchmarkLayoutCalculationWithImageSize: NSMakeSize( 1024, 768 ) count: count];
	
	uint64_t doneTime = getTime();
	
	NSString *msg = [NSString stringWithFormat: @"layout calculation %u times took %.2f seconds", count, subtractTime(doneTime, startTime)];
	NSAlert *alert = [[[NSAlert alloc] init] autorelease];
	alert.alertStyle = NSAlertStyleInformational;
	alert.messageText = msg;
	[alert beginSheetModalForWindow: [_splitter window] completionHandler: nil];
}

#pragma mark -----------------UI elment validation-----------------------

- (BOOL) validateUserInterfaceItem: (id<NSValidatedUserInterfaceItem>) item
{
    FileSystemDoc *doc = [self document];
    FSItem *selectedItem = [doc selectedItem];
	SEL menuAction = [item action];
	// Body below uses -setTitle: / -setState: on `menuItem`. Preserve the
	// pre-existing pattern: cast `item` to NSMenuItem* and let the
	// macro's isKindOfClass: check decide whether to actually fire
	// -setState: (the legacy code already handled NSToolbarItemValidationAdapter
	// via that same check).
	NSMenuItem *menuItem = (NSMenuItem*) item;

#define SET_TITLE( condition, string1, string2 ) \
	[menuItem setTitle: NSLocalizedString( (condition) ? string1 : string2, @"")]
		
#define SET_TITLE_AND_IMAGE( condition, string1, string2 )	\
	SET_TITLE( (condition), string1, string2 );				\
	if ( [menuItem isKindOfClass: [NSToolbarItemValidationAdapter class]] )\
		 [menuItem setState: (condition) ? NSControlStateValueOff : NSControlStateValueOn];
	
    if ( menuAction == @selector(openFile:)
		 || menuAction == @selector(openFileWith:) )
    {
        if ( selectedItem == nil )
			NO;
		
		AppsForItem *apps = [AppsForItem appsForItemURL: [selectedItem fileURL]];
		return [apps defaultAppURL] != nil;
    }
    else if ( menuAction == @selector(zoomIn:) )
    {
        return selectedItem != nil && [selectedItem isFolder] && ![_treeMapView zoomingInProgress];
    }
    else if ( menuAction == @selector(zoomOut:) )
    {
        return [doc rootItem] != [doc zoomedItem] && ![_treeMapView zoomingInProgress];
    }
    else if ( menuAction == @selector(showInFinder:)
			  || menuAction == @selector(refresh:))
    {
        return selectedItem != nil;
    }
    else if ( menuAction == @selector(moveToTrash:) )
    {
		//the trash folder and items residing in it can't be moved to trash
		BOOL selectItemResidesInTrash = NO;
		if ( selectedItem != nil )
		{
            NSURL *selectedURL = [selectedItem fileURL];

            NSURL *trashURL = [[NSFileManager defaultManager] URLForDirectory:NSTrashDirectory inDomain:NSUserDomainMask appropriateForURL:selectedURL create:NO error:nil];
            
			if ( trashURL != nil )
			{
                selectItemResidesInTrash = [selectedURL isEqualToURL: trashURL] || [selectedURL residesInDirectoryURL:trashURL];
			}
		}
        return !selectItemResidesInTrash && selectedItem != nil && selectedItem != [doc zoomedItem] && ![selectedItem isSpecialItem];
    }
    else if ( menuAction == @selector(showPackageContents:) )
    {
        SET_TITLE_AND_IMAGE( [doc showPackageContents], @"Hide Package Contents", @"Show Package Contents" );
    }
    else if ( menuAction == @selector(showFreeSpace:) )
    {
        SET_TITLE_AND_IMAGE( [doc showFreeSpace], @"Hide Free Space", @"Show Free Space" );
    }
    else if ( menuAction == @selector(showOtherSpace:) )
    {
        SET_TITLE_AND_IMAGE( [doc showOtherSpace], @"Hide Other Space", @"Show Other Space" );
		if ( [[[doc zoomedItem] fileURL] isVolume] )
			return NO;
    }
    else if ( menuAction == @selector(showPhysicalSizes:) )
    {
        SET_TITLE_AND_IMAGE( [doc showPhysicalFileSize], @"Show Logical File Size", @"Show Physical File Size" );
    }
    else if ( menuAction == @selector(ignoreCreatorCode:) )
    {
        SET_TITLE_AND_IMAGE( [doc ignoreCreatorCode], @"Respect Creator Code", @"Ignore Creator Code" );
    }
    else if ( menuAction == @selector(toggleFileKindsDrawer:) )
    {
        BOOL kindsHidden = ( _kindsTopSplit == nil )
                        || ( _kindsPaneView == nil )
                        || [_kindsTopSplit isSubviewCollapsed: _kindsPaneView];
        SET_TITLE_AND_IMAGE( kindsHidden,
							 @"Show File Kind Statistics", @"Hide File Kind Statistics" );
    }
    else if ( menuAction == @selector(toggleSelectionListDrawer:) )
    {
        BOOL panelHidden = ( _selectionListPanel == nil )
                        || ![[_selectionListPanel window] isVisible];
        SET_TITLE( panelHidden,
							 @"Show Selection List", @"Hide Selection List" );
    }
    else if ( menuAction == @selector(selectParentItem:) )
    {
        return selectedItem != nil && selectedItem != [doc zoomedItem];
    }   
    else if ( menuAction == @selector(showInformationPanel:) )
    {
        SET_TITLE_AND_IMAGE( [[InfoPanelController sharedController] panelIsVisible],
							 @"Hide Information", @"Show Information" );
    }   
    else if ( menuAction == @selector(changeSplitting:) )
    {
        SET_TITLE( [_splitter isVertical], @"Split Horizontally", @"Split Vertically" );
    }   
    
#undef SET_TITLE
#undef SET_TITLE_AND_IMAGE
	
    return YES;
}

#pragma mark -----------------Toolbar support---------------------

//used by OAToolbarWindowController to load the toolbar configuration file (.toolbar)
- (NSString *)toolbarConfigurationName;
{
    return @"MainWindowToolbar";
}

#pragma mark -----------------NSWindow delegates-----------------------

- (void)windowDidBecomeMain:(NSNotification *)aNotification
{
	if ( [[InfoPanelController sharedController] panelIsVisible] )
	{
		FSItem *item = [(FileSystemDoc*)[self document] selectedItem];
		[[InfoPanelController sharedController] showPanelWithFSItem: item];
	}
}

- (void)windowDidResignMain:(NSNotification *)notification;
{
}

- (void)windowWillClose:(NSNotification *)aNotification
{
	if ( [[aNotification object] isMainWindow]
		&& [[InfoPanelController sharedController] panelIsVisible] )
	{
		[[InfoPanelController sharedController] showPanelWithFSItem: nil];
	}

	// Close the doc's ancillary floating panels so they don't linger on
	// screen after the main window goes away.
	if ( _selectionListPanel != nil )
		[[_selectionListPanel window] orderOut: nil];
	if ( _diskUsagePiePanel != nil )
		[[_diskUsagePiePanel window] orderOut: nil];
}

#pragma mark -----------------NSMenu delegates-----------------------

//populates the "Open With" sub menu which the default and additional applications which can open the selected file
- (void) menuNeedsUpdate: (NSMenu*) menu
{	
	NSParameterAssert( _openWithSubMenu == menu );
	
    FSItem *selectedItem = [(FileSystemDoc*)[self document] selectedItem];
	if ( selectedItem == nil )
		return;
	
	AppsForItem *apps = [AppsForItem appsForItemURL: [selectedItem fileURL]];
	
	NSMenuItem *menuItem = nil;
	NSURL *appURL = [apps defaultAppURL];
	
	if ( appURL != nil )
	{
		//the first and second menu item is the default app and a serperator item
		if ( [_openWithSubMenu numberOfItems] == 0 )
		{
			[_openWithSubMenu addItem: [[[NSMenuItem alloc] init] autorelease]];
			[_openWithSubMenu addItem: [NSMenuItem separatorItem]];
		}

		menuItem = [_openWithSubMenu itemAtIndex: 0];
		
		[menuItem setTitle:             [appURL displayName]];
		[menuItem setToolTip:           [appURL displayPath]];
		[menuItem setRepresentedObject: appURL];
		[menuItem setTarget:            self];
		[menuItem setAction:            @selector(openFile:)];
        // set icon
        {
            NSImage *icon = [appURL icon];
            [icon setSize:NSMakeSize(16,16)];
            [menuItem setImage: icon];
        }
        
		NSArray<NSURL*> *appURLs = [apps additionalAppURLs];
		for ( unsigned i = 0; i < [appURLs count]; i++ )
		{
			unsigned menuItemIndex = i+2;
			if ( menuItemIndex >= ((unsigned) [_openWithSubMenu numberOfItems]) )
				[_openWithSubMenu addItem: [[[NSMenuItem alloc] init] autorelease]];
			
			menuItem = [_openWithSubMenu itemAtIndex: menuItemIndex];
			appURL = [appURLs objectAtIndex: i];
			
			[menuItem setTitle:             [appURL displayName]];
			[menuItem setToolTip:           [appURL displayPath]];
			[menuItem setRepresentedObject: appURL];
			[menuItem setTarget:            self];
			[menuItem setAction:            @selector(openFile:)];
            
            NSImage *icon = [appURL icon];
            [icon setSize:NSMakeSize(16,16)];
            [menuItem setImage: icon];
		}
	}
	
	//remove any supernumerary menu items (removed all items if is there is no app which can open this file)
	unsigned removeMenuItemsFromIndex = ([apps defaultAppURL] != nil) ? [[apps additionalAppURLs] count] +2 : 0;
	
	while ( ((unsigned) [_openWithSubMenu numberOfItems]) > removeMenuItemsFromIndex )
		[_openWithSubMenu removeItemAtIndex: [_openWithSubMenu numberOfItems] -1];
}

#pragma mark -----------------service menu support-----------------------

- (id)validRequestorForSendType: (NSString *) sendType
					 returnType: (NSString *) returnType
{
	FSItem *selectedItem = [(FileSystemDoc*)[self document] selectedItem];
	
    if ( selectedItem != nil
		 && ![selectedItem isSpecialItem]
		 && [returnType length] == 0 //we don't accept any input, so returnType must be emty
		 && [selectedItem exists]
		 && [selectedItem supportsPasteboardType: sendType] )
	{
		return self;
    }
	
    return [super validRequestorForSendType: sendType returnType: returnType];
}

- (BOOL)writeSelectionToPasteboard:(NSPasteboard *)pboard
							 types:(NSArray *)types
{
	FSItem *item = [(FileSystemDoc*)[self document] selectedItem];

	if ( item != nil && ![item isSpecialItem] )
	{
		[item writeToPasteboard: pboard withTypes: types];
		return YES;
	}
	else
		return NO;
}

#pragma mark -----------------treemap-settings popover-----------------

- (NSToolbarItem *)toolbar:(NSToolbar *)tb
     itemForItemIdentifier:(NSString *)itemIdentifier
 willBeInsertedIntoToolbar:(BOOL)willInsert
{
	if ( [itemIdentifier isEqualToString: @"TreeMapSettings"] )
	{
		NSToolbarItem *item = [[[NSToolbarItem alloc] initWithItemIdentifier: itemIdentifier] autorelease];
		[item setLabel: NSLocalizedString(@"Settings", @"")];
		[item setPaletteLabel: NSLocalizedString(@"Settings", @"")];
		[item setToolTip: NSLocalizedString(@"Treemap display options", @"")];

		NSImage *img = [NSImage imageWithSystemSymbolName: @"gearshape"
								 accessibilityDescription: NSLocalizedString(@"Settings", @"")];

		NSButton *btn = [[NSButton alloc] initWithFrame: NSMakeRect(0, 0, 38, 28)];
		[btn setBezelStyle: NSBezelStyleTexturedRounded];
		[btn setImage: img];
		[btn setImagePosition: NSImageOnly];
		[btn setTarget: self];
		[btn setAction: @selector(showTreeMapSettingsPopover:)];
		[item setView: btn];
		[btn release];
		return item;
	}
	return [super toolbar: tb itemForItemIdentifier: itemIdentifier willBeInsertedIntoToolbar: willInsert];
}

- (IBAction) showTreeMapSettingsPopover: (id) sender
{
	if ( _treeMapSettingsPopover == nil )
	{
		_treeMapSettingsPopover = [[NSPopover alloc] init];
		[_treeMapSettingsPopover setBehavior: NSPopoverBehaviorTransient];
		DIXTreeMapSettingsPopoverVC *vc = [[[DIXTreeMapSettingsPopoverVC alloc] init] autorelease];
		[_treeMapSettingsPopover setContentViewController: vc];
	}

	NSView *anchor = [sender isKindOfClass: [NSView class]] ? (NSView*)sender : nil;
	if ( anchor == nil )
		return;

	[_treeMapSettingsPopover showRelativeToRect: [anchor bounds]
	                                     ofView: anchor
	                              preferredEdge: NSRectEdgeMinY];
}

- (void) dealloc
{
	[_treeMapSettingsPopover release];
	[super dealloc];
}

@end

@implementation MainWindowController(Private)

- (void) performMoveToTrashForItem: (FSItem*) selectedItem
{
	FileSystemDoc *doc = [self document];

	NSParameterAssert(	selectedItem != nil
						&& selectedItem != [doc zoomedItem] 
						&& ![selectedItem isSpecialItem] );
	
	//before we move the file/folder to trash, we need to calculate the position of the poof effect
	NSRect cellRect;
	NSView *view = nil;
	if ( [[self window] firstResponder] == _filesOutlineView )
	{
		view = _filesOutlineView;
		cellRect = [_filesOutlineView frameOfCellAtColumn: 0 row: [_filesOutlineView selectedRow]];
	}
	else
	{
		view = _treeMapView;
		cellRect = [_treeMapView itemRectByPathToItem: [selectedItem fsItemPathFromAncestor: [doc zoomedItem]]];
	}
	
	//now we can do it
    NSError *error = nil;
    if ( [doc moveItemToTrash: selectedItem error:&error] )
	{
		[[self class] poofEffectInView: view inRect: cellRect];
		
        [self synchronizeWindowTitleWithDocumentName];
	}
	else
	{
		//failed
        NSString *msg = [NSString stringWithFormat: NSLocalizedString(@"\"%@\" cannot be moved to the trash by Disk Inventory Z.",@""), [selectedItem displayName] ];
        NSString *subMsg = error.localizedFailureReason; //NSLocalizedString( @"Maybe you do not have sufficient access privileges.", @"" );

        NSAlert *alert = [[[NSAlert alloc] init] autorelease];
        alert.alertStyle = NSAlertStyleInformational;
        alert.messageText = msg;
        if ( subMsg != nil )
            alert.informativeText = subMsg;
        [alert beginSheetModalForWindow: [self window] completionHandler: nil];
 	}
}

@end

#pragma mark -----------------DIXTreeMapSettingsPopoverVC-----------------

@implementation DIXTreeMapSettingsPopoverVC

- (NSView*) makeRowWithSwatchColor: (NSColor*) color
                             title: (NSString*) title
                       defaultsKey: (NSString*) key
                       description: (NSString*) desc
{
	NSView *row = [[[NSView alloc] initWithFrame: NSZeroRect] autorelease];
	[row setTranslatesAutoresizingMaskIntoConstraints: NO];

	NSButton *check = [NSButton checkboxWithTitle: title target: nil action: NULL];
	[check setTranslatesAutoresizingMaskIntoConstraints: NO];
	[check bind: NSValueBinding
	   toObject: [NSUserDefaultsController sharedUserDefaultsController]
	withKeyPath: [@"values." stringByAppendingString: key]
	    options: nil];
	[row addSubview: check];

	NSView *swatch = nil;
	if ( color != nil )
	{
		swatch = [[[NSView alloc] initWithFrame: NSZeroRect] autorelease];
		[swatch setTranslatesAutoresizingMaskIntoConstraints: NO];
		[swatch setWantsLayer: YES];
		CALayer *layer = [swatch layer];
		[layer setBackgroundColor: [color CGColor]];
		[layer setCornerRadius: 7];
		// 1pt outline so the swatch stays visible even when its color is
		// near-identical to the popover background (e.g. dark-gray "Other"
		// on dark mode, or white "Free" on light mode).
		[layer setBorderWidth: 1];
		[layer setBorderColor: [[NSColor separatorColor] CGColor]];
		[row addSubview: swatch];
	}

	NSTextField *descLabel = [NSTextField wrappingLabelWithString: desc];
	[descLabel setFont: [NSFont systemFontOfSize: [NSFont smallSystemFontSize]]];
	[descLabel setTextColor: [NSColor secondaryLabelColor]];
	[descLabel setTranslatesAutoresizingMaskIntoConstraints: NO];
	[row addSubview: descLabel];

	if ( swatch != nil )
	{
		[NSLayoutConstraint activateConstraints: @[
			[[swatch leadingAnchor] constraintEqualToAnchor: [row leadingAnchor]],
			[[swatch centerYAnchor] constraintEqualToAnchor: [check centerYAnchor]],
			[[swatch widthAnchor] constraintEqualToConstant: 14],
			[[swatch heightAnchor] constraintEqualToConstant: 14],
			[[check leadingAnchor] constraintEqualToAnchor: [swatch trailingAnchor] constant: 8],
		]];
	}
	else
	{
		// Inset the checkbox by the same amount the swatch+gap takes so the
		// titles line up across all three rows.
		[[check leadingAnchor] constraintEqualToAnchor: [row leadingAnchor] constant: 20].active = YES;
	}

	[NSLayoutConstraint activateConstraints: @[
		[[check topAnchor] constraintEqualToAnchor: [row topAnchor]],
		[[check trailingAnchor] constraintLessThanOrEqualToAnchor: [row trailingAnchor]],
		[[descLabel topAnchor] constraintEqualToAnchor: [check bottomAnchor] constant: 2],
		[[descLabel leadingAnchor] constraintEqualToAnchor: [check leadingAnchor] constant: 18],
		[[descLabel trailingAnchor] constraintEqualToAnchor: [row trailingAnchor]],
		[[descLabel bottomAnchor] constraintEqualToAnchor: [row bottomAnchor]],
	]];

	return row;
}

- (void) loadView
{
	NSView *root = [[[NSView alloc] initWithFrame: NSMakeRect(0, 0, 380, 280)] autorelease];
	[self setView: root];

	NSStackView *stack = [[[NSStackView alloc] initWithFrame: NSZeroRect] autorelease];
	[stack setOrientation: NSUserInterfaceLayoutOrientationVertical];
	[stack setAlignment: NSLayoutAttributeLeading];
	[stack setSpacing: 14];
	[stack setEdgeInsets: NSEdgeInsetsMake(16, 16, 16, 16)];
	[stack setTranslatesAutoresizingMaskIntoConstraints: NO];
	[root addSubview: stack];

	[NSLayoutConstraint activateConstraints: @[
		[[stack topAnchor] constraintEqualToAnchor: [root topAnchor]],
		[[stack leadingAnchor] constraintEqualToAnchor: [root leadingAnchor]],
		[[stack trailingAnchor] constraintEqualToAnchor: [root trailingAnchor]],
		[[stack bottomAnchor] constraintEqualToAnchor: [root bottomAnchor]],
		[[root widthAnchor] constraintEqualToConstant: 380],
	]];

	// Pie wedges, treemap blocks, and these swatches all read from the
	// same accessors on DIXPieChartView so the three stay in sync.
	NSColor *freeColor  = [DIXPieChartView freeSpaceColor];
	NSColor *otherColor = [DIXPieChartView otherSpaceColor];

	NSView *freeRow = [self makeRowWithSwatchColor: freeColor
	                                         title: NSLocalizedString(@"Show Free Space as blocks", @"")
	                                   defaultsKey: ShowFreeSpace
	                                   description: NSLocalizedString(@"This shows free space like a file in the treemap. It helps to see the size relations between the opened folder and the free space on the drive.", @"")];

	NSView *otherRow = [self makeRowWithSwatchColor: otherColor
	                                          title: NSLocalizedString(@"Show Other Space as blocks", @"")
	                                    defaultsKey: ShowOtherSpace
	                                    description: NSLocalizedString(@"This shows space used by not shown files and folders like a file in the treemap. It helps to see how the opened folder compares in size to the rest of the files on the same drive. This option is only available if not a whole drive is shown.", @"")];

	NSView *animRow = [self makeRowWithSwatchColor: nil
	                                         title: NSLocalizedString(@"Animated Zooming", @"")
	                                   defaultsKey: AnimatedZooming
	                                   description: NSLocalizedString(@"Turn this off if the animation is too slow on your machine or if you don't like it.", @"")];

	[stack addArrangedSubview: freeRow];
	[stack addArrangedSubview: otherRow];
	[stack addArrangedSubview: animRow];

	// Each row should stretch the full popover width so the wrapping
	// description labels know how wide they may be.
	for ( NSView *row in @[freeRow, otherRow, animRow] )
	{
		[[row widthAnchor] constraintEqualToAnchor: [stack widthAnchor]
		                                  constant: -32].active = YES;
	}
}

@end
