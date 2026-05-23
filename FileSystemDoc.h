//
//  FileSystemDoc.h
//  Disk Accountant
//
//  Created by Tjark Derlien on Wed Oct 08 2003.
//
//  Copyright (C) 2003 Tjark Derlien.
//  
//  This program is free software; you can redistribute it and/or
//  modify it under the terms of the GNU General Public License
//  as published by the Free Software Foundation; either version 3
//  of the License, or any later version.
//

//


#import <Cocoa/Cocoa.h>
#import "FSItem.h"
#import "Preferences.h"
#import "LoadingPanelController.h"
#import "FileTypeColors.h"

//holds information about the count and size of the files of one kind (e.g. MP3 files)
@interface FileKindStatistic : NSObject
{
    NSString *_kindName;
	unsigned long long _size;
	NSMutableSet *_items;
}

- (id) initWithItem: (FSItem*) item;

- (void) addItem: (FSItem* )item;
- (void) removeItem: (FSItem* )item;

- (NSString*) kindName;
- (NSString*) description;

- (unsigned) fileCount;		//# of files of this kind
- (unsigned long long) size; //sum of sizes of files of this kind
- (void) recalculateSize;

- (NSSet*) items;
- (NSEnumerator*) itemEnumerator;

- (NSComparisonResult) compareSizeDescendingly: (FileKindStatistic*) other;

@end

@interface FileSystemDoc : NSDocument
{
    FSItem *_rootItem;
    FSItem *_selectedItem;
    NSMutableArray *_zoomStack;
    NSMutableDictionary *_fileKindStatistics;	//dictionary: kind name -> FileKindStatistic
	NSMutableDictionary *_viewOptions;
	FileTypeColors *_kindColors;
	
	//these variables are used during the initial directory scan
	LoadingPanelController *_progressController;
	NSMutableArray *_directoryStack;

	//how long the last scan took, in seconds. Shown in the window title
	//so the user knows what the cost was after the fact.
	double _lastScanDurationSeconds;

	// Stage 8.5: async scan engine.
	// _scanQueue is a per-document serial dispatch queue. Created lazily
	// the first time a scan is kicked off; the walker runs on it.
	// _scanInProgress flips on/off around the worker block — read on main.
	// _cancelRequested is atomic so the worker thread can poll it cheaply
	// from inside the walker without locks; set from main on Cancel /
	// document-close / app-quit.
	dispatch_queue_t _scanQueue;
	BOOL _scanInProgress;
	_Atomic BOOL _cancelRequested;
	// The URL we'll scan on first window-controller appearance. Stored by
	// -readFromURL:ofType:error: (which is now just URL validation); the
	// actual walk kicks off from -makeWindowControllers.
	NSURL *_pendingScanURL;

	// Worker-thread state for the ~4 Hz dispatch_sync refresh barrier.
	// _workerCurrentPath is set by -fsItemEnteringFolder: on the worker;
	// read inside the dispatch_sync block (where worker is paused, so no
	// race). _workerLastRefreshTime is touched only on the worker thread.
	NSString *_workerCurrentPath;
	uint64_t _workerLastRefreshTime;

}

// YES if a background walker is currently populating _rootItem for this
// document. Read-only.
- (BOOL) isScanInProgress;

// Request that an in-flight background scan abort at its next poll point.
// Safe to call from main. No-op if no scan is running.
- (void) requestCancelScan;

// Total scan duration of the last completed scan, in seconds.
- (double) lastScanDurationSeconds;

- (BOOL) showPhysicalFileSize;
- (void) setShowPhysicalFileSize: (BOOL) show;
- (BOOL) showPackageContents;
- (void) setShowPackageContents: (BOOL) show;
- (BOOL) showFreeSpace;
- (void) setShowFreeSpace: (BOOL) show;
- (BOOL) showOtherSpace;
- (void) setShowOtherSpace: (BOOL) show;
- (BOOL) ignoreCreatorCode;
- (void) setIgnoreCreatorCode: (BOOL) ignoreIt;

- (BOOL) itemIsNode: (FSItem*) item; //helper method; returns YES/NO for packages depending on the showPackageContents-Flag

- (FSItem*) rootItem;

- (BOOL) moveItemToTrash: (FSItem*) item error:(NSError **)error;//will post a "FSItemsChangedNotification"
- (void) refreshItem: (FSItem*) item;//will post a "FSItemsChangedNotification"

- (FSItem*) zoomedItem;
- (void) zoomIntoItem: (FSItem*) item; //will post a "ZoomedItemChangedNotification"
- (void) zoomOutToItem: (FSItem*) item;
- (void) zoomOutOneStep;
- (NSArray*) zoomStack;

- (FSItem*) selectedItem;
- (void) setSelectedItem: (FSItem*) item; //will post a "GlobalSelectionChangedNotification"

- (FileKindStatistic*) kindStatisticForItem: (FSItem*) item;
- (FileKindStatistic*) kindStatisticForKind: (NSString*) kindName;
- (NSDictionary*) kindStatistics;

- (FileTypeColors*) fileTypeColors;

- (void) refreshFileKindStatistics;

@end

/* keys for Key Value Observing (KVO) */
extern NSString *DocKeySelectedItem;

/* FileSystemDoc Notifications */
extern NSString *GlobalSelectionChangedNotification; //userInfo contains new and old selection
extern NSString *ZoomedItemChangedNotification; //userInfo contains new and old zoomed item
extern NSString *FSItemsChangedNotification; //some items are modified, deleted or added; userInfo is nil
extern NSString *ViewOptionChangedNotification; //the name of the changed option is stored in userInfo for key ChangedViewOption (see next line)
extern NSString *ChangedViewOption;
extern NSString *NewItem;
extern NSString *OldItem;

// Stage 8.5 Wave 2: posted on main when a background scan begins / finishes.
// DIXScanProgressNotification is posted ~4 Hz from a dispatch_sync barrier
// inside the worker, with userInfo {DIXScanPath: NSString*, DIXScanItemCount: NSNumber*}.
extern NSString *DIXScanStartedNotification;
extern NSString *DIXScanProgressNotification;
extern NSString *DIXScanFinishedNotification;
extern NSString *DIXScanPath;
extern NSString *DIXScanItemCount;
