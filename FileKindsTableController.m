//
//  FSItem.m
//  Disk Inventory Z
//
//  Created by Tjark Derlien on Mon Sep 29 2003.
//  Copyright (c) 2003 Tjark Derlien.
//  Modifications © 2026 Dani Sarfati.
//  
//  This program is free software; you can redistribute it and/or
//  modify it under the terms of the GNU General Public License
//  as published by the Free Software Foundation; either version 3
//  of the License, or any later version.
//
//

#import "FileKindsTableController.h"
#import "DIXTableView+Sizing.h"
#import <TreeMapView/TMVCushionRenderer.h>
#import <TreeMapView/NSBitmapImageRep-CreationExtensions.h>
#import "Preferences.h"
#import "MainWindowController.h"

#import "FSItemIndex.h"

NSString * const DIXShowKindInSelectionListNotification    = @"DIXShowKindInSelectionList";
NSString * const DIXShowKindInSelectionListKindNameKey     = @"kindName";


//============ interface FileKindsTableController(Private) ==========================================================

@interface FileKindsTableController(Private)

- (NSImage*) colorImageForRow: (int) row column: (NSTableColumn*) column;

@end

//============ implementation FileKindsTableController ==========================================================

@implementation FileKindsTableController

- (void) awakeFromNib
{
	FileSystemDoc *doc = [self document];
	
	NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
	
    [center addObserver: self
			   selector: @selector(documentSelectionChanged:)
				   name: GlobalSelectionChangedNotification
				 object: doc];
	
    [center addObserver: self
			   selector: @selector(windowWillClose:)
				   name: NSWindowWillCloseNotification
				 object: [_windowController window]];
	
	//set up KVO
	NSUserDefaultsController *sharedDefsController = [NSUserDefaultsController sharedUserDefaultsController];
	[sharedDefsController addObserver: self
						   forKeyPath: [@"values." stringByAppendingString: ShareKindColors]
							  options: 0
							  context: ShareKindColors];

	[_kindsTableArrayController addObserver: self forKeyPath: @"arrangedObjects" options: 0 context: nil];

	//set initial sorting (descendant size)
	NSTableColumn *sizeColumn = [_tableView tableColumnWithIdentifier: @"size"];
	NSArray *initialSortDescriptors = [NSArray arrayWithObject: [[sizeColumn sortDescriptorPrototype] reversedSortDescriptor]];
	[_kindsTableArrayController setSortDescriptors: initialSortDescriptors];

	//columns fill the drawer width; numeric columns fixed-width, kind name flexible.
	// "kindName" is the flexible column (the nib uses "kindName" as the
	// column identifier, not "kind"). The first table column ("color") is
	// just a tiny swatch, so we don't want it absorbing extra width.
	[_tableView dixConfigureColumnsWithNumericIdentifiers: @[ @"size", @"fileCount" ]
	                                   flexibleIdentifier: @"kindName"];

	// Right-click menu on the kinds table: a single "Show Files in Selection
	// List" item that reuses our existing IBAction.
	NSMenu *menu = [[[NSMenu alloc] initWithTitle: @""] autorelease];
	NSMenuItem *showItem = [menu addItemWithTitle: NSLocalizedString(@"Show Files in Selection List", @"")
	                                       action: @selector(showFilesInSelectionList:)
	                                keyEquivalent: @""];
	[showItem setTarget: self];
	[menu setDelegate: self];
	[_tableView setMenu: menu];

	// Other controllers (e.g. the files outline view's right-click menu) ask
	// us to select a kind by name via this notification; see DIX...Notification
	// declaration in the header.
	[[NSNotificationCenter defaultCenter] addObserver: self
	                                         selector: @selector(handleShowKindInSelectionListNotification:)
	                                             name: DIXShowKindInSelectionListNotification
	                                           object: nil];
}

// NSMenuDelegate: select the right-clicked row before the context menu shows
// so -showFilesInSelectionList: operates on the row under the cursor.
- (void) menuNeedsUpdate: (NSMenu*) menu
{
	NSEvent *event = [NSApp currentEvent];
	if ( event == nil )
		return;
	NSPoint pt = [_tableView convertPoint: [event locationInWindow] fromView: nil];
	NSInteger row = [_tableView rowAtPoint: pt];
	if ( row >= 0 && row != [_tableView selectedRow] )
	{
		[_tableView selectRowIndexes: [NSIndexSet indexSetWithIndex: row]
		        byExtendingSelection: NO];
	}
}

- (void) handleShowKindInSelectionListNotification: (NSNotification*) note
{
	NSString *kindName = [[note userInfo] objectForKey: DIXShowKindInSelectionListKindNameKey];
	if ( [kindName length] == 0 )
		return;

	// Find the FileKindStatistic with this kindName in our arranged objects
	// and select it -- that lights up the same code path as a manual click
	// on the row, which the selection list is already wired to observe.
	NSArray *arranged = (NSArray*)[_kindsTableArrayController arrangedObjects];
	NSUInteger idx = [arranged indexOfObjectPassingTest:
		^BOOL (FileKindStatistic *stat, NSUInteger i, BOOL *stop)
		{
			return [[stat kindName] isEqualToString: kindName];
		}];

	if ( idx == NSNotFound )
		return;

	[_tableView selectRowIndexes: [NSIndexSet indexSetWithIndex: idx]
	        byExtendingSelection: NO];
	[_tableView scrollRowToVisible: idx];
	[self showFilesInSelectionList: nil];
}

- (void) dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver: self
                                                    name: DIXShowKindInSelectionListNotification
                                                  object: nil];
    [_cushionImages release];

    [super dealloc];
}

- (FileSystemDoc*) document
{
	return [_windowController document];
}

- (IBAction) showFilesInSelectionList: (id) sender
{
	[_windowController showSelectionListPanel];

	int selectedRow = [_tableView selectedRow];
	NSAssert( selectedRow >= 0, @"kinds tableview should have a selection" );
	
	FileKindStatistic *kindStat = [(NSArray*)[_kindsTableArrayController arrangedObjects] objectAtIndex: selectedRow];
	[_kindsPopupArrayController setSelectedObjects: [NSArray arrayWithObject: kindStat]];
}

#pragma mark --------NSTableView delegate methods-----------------

//NSTableView delegate
- (void) tableView: (NSTableView*) tableView willDisplayCell: (id) cell forTableColumn: (NSTableColumn*) tableColumn row: (int) row
{
	if ( [[tableColumn identifier] isEqualToString: @"color"] )
	{
		// Make the cushion fill the whole cell. Without this the image cell
		// centers a fixed-size image, so when a split-view collapse/expand
		// leaves the row height different from the cached bitmap's height the
		// cushion floats with a gap below it.
		if ( [cell respondsToSelector: @selector(setImageScaling:)] )
			[cell setImageScaling: NSImageScaleAxesIndependently];
		if ( [cell respondsToSelector: @selector(setImageAlignment:)] )
			[cell setImageAlignment: NSImageAlignCenter];
		[cell setImage: [self colorImageForRow: row column: tableColumn]];
	}
	// Kind column truncation is handled by the DIXTruncatingTextFieldCell
	// installed as that column's dataCell in -dixConfigureColumns...
}

#pragma mark --------NSTableView notifications-----------------

- (void) tableViewSelectionDidChange: (NSNotification *) aNotification
{
    //int row = [_tableView selectedRow];
}

#pragma mark --------KVO-----------------

- (void)observeValueForKeyPath:(NSString*)keyPath
					  ofObject:(id)object
						change:(NSDictionary*)change
					   context:(void*)context
{
	LOG( @"FileKindsTableColumn.observeValueForKeyPath: keyPath: %@, change dict:%@", keyPath, change );
	
	if ( context == ShareKindColors )
	{
		[_cushionImages release];
		_cushionImages = nil;
		
		[_tableView setNeedsDisplay: YES];
	}
	else if ( object == _kindsTableArrayController )
	{
		if ( [keyPath isEqualToString: @"arrangedObjects"] )
			[_cushionImages removeAllObjects];
	}
}

@end

//============ implementation FileKindsTableController(Private) ===============================================

@implementation FileKindsTableController(Private)

//returns a cushion image for a given row in the tableview
- (NSImage*) colorImageForRow: (int) row column: (NSTableColumn*) column
{
	if ( _cushionImages == nil )
		_cushionImages = [[NSMutableDictionary alloc] init];
		
	FileKindStatistic *kindStatistic = [(NSArray*)[_kindsTableArrayController arrangedObjects] objectAtIndex: row];
	
	NSImage *image = [_cushionImages objectForKey: [kindStatistic kindName]];
	
	// Floor to integers: the bitmap is allocated with integer pixel dimensions
	// (NSInteger pixelsWide/pixelsHigh) but the cushion renderer's rect uses
	// the same NSSize, so a fractional column width (which the kinds table
	// now gets when auto-sized inside a split view pane) trips the
	// "_rect exceeds bitmap width" assertion in TMVCushionRenderer.
	NSSize cellSize = NSMakeSize( floor([column width]), floor([_tableView rowHeight]) );
	
	//if we don't have any image for that row yet or the cell size has changed, create a new image
	if ( image == nil || !NSEqualSizes( [image size], cellSize ) )
	{
		//create a bitmap with 24 bit color depth and no alpha component							 
		NSBitmapImageRep* bitmap = [[ NSBitmapImageRep alloc]
										initRGBBitmapWithWidth: cellSize.width height: cellSize.height];
		
		//..and draw a cushion in that bitmap
		TMVCushionRenderer *cushionRenderer = [(TMVCushionRenderer*) [TMVCushionRenderer alloc]
											   initWithRect: NSMakeRect(0, 0, cellSize.width, cellSize.height)];
		
		FileTypeColors *kindColors = [[self document] fileTypeColors];
		[cushionRenderer setColor: [kindColors colorForKind: [kindStatistic kindName]]];
		
		[cushionRenderer addRidgeByHeightFactor: 0.5];
		[cushionRenderer renderCushionInBitmap: bitmap];
		
		[cushionRenderer release];
		
		//put an image with the cushion in the _cushionImages array for the next time this row is about to be drawn
		image = [bitmap suitableImageForView: _tableView];
		[bitmap release];
		
		[_cushionImages setObject: image forKey: [kindStatistic kindName]];
	}

	return image;
}

#pragma mark --------document notifications-----------------

- (void) documentSelectionChanged: (NSNotification*) notification
{
	FileSystemDoc *doc = [self document];
	
    FSItem *item = [doc selectedItem];
	//optimization: if item is a folder, remove selection (as it is not in the list anyway)
	FileKindStatistic *stat = [doc itemIsNode: item] ? nil : [doc kindStatisticForItem: item];
	
	id tableViewSelection = [_kindsTableArrayController selection];
	if ( tableViewSelection == NSBindingSelectionMarker.noSelectionMarker )
		tableViewSelection = nil;
	
	if ( stat != tableViewSelection )
	{
		if ( stat == nil )
			[_kindsTableArrayController setSelectionIndexes: [NSIndexSet indexSet]];
		else
			[_kindsTableArrayController setSelectedObjects: [NSArray arrayWithObject: stat]];
	}
}

#pragma mark --------window notifications-----------------

- (void) windowWillClose: (NSNotification*) notification
{
	NSUserDefaultsController *sharedDefsController = [NSUserDefaultsController sharedUserDefaultsController];
	[sharedDefsController removeObserver: self forKeyPath: [@"values." stringByAppendingString: ShareKindColors]];
    
	[_kindsTableArrayController removeObserver: self forKeyPath: @"arrangedObjects"];
	
    [[NSNotificationCenter defaultCenter] removeObserver: self];
}

@end
