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

    // If the panel is already on screen, leave it exactly where the user
    // put it. Its contents update via bindings to the document, so we
    // don't need to re-orderFront or reset the frame just because the
    // selection changed.
    if ( [panel isVisible] )
        return;

    // First show: park along the LEFT edge of the screen by default,
    // top-aligned to the parent window. After that, autosave takes over.
    if ( ![panel setFrameUsingName: @"DIXSelectionListPanel"] )
    {
        NSScreen *screen = (_parentWindow != nil ? [_parentWindow screen] : nil)
                           ?: [NSScreen mainScreen];
        NSRect vis = [screen visibleFrame];
        NSRect wf  = [panel frame];
        wf.origin.x = NSMinX(vis) + 10;
        if ( _parentWindow != nil )
            wf.origin.y = NSMaxY([_parentWindow frame]) - NSHeight(wf);
        else
            wf.origin.y = NSMaxY(vis) - NSHeight(wf) - 20;
        // Clamp to screen so it can't land off the visible area.
        if ( wf.origin.y < NSMinY(vis) )
            wf.origin.y = NSMinY(vis);
        [panel setFrame: wf display: NO];
    }

    [panel orderFront: nil];
}

@end
