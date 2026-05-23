//
//  DIXAboutButton.h
//  Disk Inventory Z
//
//  Copyright (C) 2026 Dani Sarfati.
//
//  This program is free software; you can redistribute it and/or
//  modify it under the terms of the GNU General Public License
//  as published by the Free Software Foundation; either version 3
//  of the License, or any later version.
//

#import <Cocoa/Cocoa.h>

// Add a standard macOS help-style ⓘ/? button to the top-right corner of the
// given window's content view. The button shows the standard "About <App>"
// panel when clicked. Safe to call multiple times — duplicates are skipped.
extern void DIXInstallAboutButtonInWindow(NSWindow *window);
