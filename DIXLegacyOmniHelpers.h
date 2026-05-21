//
//  DIXLegacyOmniHelpers.h
//  Disk Inventory Y
//
//  Copyright (C) 2026 Dani Sarfati.
//
//  This program is free software; you can redistribute it and/or
//  modify it under the terms of the GNU General Public License
//  as published by the Free Software Foundation; either version 3
//  of the License, or any later version.
//
//  Tiny replacements for the handful of OmniFoundation category methods
//  that the original Disk Inventory X codebase still calls. Once every
//  call site has been rewritten in modern AppKit terms these can go away.
//

#import <Foundation/Foundation.h>

@interface NSString (DIXLegacyOmniHelpers)

// Equivalent to OmniFoundation's +[NSString isEmptyString:]: YES when the
// argument is nil or has length 0. Treats non-NSString objects as empty.
+ (BOOL) isEmptyString: (NSString *) string;

@end
