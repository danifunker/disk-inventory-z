/* MainWindowController */

#import <Cocoa/Cocoa.h>
#import "FileSystemDoc.h"
#import <TreeMapView/TreeMapView.h>
#import "OAToolbarWindowControllerEx.h"
#import "OASplitView.h"

@class SelectionListPanelController;

@interface MainWindowController : OAToolbarWindowControllerEx
{
    IBOutlet NSSplitView *_kindsTopSplit;       // top half of main split: files outline | kinds table
    IBOutlet NSView *_kindsPaneView;            // right side of _kindsTopSplit (kinds-table host view)
    IBOutlet NSView *_selectionListPaneView;    // loose view in TreeMap.xib that becomes the selection-list panel's contentView
	IBOutlet OASplitView *_splitter;            // outer split: (files+kinds) on top | treemap on bottom. "Split Vertically" flips this to L/R.
	IBOutlet NSOutlineView *_filesOutlineView;
	IBOutlet TreeMapView *_treeMapView;
	IBOutlet NSMenu *_openWithSubMenu;

	// Programmatically-injected status bar at the bottom of the window.
	NSTextField *_statusBar;

	// Lazily created on first show.
	SelectionListPanelController *_selectionListPanel;
}

+ (FileSystemDoc*) documentForView: (NSView*) view;

+ (void) poofEffectInView: (NSView*)view inRect: (NSRect) rect; //rect in view coords

// Brings up the selection-list floating panel (creating it on first call).
// Called by FileKindsTableController's "Show Files in Selection List" action.
- (void) showSelectionListPanel;

- (IBAction) openFile:(id)sender;
- (IBAction) toggleFileKindsDrawer:(id)sender;
- (IBAction) toggleSelectionListDrawer:(id)sender;
- (IBAction) zoomIn:(id)sender;
- (IBAction) zoomOut:(id)sender;
- (IBAction) zoomOutTo:(id)sender;
- (IBAction) showInFinder:(id)sender;
- (IBAction) refresh:(id)sender;
- (IBAction) refreshAll:(id)sender;
- (IBAction) moveToTrash:(id)sender;
- (IBAction) showPackageContents:(id)sender;
- (IBAction) showFreeSpace:(id)sender;
- (IBAction) showOtherSpace:(id)sender;
- (IBAction) selectParentItem:(id)sender;
- (IBAction) changeSplitting:(id)sender;
- (IBAction) showInformationPanel:(id)sender;
- (IBAction) showPhysicalSizes:(id) sender;
- (IBAction) ignoreCreatorCode:(id) sender;

- (IBAction) performRenderBenchmark:(id)sender;
- (IBAction) performLayoutBenchmark:(id)sender;
@end
