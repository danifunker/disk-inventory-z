//
//  OASplitView.h
//  Disk Inventory X
//
//  Minimal local replacement for OmniAppKit's OASplitView.
//  TreeMap.nib references this class by name, so the name is preserved.
//
//  This program is free software; you can redistribute it and/or
//  modify it under the terms of the GNU General Public License
//  as published by the Free Software Foundation; either version 3
//  of the License, or any later version.

#import <Cocoa/Cocoa.h>

@interface OASplitView : NSSplitView

// Omni exposed divider-position persistence under this name; map it to
// NSSplitView's built-in autosave behavior.
- (void)setPositionAutosaveName:(NSString *)name;

@end
