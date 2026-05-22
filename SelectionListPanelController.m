//
//  SelectionListPanelController.m
//  Disk Inventory Z
//

#import "SelectionListPanelController.h"

@implementation SelectionListPanelController

- (instancetype) initWithContentView: (NSView*) contentView
                        parentWindow: (NSWindow*) parentWindow
{
    NSParameterAssert( contentView != nil );
    NSParameterAssert( parentWindow != nil );

    // Size the panel to match the hosted view's natural frame.
    NSRect viewFrame = [contentView frame];
    NSRect contentRect = NSMakeRect( 0, 0,
                                     NSWidth(viewFrame)  > 200 ? NSWidth(viewFrame)  : 480,
                                     NSHeight(viewFrame) > 100 ? NSHeight(viewFrame) : 220 );

    NSWindowStyleMask style = NSWindowStyleMaskTitled
                            | NSWindowStyleMaskClosable
                            | NSWindowStyleMaskResizable
                            | NSWindowStyleMaskUtilityWindow
                            | NSWindowStyleMaskHUDWindow * 0; // not HUD

    NSPanel *panel = [[NSPanel alloc] initWithContentRect: contentRect
                                                styleMask: style
                                                  backing: NSBackingStoreBuffered
                                                    defer: YES];
    [panel setTitle: NSLocalizedString( @"Selection List", @"Selection list panel title" )];
    [panel setFloatingPanel: YES];
    [panel setBecomesKeyOnlyIfNeeded: YES];
    [panel setHidesOnDeactivate: NO];
    [panel setReleasedWhenClosed: NO];
    [panel setFrameAutosaveName: @"DIXSelectionListPanel"];

    // Make the hosted view fill the panel and resize with it.
    [contentView setFrame: [[panel contentView] bounds]];
    [contentView setAutoresizingMask: NSViewWidthSizable | NSViewHeightSizable];
    [panel setContentView: contentView];

    self = [super initWithWindow: panel];
    [panel release];

    if ( self != nil )
    {
        _hostedView = [contentView retain];
        _parentWindow = [parentWindow retain];
    }
    return self;
}

- (void) dealloc
{
    [_hostedView release];
    [_parentWindow release];
    [super dealloc];
}

- (void) togglePanel: (id) sender
{
    if ( [[self window] isVisible] )
        [[self window] orderOut: sender];
    else
        [self showPanel];
}

- (void) showPanel
{
    NSWindow *panel = [self window];

    // First show: park near the bottom-edge of the parent window to evoke
    // the old drawer's position. After that, autosave takes over.
    if ( ![panel setFrameUsingName: @"DIXSelectionListPanel"] && _parentWindow != nil )
    {
        NSRect pf = [_parentWindow frame];
        NSRect wf = [panel frame];
        wf.origin.x = NSMinX(pf);
        wf.origin.y = NSMinY(pf) - NSHeight(wf) - 8;
        [panel setFrame: wf display: NO];
    }

    [panel orderFront: nil];
}

@end
