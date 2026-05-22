//
//  SelectionListPanelController.h
//  Disk Inventory Z
//
//  Hosts the selection-list view (instantiated inside TreeMap.xib as a
//  loose top-level customView) in a floating NSPanel that the user
//  can show/hide via the View menu, toolbar, or the right-click
//  "Show Files in Selection List" action. Replaces the NSDrawer that
//  used to live on the bottom of the main document window.
//

#import <Cocoa/Cocoa.h>

@interface SelectionListPanelController : NSWindowController
{
    NSView *_hostedView;       // strong reference; the view came from the doc nib
    NSWindow *_parentWindow;   // doc window we float above
}

// `contentView` is the view that becomes the panel's contentView
// (typically the selection-list customView from TreeMap.xib).
// `parentWindow` is the document's main window; the panel floats over it.
- (instancetype) initWithContentView: (NSView*) contentView
                        parentWindow: (NSWindow*) parentWindow;

- (void) togglePanel: (id) sender;
- (void) showPanel;

@end
