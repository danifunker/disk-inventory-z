//
//  DIXAboutButton.m
//  Disk Inventory Y
//
//  Copyright (C) 2026 Dani Sarfati.
//
//  This program is free software; you can redistribute it and/or
//  modify it under the terms of the GNU General Public License
//  as published by the Free Software Foundation; either version 3
//  of the License, or any later version.
//

#import "DIXAboutButton.h"

// Sentinel tag so we can detect a previously-installed button and skip
// installing a duplicate (windows may be reopened).
static const NSInteger kDIXAboutButtonTag = 0x44495861;  // 'DIXa'

static BOOL DIXAccessoryHasOurButton(NSTitlebarAccessoryViewController *vc)
{
    for ( NSView *sub in [[vc view] subviews] )
        if ( [sub isKindOfClass: [NSButton class]] && [(NSButton*)sub tag] == kDIXAboutButtonTag )
            return YES;
    return NO;
}

void DIXInstallAboutButtonInWindow(NSWindow *window)
{
    if ( window == nil )
        return;

    // Already installed? bail.
    for ( NSTitlebarAccessoryViewController *vc in [window titlebarAccessoryViewControllers] )
        if ( DIXAccessoryHasOurButton(vc) )
            return;

    NSButton *btn = [[NSButton alloc] initWithFrame: NSZeroRect];
    [btn setBezelStyle: NSBezelStyleHelpButton];    // round ⓘ/? button
    [btn setTitle: @""];
    [btn setTag: kDIXAboutButtonTag];
    [btn setTarget: NSApp];
    [btn setAction: @selector(orderFrontStandardAboutPanel:)];
    [btn setToolTip: NSLocalizedString(@"About Disk Inventory Y", @"")];
    [btn sizeToFit];

    // The accessory view is laid out inside the title bar; size its container
    // so there's a bit of padding around the round button.
    NSSize bsize = [btn frame].size;
    NSView *container = [[NSView alloc] initWithFrame:
        NSMakeRect(0, 0, bsize.width + 12, bsize.height + 4)];
    [btn setFrame: NSMakeRect(6, 2, bsize.width, bsize.height)];
    [container addSubview: btn];
    [btn release];

    NSTitlebarAccessoryViewController *vc = [[NSTitlebarAccessoryViewController alloc] init];
    [vc setView: container];
    [vc setLayoutAttribute: NSLayoutAttributeRight];   // dock against the right edge
    [container release];

    [window addTitlebarAccessoryViewController: vc];
    [vc release];
}
