//
//  PrefsPanelController.h
//  Disk Inventory X
//
//  Created by Tjark Derlien on 28.11.04.
//
//  Copyright (C) 2004 Tjark Derlien.
//
//  This program is free software; you can redistribute it and/or
//  modify it under the terms of the GNU General Public License
//  as published by the Free Software Foundation; either version 3
//  of the License, or any later version.

//
//  A stock preferences window with a toolbar to switch between pages.
//  Page metadata is read from the "OFRegistrations" > "PrefsPanelController"
//  dictionary in Info.plist (formerly consumed by OmniAppKit).

#import <Cocoa/Cocoa.h>

@interface PrefsPanelController : NSObject <NSToolbarDelegate>

+ (PrefsPanelController*) sharedPreferenceController;

- (IBAction) showPreferencesPanel: (id) sender;

@end
