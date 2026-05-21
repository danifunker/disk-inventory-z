//
//  DrivesPanelController.m
//  Disk Inventory X
//
//  Created by Tjark Derlien on 15.11.04.
//
//  Copyright (C) 2004 Tjark Derlien.
//  
//  This program is free software; you can redistribute it and/or
//  modify it under the terms of the GNU General Public License
//  as published by the Free Software Foundation; either version 3
//  of the License, or any later version.

//

#import "DrivesPanelController.h"
#import "DIXAboutButton.h"
#import "DIXSnapshotInfo.h"
#import "DIXVolumeKind.h"
#import "FileSizeFormatter.h"
#import "Preferences.h"

@interface DrivesPanelController (FilterSwitches)
- (void) installFilterSwitchesInWindow: (NSWindow*) window;
- (NSView*) labeledSwitchWithTitle: (NSString*) title defaultsKey: (NSString*) key;
- (void) filterSwitchToggled: (NSSwitch*) sender;
- (BOOL) shouldShowVolumeKind: (DIXVolumeKind) kind;
@end

// NSUserDefaults keys for the filter switches at the bottom of the panel.
NSString * const DIXShowNetworkDrivesKey   = @"DIXShowNetworkDrives";
NSString * const DIXShowExternalDevicesKey = @"DIXShowExternalDevices";
NSString * const DIXShowMountedImagesKey   = @"DIXShowMountedImages";
#import "VolumeNameTransformer.h"
#import "VolumeUsageTransformer.h"
#import "NSURL-Extensions.h"

//NTStringShare is a private class in the CocoaFoundation framework; but as it is not fully thread safe,
//we need to declare it here to be accessible (see [DrivesPanelController init])
@interface NTStringShare : NSObject
+ (NTStringShare*)sharedInstance;
@end

//============ interface DrivesPanelController(Private) ==========================================================

@interface DrivesPanelController(Private)

- (void) rebuildVolumesArray;
- (void) rebuildProgressIndicatorArray;
- (void) onVolumesChanged: (NSNotification*) notification;

@end


@implementation DrivesPanelController

+ (DrivesPanelController*) sharedController
{
	static DrivesPanelController *controller = nil;
	
	if ( controller == nil )
		controller = [[DrivesPanelController alloc] init];
	
	return controller;
}

- (id) init
{
	self = [super init];
    
    _maxVolumeSize = 0;

	//register volume transformers needed in the volume tableview (before Nib is loaded!)
	[NSValueTransformer setValueTransformer:[VolumeNameTransformer transformer] forName: @"volumeNameTransformer"];
	[NSValueTransformer setValueTransformer:[VolumeUsageTransformer transformer] forName: @"volumeUsageTransformer"];

    NSNotificationCenter *wsNotiCenter = [[NSWorkspace sharedWorkspace] notificationCenter];
    [wsNotiCenter addObserver: self
                     selector: @selector(onVolumesChanged:)
                         name: NSWorkspaceDidMountNotification
                       object: nil];
    
    [wsNotiCenter addObserver: self
                     selector: @selector(onVolumesChanged:)
                         name: NSWorkspaceDidUnmountNotification
                       object: nil];
    
    [wsNotiCenter addObserver: self
                     selector: @selector(onVolumesChanged:)
                         name: NSWorkspaceDidRenameVolumeNotification
                       object: nil];

	
	[self rebuildVolumesArray];
	
	//load Nib with volume panel
    if ( ![NSBundle loadNibNamed: @"VolumesPanel" owner: self] )
	{
		[self release];
		self = nil;
	}
	else
	{
		//open volume on double clicked (can't be configured in IB?)
		[_volumesTableView setDoubleAction: @selector(openVolume:)];
		
		//set FileSizeFormatter for the columns displaying sizes (capacity, free)
		FileSizeFormatter *sizeFormatter = [[[FileSizeFormatter alloc] init] autorelease];
		[[[_volumesTableView tableColumnWithIdentifier: @"totalSize"] dataCell] setFormatter: sizeFormatter];
		[[[_volumesTableView tableColumnWithIdentifier: @"freeBytes"] dataCell] setFormatter: sizeFormatter];

		// Top-right corner of the volumes panel: a small ⓘ button that opens
		// the standard About panel. The donation/nag panel was removed in
		// v1.5.0 so this is the user's primary entry point for project info.
		DIXInstallAboutButtonInWindow( _volumesPanel );

		// The xib doesn't ship a close button on the volumes panel — enable
		// it here so the close affordance matches what ⌘W / ⌘Q already do.
		[_volumesPanel setStyleMask: [_volumesPanel styleMask] | NSWindowStyleMaskClosable];

		// Volumes table now renders up to three text lines (name, format,
		// snapshot summary) — the nib's 45pt rowHeight is short by ~15pt.
		[_volumesTableView setRowHeight: 60];

		// Filter row below the table. Register sane defaults (everything on)
		// the first time we run so existing users don't lose volumes.
		[[NSUserDefaults standardUserDefaults] registerDefaults: @{
			DIXShowNetworkDrivesKey:   @YES,
			DIXShowExternalDevicesKey: @YES,
			DIXShowMountedImagesKey:   @YES,
		}];
		[self installFilterSwitchesInWindow: _volumesPanel];
	}

	[_volumesPanel makeFirstResponder: _volumesTableView];
	
	return self;
}

- (void) dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver: self];

    [_volumes release];
	[_progressIndicators release];
	
    [super dealloc];
}

- (NSArray*) volumes
{
	return _volumes;
}

- (IBAction)openVolume:(id)sender
{
	NSIndexSet *selectedIndexes = [_volumesTableView selectedRowIndexes];
	NSUInteger index = [selectedIndexes firstIndex];
	
	//open volume in each of the selected rows
    while (index != NSNotFound)
    {
		NSURL *volume = [[_volumes objectAtIndex: index] objectForKey: @"volume"];
        if ( [volume stillExists] )
        {
            NSString *path = [volume path];
            
            //defer it till the next loop cycle (otherwise the "Open Volume" button stays in "pressed" mode during the loading)
            [[NSRunLoop currentRunLoop] performSelector: @selector(openDocumentWithContentsOfFile:)
                                                 target: [NSDocumentController sharedDocumentController]
                                               argument: path
                                                  order: 1
                                                  modes: [NSArray arrayWithObject: NSDefaultRunLoopMode]];
        }
        
        index = [selectedIndexes indexGreaterThanIndex: index];
    }	
}

- (BOOL) panelIsVisible
{
	return [[self panel] isVisible];
}

- (void) showPanel
{
	[[self panel] orderFront: nil];
}

- (NSWindow*) panel
{
	return _volumesPanel;
}

#pragma mark --------filter switches (programmatically injected)-----------

// Build a small row of NSSwitch + NSTextField pairs positioned just *above*
// the existing "Select Folder / Open Volume" row, in the gap between that row
// and the volumes table. The window is grown to make room and the scroll view
// (heightSizable) is slid up by the same amount so the new strip lives in the
// freed space rather than overlapping the original controls.
- (void) installFilterSwitchesInWindow: (NSWindow*) window
{
	NSView *content = [window contentView];
	if ( content == nil )
		return;

	const CGFloat stripVisualHeight = 28;   // visible height of the switch row
	const CGFloat gapAboveBottomRow = 10;   // distance below strip
	const CGFloat gapBelowTable     = 14;   // distance above strip
	const CGFloat addedHeight       = stripVisualHeight + gapAboveBottomRow + gapBelowTable;

	// 1. Grow the window. Keep the title bar at the same screen position by
	//    also moving origin.y down. autoresizing then enlarges the scroll view.
	NSRect frame = [window frame];
	frame.origin.y    -= addedHeight;
	frame.size.height += addedHeight;
	[window setFrame: frame display: NO];

	// 2. The scroll view (heightSizable) just absorbed the extra height — slide
	//    it back up so the gap opens *between* the table and the bottom row,
	//    not at the very bottom (where the existing controls live).
	NSScrollView *tableScroller = nil;
	for ( NSView *v in [content subviews] )
		if ( [v isKindOfClass: [NSScrollView class]] )
			{ tableScroller = (NSScrollView*) v; break; }

	if ( tableScroller != nil )
	{
		NSRect tf = [tableScroller frame];
		tf.origin.y    += addedHeight;
		tf.size.height -= addedHeight;
		[tableScroller setFrame: tf];
	}

	// 3. Find the top edge of the existing bottom row (the highest maxY of
	//    any non-scroll subview in the lower half of the content). Place the
	//    strip gapAboveBottomRow above that.
	CGFloat bottomRowTopY = 0;
	for ( NSView *v in [content subviews] )
	{
		if ( v == tableScroller ) continue;
		CGFloat maxY = NSMaxY([v frame]);
		if ( maxY > bottomRowTopY && maxY < NSMidY([content bounds]) )
			bottomRowTopY = maxY;
	}
	CGFloat stripY = bottomRowTopY + gapAboveBottomRow;

	// 4. Build a horizontal stack of (switch, label) pairs.
	NSStackView *strip = [[NSStackView alloc] initWithFrame:
		NSMakeRect( 16, stripY, [content bounds].size.width - 32, stripVisualHeight )];
	[strip setOrientation: NSUserInterfaceLayoutOrientationHorizontal];
	[strip setDistribution: NSStackViewDistributionFillEqually];
	[strip setAlignment: NSLayoutAttributeCenterY];
	[strip setSpacing: 16];
	[strip setAutoresizingMask: NSViewWidthSizable | NSViewMaxYMargin];

	NSArray<NSString*> *titles = @[
		NSLocalizedString(@"Show Network Drives",   @""),
		NSLocalizedString(@"Show External Devices", @""),
		NSLocalizedString(@"Show Mounted Images",   @""),
		NSLocalizedString(@"Show Package Contents", @""),
	];
	NSArray<NSString*> *keys = @[
		DIXShowNetworkDrivesKey,
		DIXShowExternalDevicesKey,
		DIXShowMountedImagesKey,
		ShowPackageContents,
	];
	for ( NSUInteger i = 0; i < [titles count]; i++ )
		[strip addArrangedSubview: [self labeledSwitchWithTitle: titles[i]
													defaultsKey: keys[i]]];

	[content addSubview: strip];
	[strip release];
}

- (NSView*) labeledSwitchWithTitle: (NSString*) title
					   defaultsKey: (NSString*) key
{
	NSSwitch *sw = [[[NSSwitch alloc] initWithFrame: NSMakeRect(0,0,40,22)] autorelease];
	[sw setState: [[NSUserDefaults standardUserDefaults] boolForKey: key]
			? NSControlStateValueOn : NSControlStateValueOff];
	[sw setTarget: self];
	[sw setAction: @selector(filterSwitchToggled:)];
	[sw setIdentifier: key];

	NSTextField *label = [NSTextField labelWithString: title];
	[label setLineBreakMode: NSLineBreakByTruncatingTail];
	[label setFont: [NSFont systemFontOfSize: [NSFont smallSystemFontSize]]];

	NSStackView *row = [[[NSStackView alloc] initWithFrame: NSZeroRect] autorelease];
	[row setOrientation: NSUserInterfaceLayoutOrientationHorizontal];
	[row setAlignment: NSLayoutAttributeCenterY];
	[row setSpacing: 8];
	[row addArrangedSubview: sw];
	[row addArrangedSubview: label];
	return row;
}

- (void) filterSwitchToggled: (NSSwitch*) sender
{
	NSString *key = [sender identifier];
	if ( key == nil )
		return;
	[[NSUserDefaults standardUserDefaults] setBool: ([sender state] == NSControlStateValueOn)
											forKey: key];

	// Only the volume-kind switches affect which volumes are in the list.
	// ShowPackageContents is consumed by FileSystemDoc at scan time for
	// newly-opened documents, so no rebuild needed here.
	if ( [key isEqualToString: ShowPackageContents] )
		return;

	[self rebuildVolumesArray];
}

// YES if a given volume kind should be shown given the current switch state.
- (BOOL) shouldShowVolumeKind: (DIXVolumeKind) kind
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	switch ( kind )
	{
		case DIXVolumeKindInternal:  return YES;  // always shown
		case DIXVolumeKindNetwork:   return [defaults boolForKey: DIXShowNetworkDrivesKey];
		case DIXVolumeKindExternal:  return [defaults boolForKey: DIXShowExternalDevicesKey];
		case DIXVolumeKindDiskImage: return [defaults boolForKey: DIXShowMountedImagesKey];
	}
	return YES;
}

@end

//============ implementation DrivesPanelController(Private) ==========================================================

@implementation DrivesPanelController(Private)

//fill array "_volumes" with mounted volumes and their images
- (void) rebuildVolumesArray
{
    _maxVolumeSize = 0;
    
    NSArray *volProps = [NSArray arrayWithObjects:NSURLLocalizedNameKey
                                                , NSURLVolumeTotalCapacityKey
                                                , NSURLVolumeAvailableCapacityKey
                                                , NSURLVolumeSupportsVolumeSizesKey
                                                , NSURLVolumeLocalizedFormatDescriptionKey
                                                , nil];
    
    NSArray<NSURL *> *vols = [[NSFileManager defaultManager] mountedVolumeURLsIncludingResourceValuesForKeys: volProps
                                                                                                     options: NSVolumeEnumerationSkipHiddenVolumes];
    
    [self willChangeValueForKey: @"volumes"];
    
    NS_DURING
    [_volumes release];
    _volumes = [[NSMutableArray alloc] initWithCapacity: [vols count]];
    
    for ( NSURL *volumeURL in vols )
    {
        [volumeURL cacheResourcesInArray: volProps];

        // Drop volumes the user has filtered out.
        if ( ![self shouldShowVolumeKind: DIXClassifyVolume(volumeURL)] )
            continue;

        // Refresh the cached snapshot info for this volume so the name
        // transformer can show "N snapshots (~size)" without spawning a task
        // on every cell redraw.
        DIXRefreshSnapshotInfoForVolume(volumeURL);

        //put NSURL object for key "volume" in the entry dictionary
        NSMutableDictionary *entry = [NSMutableDictionary dictionaryWithObject: volumeURL forKey: @"volume"];
        
        //put volume icon for key "image" in the entry dictionary
        NSImage *volImage = [volumeURL icon];
        [volImage setSize: NSMakeSize(32,32)];
        
        [entry setObject: ( volImage == nil ? (id)[NSNull null] : volImage )
                  forKey: @"image"];
        
        [_volumes addObject: entry];
        
        if ( [[volumeURL volumeTotalCapacity] unsignedLongLongValue] > _maxVolumeSize)
            _maxVolumeSize = [[volumeURL volumeTotalCapacity] unsignedLongLongValue];
    }
    NS_HANDLER
    NS_ENDHANDLER
    
    [self rebuildProgressIndicatorArray];
    
    [self didChangeValueForKey: @"volumes"];
}

//keeps array of progress indicators (for graphical usage display) in sync with volumes array
- (void) rebuildProgressIndicatorArray
{
	if ( _progressIndicators == nil )
		_progressIndicators = [[NSMutableArray alloc] initWithCapacity: [_volumes count]];
	
	unsigned i;
	for ( i = 0; i < [_volumes count]; i++ )
	{
		NSProgressIndicator *progrInd = nil;
		if ( i >= [_progressIndicators count] )
		{
			progrInd = [[[NSProgressIndicator alloc] init] autorelease];
			[progrInd setStyle: NSProgressIndicatorBarStyle];
			[progrInd setIndeterminate: NO];
			
			[_progressIndicators addObject: progrInd];
		}
		else
			//reuse existing progress indicator
			progrInd = [_progressIndicators objectAtIndex: i];
		
		NSURL *vol = [[_volumes objectAtIndex: i] objectForKey : @"volume"];
        
        if ( [vol getCachedBoolValue: NSURLVolumeSupportsVolumeSizesKey] )
        {
            double totalBytes = [[vol volumeTotalCapacity] doubleValue];
            double freeBytes = [[vol volumeAvailableCapacity] doubleValue];

            [progrInd setMinValue: 0];
            [progrInd setMaxValue: totalBytes];
            [progrInd setDoubleValue: (totalBytes - freeBytes)];
        }
        else
        {
            [progrInd setMinValue: 0];
            [progrInd setMaxValue: 0];
            [progrInd setDoubleValue: 0];
        }
	}
	
	while ( [_progressIndicators count] > [_volumes count] )
	{
		[[_progressIndicators lastObject] removeFromSuperviewWithoutNeedingDisplay];
		[_progressIndicators removeLastObject];
	}
}

#pragma mark --------NTVolumeMgr notifications-----------------

- (void) onVolumesChanged: (NSNotification*) notification
{
    [self rebuildVolumesArray];
}

#pragma mark --------NSTableView notifications-----------------

- (void) tableViewSelectionDidChange: (NSNotification*) notification
{
}

#pragma mark --------NSTableView delegates-----------------

- (void) tableView:(NSTableView *) tableView willDisplayCell:(id) cell forTableColumn:(NSTableColumn *) tableColumn row:(int) row
{
	if ( [[tableColumn identifier] isEqualToString: @"usagePercent"] )
	{
		NSProgressIndicator *progrInd = [_progressIndicators objectAtIndex: row];
		
		//add progress indicator as subview of table view
		if ( [progrInd superview] != tableView )
			[tableView addSubview: progrInd];
		
		int colIndex = [tableView columnWithIdentifier: [tableColumn identifier]];
		NSRect cellRect = [tableView frameOfCellAtColumn: colIndex row: row];
		
		const float progrIndThickness = NSProgressIndicatorPreferredLargeThickness; 
		const float extraSpace = 16; //space before and after progress indicator (relative to left and right side of cell)
		
		//center it vertically in cell
		NSAssert( NSHeight(cellRect) > progrIndThickness, @"rows need to be higher than progress indicator thickness" );
		cellRect.origin.y += (NSHeight(cellRect) - progrIndThickness) / 2;
		cellRect.size.height = progrIndThickness;

		//add space before and after
		cellRect.origin.x += extraSpace;
		cellRect.size.width -= 2*extraSpace;
        
        NSURL *volURL = [[_volumes objectAtIndex: row] objectForKey : @"volume"];
        if ( [volURL getCachedBoolValue: NSURLVolumeSupportsVolumeSizesKey] )
        {
            double fraction = [[volURL cachedVolumeTotalCapacity] doubleValue] / (double)_maxVolumeSize;
            // each volume should at least be shown as 20% of the available space as it would be shown as too narrow (or not at all) otherwise
            cellRect.size.width *= fmax(fraction, 0.2);
        }
        else
            cellRect.size.width = 0; //no size information available; hide progress indicator
        
		[progrInd setFrame: cellRect];
		[progrInd stopAnimation: nil];
	}
}



@end
