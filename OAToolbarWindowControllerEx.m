//
//  OAToolbarWindowControllerEx.m
//  Disk Inventory X
//
//  Created by Tjark Derlien on 01.12.04.
//
//  Copyright (C) 2004 Tjark Derlien.
//
//  This program is free software; you can redistribute it and/or
//  modify it under the terms of the GNU General Public License
//  as published by the Free Software Foundation; either version 3
//  of the License, or any later version.

//

#import "OAToolbarWindowControllerEx.h"

static BOOL DIXStringIsEmpty(NSString *s)
{
	return s == nil || [s length] == 0;
}

@implementation NSToolbarItemValidationAdapter

- (void) setToolbarItem: (NSToolbarItem*) toolbarItem
{
	[toolbarItem retain];
	[_toolbarItem release];
	_toolbarItem = toolbarItem;
}

- (void) forwardInvocation: (NSInvocation*) anInvocation
{
	if ( [_toolbarItem respondsToSelector: [anInvocation selector]] )
	{
		[anInvocation setTarget: _toolbarItem];
		[anInvocation invoke];
	}
	else
		[super forwardInvocation: anInvocation];
}

- (NSMethodSignature *) methodSignatureForSelector:(SEL)aSelector
{
	if ( [_toolbarItem respondsToSelector: aSelector] )
		return [_toolbarItem methodSignatureForSelector: aSelector];
	else
		return [super methodSignatureForSelector: aSelector];
}

//swap the toolbar item's image when its (menu-style) state changes
- (void)setState:(NSControlStateValue)itemState
{
	OAToolbarWindowControllerEx *controller = (OAToolbarWindowControllerEx *)[[_toolbarItem toolbar] delegate];

    if ( [controller respondsToSelector:@selector(toolbar:imageForToolbarItem:forState:)] )
    {
        NSImage *image = [controller toolbar: [_toolbarItem toolbar]
                         imageForToolbarItem: _toolbarItem
                                    forState: itemState];

        if ( image != nil && image != [_toolbarItem image] )
            [_toolbarItem setImage: image];
    }
}

//NSToolbarItem has no -setTitle:; menu validation may send it, so swallow it
- (void)setTitle:(NSString *)title
{
}

@end


@interface NSMenu(FindExtensions)

- (NSMenuItem*) menuItemWithAction: (SEL) action;

@end

@interface OAToolbarWindowControllerEx ()
{
	NSArray *_allowedItemIdentifiers;
	NSArray *_defaultItemIdentifiers;
	NSDictionary *_itemInfoByIdentifier;
}
@end

static NSToolbarItemValidationAdapter *g_toolbarItemValidationAdapter = nil;
static NSMutableDictionary *g_toolbatStateImages = nil;

@implementation OAToolbarWindowControllerEx

#pragma mark -----------------Toolbar support---------------------

+ (void) initialize
{
	g_toolbarItemValidationAdapter = [[NSToolbarItemValidationAdapter alloc] init];
	g_toolbatStateImages = [[NSMutableDictionary alloc] init];
}

- (NSString *)toolbarConfigurationName;
{
	//subclasses override this
	return nil;
}

- (void) dealloc
{
	[_allowedItemIdentifiers release];
	[_defaultItemIdentifiers release];
	[_itemInfoByIdentifier release];
	[super dealloc];
}

- (void) loadToolbarConfiguration
{
	if ( _itemInfoByIdentifier != nil )
		return;

	NSString *configName = [self toolbarConfigurationName];
	if ( configName == nil )
		return;

	NSString *path = [[NSBundle mainBundle] pathForResource: configName ofType: @"toolbar"];
	NSDictionary *plist = [NSDictionary dictionaryWithContentsOfFile: path];

	_allowedItemIdentifiers = [[plist objectForKey: @"allowedItemIdentifiers"] retain];
	_defaultItemIdentifiers = [[plist objectForKey: @"defaultItemIdentifiers"] retain];
	_itemInfoByIdentifier = [[plist objectForKey: @"itemInfoByIdentifier"] retain];
}

- (void) windowDidLoad
{
	[super windowDidLoad];

	NSString *configName = [self toolbarConfigurationName];
	if ( configName == nil )
		return;

	[self loadToolbarConfiguration];

	NSToolbar *toolbar = [[[NSToolbar alloc] initWithIdentifier: configName] autorelease];
	[toolbar setAllowsUserCustomization: YES];
	[toolbar setAutosavesConfiguration: YES];
	[toolbar setDisplayMode: NSToolbarDisplayModeIconOnly];
	[toolbar setDelegate: self];

	[[self window] setToolbar: toolbar];
}

//returns an image for a toolbar item with a specific (menu-style) state
- (NSImage*) toolbar: (NSToolbar*) theToolbar imageForToolbarItem: (NSToolbarItem*) item forState: (NSControlStateValue) state;
{
	NSString *imageKey = nil;
	switch( state )
	{
		case NSControlStateValueOn:
			imageKey = @"imageName";
			break;
		case NSControlStateValueOff:
			imageKey = @"imageNameOffState";
			break;
		case NSControlStateValueMixed:
			imageKey = @"imageNameMixedState";
			break;
		default:
			NSAssert( NO, @"invalid item state for ToolbarItem" );
	}

	//get the image cache for our toolbar
	NSMutableDictionary *toolbarImageCache = [g_toolbatStateImages objectForKey: [self toolbarConfigurationName]];
	if ( toolbarImageCache == nil )
	{
		toolbarImageCache = [NSMutableDictionary dictionary];
		[g_toolbatStateImages setObject: toolbarImageCache forKey: [self toolbarConfigurationName]];
	}

	//get image cache for the toolbar item
	NSMutableDictionary *itemImageCache = [toolbarImageCache objectForKey: [item itemIdentifier]];
	if ( itemImageCache == nil )
	{
		itemImageCache = [NSMutableDictionary dictionary];
		[toolbarImageCache setObject: itemImageCache forKey: [item itemIdentifier]];
	}

	//get the state image from the toolbar item image cache
	NSImage *image = [itemImageCache objectForKey: imageKey];
	if ( image == nil )
	{
		NSDictionary *itemInfo = [self toolbarInfoForItem: [item itemIdentifier]];

		//get image name from info dictionary
		NSString *imageName = [itemInfo objectForKey: imageKey];
		if ( imageName == nil )
			imageName = [itemInfo objectForKey: @"imageName"];

		NSAssert1( imageName != nil, @"no image name for item '%@'", [item itemIdentifier] );

		image = [NSImage imageNamed: imageName];
		NSAssert1( image != nil, @"couldn't load image '%@'", imageName );

		if ( image != nil )
			[itemImageCache setObject: image forKey: imageKey];
	}

	return image;
}

- (NSDictionary *)toolbarInfoForItem:(NSString *)identifier;
{
	[self loadToolbarConfiguration];

	NSDictionary *baseInfo = [_itemInfoByIdentifier objectForKey: identifier];
	NSMutableDictionary *itemInfo = [NSMutableDictionary dictionaryWithDictionary: baseInfo ? baseInfo : @{}];

	//localize existing strings
#define LOCALIZE_PROPERTY( propname )									\
	if ( !DIXStringIsEmpty( [itemInfo objectForKey: propname] ) )	\
	{																	\
		NSString *localized = NSLocalizedString( [itemInfo objectForKey: propname], @"" ); \
		[itemInfo setObject: localized forKey: propname];				\
	}

	LOCALIZE_PROPERTY( @"label" );
	LOCALIZE_PROPERTY( @"paletteLabel" );
	LOCALIZE_PROPERTY( @"toolTip" );

#undef LOCALIZE_PROPERTY

	//We try to get the label and tooltip from the menu item with the same action,
	//so the strings only need to be maintained (and localized) in one place.

	NSString *actionString = [itemInfo objectForKey:@"action"];
	//did someone forget the ':' at the end of the string? (actions always have the sender as a parameter)
	if ( !DIXStringIsEmpty( actionString ) && [actionString characterAtIndex: [actionString length] -1] != ':' )
	{
		actionString = [actionString stringByAppendingString: @":"];
		[itemInfo setObject: actionString forKey:@"action"];
	}

	SEL action = NSSelectorFromString( actionString );

	if (  action != 0
		  && ( [itemInfo objectForKey:@"label"] == nil || [itemInfo objectForKey:@"toolTip"] == nil ) )
	{
		NSMenuItem * menuItem = [[NSApp mainMenu] menuItemWithAction: action];
		if ( menuItem != nil )
		{
			//set label?
			if ( [itemInfo objectForKey:@"label"] == nil && !DIXStringIsEmpty( [menuItem title] ) )
			{
				//delete periods at end of title (e.g. "Preferences...")
				NSString *title = [menuItem title];
				NSUInteger numOfRemainingChars = [title length];
				unichar lastChar;
				do
				{
					numOfRemainingChars--;
					lastChar = [title characterAtIndex: numOfRemainingChars];
				}
				while ( ( lastChar == '.' || isspace(lastChar) ) && numOfRemainingChars > 0 );
				title = [title substringToIndex: numOfRemainingChars+1];

				[itemInfo setObject: title forKey: @"label"];
			}
			//set tooltip?
			if ( [itemInfo objectForKey:@"toolTip"] == nil && !DIXStringIsEmpty( [menuItem toolTip] ) )
				[itemInfo setObject: [menuItem toolTip] forKey: @"toolTip"];
		}
	}

	//if no string for "paletteLabel" is set, use the one for "label"
	//(the paletteLabel is used as the toolbar item's title in the customize sheet)
	if ( [itemInfo objectForKey:@"paletteLabel"] == nil )
	{
		if ( [itemInfo objectForKey:@"label"] != nil )
			[itemInfo setObject: [itemInfo objectForKey:@"label"] forKey: @"paletteLabel"];
	}

    return itemInfo;
}

#pragma mark NSToolbarDelegate

- (id) targetForItemInfo: (NSDictionary*) itemInfo
{
	NSString *targetKey = [itemInfo objectForKey: @"target"];
	if ( [targetKey isEqualToString: @"documentController"] )
		return [self documentController];
	if ( [targetKey isEqualToString: @"application"] )
		return [self application];
	if ( [targetKey isEqualToString: @"firstResponder"] )
		return nil; //route through the responder chain
	//default: actions are handled by the window controller itself
	return self;
}

- (NSToolbarItem *)toolbar:(NSToolbar *)aToolbar itemForItemIdentifier:(NSString *)itemIdentifier willBeInsertedIntoToolbar:(BOOL)willInsert
{
	NSDictionary *itemInfo = [self toolbarInfoForItem: itemIdentifier];

	NSToolbarItem *toolbarItem = [[[NSToolbarItem alloc] initWithItemIdentifier: itemIdentifier] autorelease];

	NSString *label = [itemInfo objectForKey: @"label"];
	if ( label == nil )
		label = itemIdentifier;
	[toolbarItem setLabel: label];

	NSString *paletteLabel = [itemInfo objectForKey: @"paletteLabel"];
	[toolbarItem setPaletteLabel: paletteLabel ? paletteLabel : label];

	NSString *toolTip = [itemInfo objectForKey: @"toolTip"];
	if ( toolTip != nil )
		[toolbarItem setToolTip: toolTip];

	NSString *imageName = [itemInfo objectForKey: @"imageName"];
	if ( imageName != nil )
		[toolbarItem setImage: [NSImage imageNamed: imageName]];

	NSString *actionString = [itemInfo objectForKey: @"action"];
	if ( !DIXStringIsEmpty( actionString ) )
		[toolbarItem setAction: NSSelectorFromString( actionString )];

	[toolbarItem setTarget: [self targetForItemInfo: itemInfo]];

	return toolbarItem;
}

- (NSArray<NSToolbarItemIdentifier> *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar
{
	[self loadToolbarConfiguration];
	return _defaultItemIdentifiers ? _defaultItemIdentifiers : @[];
}

- (NSArray<NSToolbarItemIdentifier> *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar
{
	[self loadToolbarConfiguration];
	return _allowedItemIdentifiers ? _allowedItemIdentifiers : @[];
}

// properties to resolve "target" value for tool items

- (NSDocumentController*) documentController
{
    return [NSDocumentController sharedDocumentController];
}

- (NSApplication*) application
{
    return NSApp;
}

#pragma mark NSToolbarItemValidation

- (BOOL)validateToolbarItem:(NSToolbarItem *)theItem;
{
    if ( ![[self window] isKeyWindow] )
		return NO;

	[g_toolbarItemValidationAdapter setToolbarItem: theItem];

	return [self validateMenuItem: (NSMenuItem*) g_toolbarItemValidationAdapter];
}

@end


@implementation NSMenu(FindExtensions)

//linear search through all menu items (including sub menus)
- (NSMenuItem*) menuItemWithAction: (SEL) action
{
	NSInteger i = [self numberOfItems];
	while ( i-- )
	{
		NSMenuItem *menuItem = [self itemAtIndex: i];

		if ( [menuItem action] == action )
			return menuItem;

		if ( [menuItem hasSubmenu] )
		{
			menuItem = [[menuItem submenu] menuItemWithAction: action];
			if ( menuItem != nil )
				return menuItem;
		}
	}

	//not found
	return nil;
}

@end
