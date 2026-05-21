//
//  PrefsPageBase.h
//  Disk Inventory Z
//
//  Created by Tjark Derlien on 29.11.04.
//
//  Copyright (C) 2004 Tjark Derlien.
//  Modifications © 2026 Dani Sarfati.
//
//  This program is free software; you can redistribute it and/or
//  modify it under the terms of the GNU General Public License
//  as published by the Free Software Foundation; either version 3
//  of the License, or any later version.

//
//  Base class for a single preference page. Each page has a nib whose
//  File's Owner is a PrefsPageBase subclass; the controls in the nib are
//  bound to NSUserDefaults via Cocoa Bindings, so no per-page code is needed.
//  (Formerly OmniAppKit's OAPreferenceClient.)

#import <Cocoa/Cocoa.h>

@interface PrefsPageBase : NSObject
{
	IBOutlet NSView *controlBox;
	IBOutlet NSView *initialFirstResponder;
	IBOutlet NSView *lastKeyView;
}

// The page's top-level view, hosted by the preferences window.
@property (nonatomic, readonly) NSView *controlBox;
@property (nonatomic, readonly) NSView *initialFirstResponder;

@end
