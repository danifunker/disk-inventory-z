//
//  OAToolbarWindowControllerEx.h
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
//  Standalone NSWindowController that builds its toolbar from a ".toolbar"
//  property list (formerly handled by OmniAppKit's OAToolbarWindowController).

#import <Cocoa/Cocoa.h>

// A stand-in "menu item" that forwards setState:/setTitle: etc. to a toolbar
// item, so a single -validateMenuItem: implementation can validate both menu
// items and toolbar items.
@interface NSToolbarItemValidationAdapter : NSObject
{
	NSToolbarItem* _toolbarItem;
}

- (void) setToolbarItem: (NSToolbarItem*) toolbarItem;
- (void) forwardInvocation: (NSInvocation*) anInvocation;

@end

@interface OAToolbarWindowControllerEx : NSWindowController <NSToolbarDelegate, NSToolbarItemValidation>

// Subclasses return the name of the ".toolbar" plist (without extension).
- (NSString *)toolbarConfigurationName;

- (NSImage*) toolbar: (NSToolbar*) theToolbar imageForToolbarItem: (NSToolbarItem*) item forState: (NSControlStateValue) state;

// properties to resolve "target" value for tool items
@property (readonly) NSDocumentController *documentController;
@property (readonly) NSApplication *application;

@end
