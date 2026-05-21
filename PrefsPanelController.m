//
//  PrefsPanelController.m
//  Disk Inventory X
//
//  Created by Tjark Derlien on 28.11.04.
//
//  Copyright (C) 2004 Tjark Derlien.
//  Modifications © 2026 Dani Sarfati.
//
//  This program is free software; you can redistribute it and/or
//  modify it under the terms of the GNU General Public License
//  as published by the Free Software Foundation; either version 3
//  of the License, or any later version.

//

#import "PrefsPanelController.h"
#import "PrefsPageBase.h"

@interface PrefsPanelController ()
{
	NSWindow *_window;
	NSArray *_pages;					//array of page-info dictionaries, sorted by "ordering"
	NSMutableDictionary *_pageInstances;	//identifier -> PrefsPageBase
	NSMutableDictionary *_pageTopObjects;	//identifier -> retained top-level nib objects
}
@end

@implementation PrefsPanelController

+ (PrefsPanelController*) sharedPreferenceController
{
	static PrefsPanelController *sharedPreferenceController = nil;

	if (sharedPreferenceController == nil)
		sharedPreferenceController = [[self alloc] init];

	return sharedPreferenceController;
}

- (instancetype) init
{
	self = [super init];
	if ( self != nil )
	{
		_pageInstances = [[NSMutableDictionary alloc] init];
		_pageTopObjects = [[NSMutableDictionary alloc] init];
		[self loadPageRegistration];
	}
	return self;
}

- (void) loadPageRegistration
{
	NSDictionary *registrations = [[NSBundle mainBundle] objectForInfoDictionaryKey: @"OFRegistrations"];
	NSDictionary *pageDict = [registrations objectForKey: @"PrefsPanelController"];

	NSMutableArray *pages = [NSMutableArray array];
	for ( NSString *identifier in pageDict )
	{
		NSDictionary *info = [pageDict objectForKey: identifier];
		if ( [[info objectForKey: @"hidden"] boolValue] )
			continue;
		[pages addObject: info];
	}

	[pages sortUsingComparator: ^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
		return [[a objectForKey: @"ordering"] compare: [b objectForKey: @"ordering"]];
	}];

	_pages = [pages copy];
}

- (NSDictionary*) infoForIdentifier: (NSString*) identifier
{
	for ( NSDictionary *info in _pages )
	{
		if ( [[info objectForKey: @"identifier"] isEqualToString: identifier] )
			return info;
	}
	return nil;
}

#pragma mark window

- (void) buildWindow
{
	if ( _window != nil )
		return;

	NSRect frame = NSMakeRect( 0, 0, 400, 300 );
	_window = [[NSWindow alloc] initWithContentRect: frame
										  styleMask: (NSWindowStyleMaskTitled | NSWindowStyleMaskClosable)
											backing: NSBackingStoreBuffered
											  defer: YES];
	[_window setReleasedWhenClosed: NO];
	[_window setFrameAutosaveName: @"PreferencesWindow"];

	NSToolbar *toolbar = [[[NSToolbar alloc] initWithIdentifier: @"PreferencesToolbar"] autorelease];
	[toolbar setDelegate: self];
	[toolbar setAllowsUserCustomization: NO];
	[toolbar setDisplayMode: NSToolbarDisplayModeIconAndLabel];
	[_window setToolbar: toolbar];
}

- (PrefsPageBase*) pageForIdentifier: (NSString*) identifier
{
	PrefsPageBase *page = [_pageInstances objectForKey: identifier];
	if ( page != nil )
		return page;

	NSDictionary *info = [self infoForIdentifier: identifier];
	if ( info == nil )
		return nil;

	Class pageClass = NSClassFromString( identifier );
	if ( pageClass == nil )
		return nil;

	page = [[pageClass alloc] init];

	NSString *nibName = [info objectForKey: @"nib"];
	NSArray *topObjects = nil;
	if ( [[NSBundle mainBundle] loadNibNamed: nibName owner: page topLevelObjects: &topObjects] )
	{
		[_pageTopObjects setObject: (topObjects ? topObjects : @[]) forKey: identifier];
		[_pageInstances setObject: page forKey: identifier];
	}

	[page release];

	return [_pageInstances objectForKey: identifier];
}

- (void) selectPageWithIdentifier: (NSString*) identifier
{
	PrefsPageBase *page = [self pageForIdentifier: identifier];
	NSView *view = [page controlBox];
	if ( view == nil )
		return;

	[_window setContentView: view];
	[_window setContentSize: [view frame].size];
	[[_window toolbar] setSelectedItemIdentifier: identifier];

	NSDictionary *info = [self infoForIdentifier: identifier];
	NSString *title = [info objectForKey: @"title"];
	[_window setTitle: title ? NSLocalizedString( title, @"" ) : @"Preferences"];

	if ( [page initialFirstResponder] != nil )
		[_window setInitialFirstResponder: [page initialFirstResponder]];
}

- (IBAction) toolbarSelectPage: (id) sender
{
	[self selectPageWithIdentifier: [(NSToolbarItem*)sender itemIdentifier]];
}

- (IBAction) showPreferencesPanel: (id) sender
{
	[self buildWindow];

	if ( [[_window toolbar] selectedItemIdentifier] == nil && [_pages count] > 0 )
	{
		NSString *first = [[_pages objectAtIndex: 0] objectForKey: @"identifier"];
		[self selectPageWithIdentifier: first];
		[_window center];
	}

	[_window makeKeyAndOrderFront: sender];
}

#pragma mark NSToolbarDelegate

- (NSArray<NSString*>*) pageIdentifiers
{
	NSMutableArray *ids = [NSMutableArray array];
	for ( NSDictionary *info in _pages )
		[ids addObject: [info objectForKey: @"identifier"]];
	return ids;
}

- (NSArray<NSToolbarItemIdentifier>*) toolbarDefaultItemIdentifiers: (NSToolbar*) toolbar
{
	return [self pageIdentifiers];
}

- (NSArray<NSToolbarItemIdentifier>*) toolbarAllowedItemIdentifiers: (NSToolbar*) toolbar
{
	return [self pageIdentifiers];
}

- (NSArray<NSToolbarItemIdentifier>*) toolbarSelectableItemIdentifiers: (NSToolbar*) toolbar
{
	return [self pageIdentifiers];
}

- (NSToolbarItem*) toolbar: (NSToolbar*) toolbar itemForItemIdentifier: (NSToolbarItemIdentifier) identifier willBeInsertedIntoToolbar: (BOOL) flag
{
	NSDictionary *info = [self infoForIdentifier: identifier];
	if ( info == nil )
		return nil;

	NSToolbarItem *item = [[[NSToolbarItem alloc] initWithItemIdentifier: identifier] autorelease];

	NSString *title = [info objectForKey: @"title"];
	[item setLabel: title ? NSLocalizedString( title, @"" ) : identifier];

	NSString *iconName = [info objectForKey: @"icon"];
	if ( iconName != nil )
		[item setImage: [NSImage imageNamed: iconName]];

	[item setTarget: self];
	[item setAction: @selector(toolbarSelectPage:)];

	return item;
}

@end
