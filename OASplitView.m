//
//  OASplitView.m
//  Disk Inventory X
//
//  Minimal local replacement for OmniAppKit's OASplitView.
//
//  This program is free software; you can redistribute it and/or
//  modify it under the terms of the GNU General Public License
//  as published by the Free Software Foundation; either version 3
//  of the License, or any later version.

#import "OASplitView.h"

@implementation OASplitView

- (void)setPositionAutosaveName:(NSString *)name
{
	[self setAutosaveName:name];
}

@end
