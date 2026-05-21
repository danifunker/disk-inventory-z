/* FileKindsTableController */

#import <Cocoa/Cocoa.h>
#import "FileSystemDoc.h"
#import "FileSizeFormatter.h"
#import "MainWindowController.h"

// Posted by any controller that wants to "show files of a given kind in the
// selection list". userInfo carries:
//   @"kindName": NSString -- the FileKindStatistic.kindName to select.
// FileKindsTableController owns the action because it has direct access to
// the kinds + popup array controllers; other controllers (e.g. the files
// outline view) post the notification to ask for the operation without
// holding a direct reference to FileKindsTableController.
extern NSString * const DIXShowKindInSelectionListNotification;
extern NSString * const DIXShowKindInSelectionListKindNameKey;

@interface FileKindsTableController : NSObject
{
    IBOutlet NSTableView *_tableView;
    IBOutlet MainWindowController *_windowController;
	IBOutlet NSArrayController *_kindsPopupArrayController;
	IBOutlet NSArrayController *_kindsTableArrayController;

    NSMutableDictionary *_cushionImages;
}

- (FileSystemDoc*) document;

- (IBAction) showFilesInSelectionList: (id) sender;

@end
