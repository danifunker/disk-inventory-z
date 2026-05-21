//
//  DIXLegacyOmniHelpers.m
//  Disk Inventory Z
//
//  Copyright (C) 2026 Dani Sarfati.
//
//  This program is free software; you can redistribute it and/or
//  modify it under the terms of the GNU General Public License
//  as published by the Free Software Foundation; either version 3
//  of the License, or any later version.
//

#import "DIXLegacyOmniHelpers.h"

@implementation NSString (DIXLegacyOmniHelpers)

+ (BOOL) isEmptyString: (NSString *) string
{
    if ( string == nil )
        return YES;
    if ( ![string isKindOfClass: [NSString class]] )
        return YES;
    return [string length] == 0;
}

@end
