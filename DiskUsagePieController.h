//
//  DiskUsagePieController.h
//  Disk Inventory Z
//
//  Floating NSPanel that shows a three-wedge pie chart of disk usage
//  (scanned / other used / free) for full-volume scans. Lazily created
//  by MainWindowController when the document is a full-volume scan;
//  not shown for folder-only scans.
//

#import <Cocoa/Cocoa.h>

@class FileSystemDoc;
@class DIXPieChartView;

@interface DiskUsagePieController : NSWindowController
{
    FileSystemDoc *_document;        // weak — document owns this controller chain
    NSWindow *_parentWindow;         // strong; the doc window we float above
    DIXPieChartView *_pieView;       // weak; subview of contentView
    NSTextField *_scannedLabel;      // weak; legend rows
    NSTextField *_otherUsedLabel;
    NSTextField *_freeLabel;
}

- (instancetype) initWithDocument: (FileSystemDoc*) doc
                     parentWindow: (NSWindow*) parentWindow;

- (void) showPanel;

// Re-read the volume sizes from disk and re-pull rootItem.size from the
// document. Safe to call from any FSItemsChangedNotification observer.
- (void) refresh;

@end
