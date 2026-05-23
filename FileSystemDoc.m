//
//  MyDocument.m
//  Disk Accountant
//
//  Created by Tjark Derlien on Wed Oct 08 2003.
//
//  Copyright (C) 2003 Tjark Derlien.
//  Modifications © 2026 Dani Sarfati.
//  
//  This program is free software; you can redistribute it and/or
//  modify it under the terms of the GNU General Public License
//  as published by the Free Software Foundation; either version 3
//  of the License, or any later version.
//

//

#import "FileSystemDoc.h"
#import "NSURL-Extensions.h"
#import "MainWindowController.h"
#import "DrivesPanelController.h"
#import "FileSizeFormatter.h"
#import "Timing.h"
#import "InfoPanelController.h"
#import "FSItem-Utilities.h"
#import "NSFileManager-Extensions.h"
#import "DrivesPanelController.h"

NSString *CollectFileKindStatisticsCanceledException = @"CollectFileKindStatisticsCanceledException";

//============ implementation FileKindStatistic ==========================================================

@implementation FileKindStatistic

- (id) initWithItem: (FSItem*) item
{
    self = [super init];
    
    _kindName = [item kindName];
	[_kindName retain];

	_size = [item sizeValue];
	
	_items = [[NSMutableSet alloc] initWithObjects: item, nil];

    return self;
}

- (void) dealloc
{
    [_kindName release];
	[_items release];
	
	[super dealloc];
}

- (void) addItem: (FSItem* )item
{
	NSParameterAssert( ![_items containsObject: item] );
	
	[_items addObject: item];
	
	_size += [item sizeValue];
}

- (void) removeItem: (FSItem* )item
{
	NSParameterAssert( [_items containsObject: item] );
	
	_size -= [item sizeValue];
	
	[_items removeObject: item];
}

- (NSString*) description
{
    return [[self kindName] stringByAppendingFormat: @" {%u files; %.1f kB}", [self fileCount], (float) [self size]/1024]; 
}

- (NSString*) kindName
{
    return _kindName;
}

//# of files of this kind
- (unsigned) fileCount
{
	return [_items count];
}

//sum of sizes of files of this kind
- (unsigned long long) size
{
	return _size;
}

- (void) recalculateSize
{
	NSEnumerator *itemEnum = [self itemEnumerator];
	FSItem *item = nil;
	_size = 0;
	while ( (item = [itemEnum nextObject]) != nil )
		_size += [item sizeValue];
}

- (NSSet*) items
{
	return _items;
}

- (NSEnumerator*) itemEnumerator
{
	return [_items objectEnumerator];
}

//compare the size descendingly
- (NSComparisonResult) compareSizeDescendingly: (FileKindStatistic*) other
{
	UInt64 mySize = [self size];
	UInt64 otherSize = [other size];
	
	//we want the sorting to be descending
	if ( mySize < otherSize )
		return NSOrderedDescending;
	if ( mySize > otherSize )
		return NSOrderedAscending;
	
	//if both object have the same size, order by their names
	return [[self kindName] compare: [other kindName] options: NSNumericSearch];
}

@end

//============ interface FileSystemDoc(Private) ==========================================================

@interface FileSystemDoc(Private)

- (void) addItemToFileKindStatistic: (FSItem*) item includingChilds: (BOOL) includingChilds;
- (void) removeItemFromFileKindStatistic: (FSItem*) item includingChilds: (BOOL) includingChilds;
- (void) recalculateFileKindStatisticSizes;
- (void) removePackagesFromFileKindStatistic: (FSItem*) item;
- (void) addPackagesToFileKindStatistic: (FSItem*) item; 	
- (void) removeEmptyKindStatistics;

// Returns YES if the scan should proceed, NO if the user wants to grant
// permissions first (chose "Open System Settings" so the scan should NOT
// start while they're doing that — they'll re-trigger the scan after).
- (BOOL)checkForProtectedFolders:(NSString * _Nonnull)folder;

- (void) reserveColorsForLargestKinds;

- (void) recalculateTotalSize;

- (NSMutableDictionary*) viewOptions;

- (void) postViewOptionChangedNotificationForOption: (NSString*) optionName;
- (void) postNotificationName: (NSString*) name oldItem: (FSItem*) old newItem:  (FSItem*) new;

@end

//=========== implementation FileSystemDoc ==========================================================

/* keys for Key Value Observing (KVO) */
NSString *DocKeySelectedItem = @"selectedItem";

/* FileSystemDoc Notifications */
NSString *GlobalSelectionChangedNotification = @"GlobalSelectionChanged";
NSString *ZoomedItemChangedNotification = @"ZoomedItemChanged";
NSString *FSItemsChangedNotification = @"FSItemsChanged";
NSString *ViewOptionChangedNotification = @"ViewOptionsChangedNotification";
NSString *ChangedViewOption = @"ChangedViewOption";
NSString *NewItem = @"NewItem";
NSString *OldItem = @"OldItem";
NSString *DIXScanStartedNotification = @"DIXScanStarted";
NSString *DIXScanProgressNotification = @"DIXScanProgress";
NSString *DIXScanFinishedNotification = @"DIXScanFinished";
NSString *DIXScanPath = @"DIXScanPath";
NSString *DIXScanItemCount = @"DIXScanItemCount";

@implementation FileSystemDoc

- (id)init
{
    self = [super init];
    if ( self != nil )
    {
        // Add your subclass-specific initialization here.
        // If an error occurs here, send a [self release] message and return nil.
		
        _zoomStack = [[NSMutableArray alloc] init];

		// Initialize early (was lazily populated by refreshFileKindStatistics
		// during the sync scan, but with the async scan in Stage 8.5 the doc
		// window nib loads BEFORE the scan runs, and bindings query
		// kindStatistics during nib load. Without a pre-existing dict the
		// NSAssert in -kindStatistics aborted nib load, blocking awakeFromNib
		// on every controller in TreeMap.xib.
		_fileKindStatistics = [[NSMutableDictionary alloc] init];

		_viewOptions = [[NSMutableDictionary alloc] initWithDefaults];
		
		NSUserDefaultsController *sharedDefsController = [NSUserDefaultsController sharedUserDefaultsController];
		[sharedDefsController addObserver: self
							   forKeyPath: [@"values." stringByAppendingString: ShareKindColors]
								  options: 0
								  context: ShareKindColors];
		[sharedDefsController addObserver: self
							   forKeyPath: [@"values." stringByAppendingString: ShowFreeSpace]
								  options: 0
								  context: ShowFreeSpace];
		[sharedDefsController addObserver: self
							   forKeyPath: [@"values." stringByAppendingString: ShowOtherSpace]
								  options: 0
								  context: ShowOtherSpace];
    }
    return self;
}

- (void) dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver: self];        
	
	NSUserDefaultsController *sharedDefsController = [NSUserDefaultsController sharedUserDefaultsController];
	[sharedDefsController removeObserver: self forKeyPath: [@"values." stringByAppendingString: ShareKindColors]];
	[sharedDefsController removeObserver: self forKeyPath: [@"values." stringByAppendingString: ShowFreeSpace]];
	[sharedDefsController removeObserver: self forKeyPath: [@"values." stringByAppendingString: ShowOtherSpace]];
	
	[_viewOptions release];
    [_fileKindStatistics release];
    [_zoomStack release];
	
    [_rootItem release];

	[_directoryStack release];

	[_kindColors release];

    [_pendingScanURL release];
    if ( _scanQueue != NULL )
    {
        dispatch_release(_scanQueue);
        _scanQueue = NULL;
    }

    [super dealloc];
}

- (void) close
{
    // Bring the drives panel back when the doc closes (cancelled scan,
    // Cmd-W, etc.) so the user lands on the disk-selection screen rather
    // than triggering applicationShouldTerminateAfterLastWindowClosed and
    // quitting the app. If they open another doc, the standard open path
    // (MyDocumentController) hides the drives panel again.
    [super close];
    [[DrivesPanelController sharedController] showPanel];
}

- (void) makeWindowControllers
{
    MainWindowController *controller = [[MainWindowController alloc] initWithWindowNibName: [self windowNibName]];
    [self addWindowController:controller];
    [controller release];

    // Stage 8.5: kick off the async scan now that the doc window exists.
    // -readFromURL:ofType:error: only validates and stashes the URL —
    // the actual walk happens here so the loading sheet can attach to a
    // real window. dispatch_async to next runloop turn so showWindows
    // (called by NSDocumentController right after makeWindowControllers)
    // gets a chance to make the window visible first.
    if ( _pendingScanURL != nil )
    {
        NSURL *url = [_pendingScanURL retain];
        [_pendingScanURL release];
        _pendingScanURL = nil;

        dispatch_async(dispatch_get_main_queue(), ^{
            [self startBackgroundScanForURL: url];
            [url release];
        });
    }
}


- (NSString *)windowNibName
{
    // Override returning the nib file name of the document
    // If you need to use a subclass of NSWindowController or if your document supports multiple NSWindowControllers, you should remove this method and override -makeWindowControllers instead.
    return @"TreeMap";
}

- (void)windowControllerDidLoadNib:(NSWindowController *) aController
{
    [super windowControllerDidLoadNib:aController];
    // Add any code here that needs to be executed once the windowController has loaded the document's window.
}

#pragma mark ----------------- async scan engine (Stage 8.5) -----------------

#include <stdatomic.h>

- (BOOL) isScanInProgress
{
    return _scanInProgress;
}

- (void) requestCancelScan
{
    atomic_store(&_cancelRequested, YES);
}

// NSDocument override: this is the synchronous "read" entry point that
// NSDocumentController calls. We DO NOT walk the directory tree here —
// we just validate the URL and stash it for -makeWindowControllers to
// pick up. Returning YES from here makes NSDocumentController think the
// doc loaded successfully; the actual scan then happens asynchronously
// once a window controller is in place.
- (BOOL) readFromURL: (NSURL*) url
              ofType: (NSString*) typeName
               error: (NSError**) outError
{
    // Validate: must exist and be a directory.
    NSNumber *isDir = nil;
    BOOL ok = [url getResourceValue: &isDir forKey: NSURLIsDirectoryKey error: nil];
    if ( !ok || ![isDir boolValue] )
    {
        if ( outError != nil )
            *outError = [NSError errorWithDomain: NSCocoaErrorDomain
                                            code: NSFileReadNoSuchFileError
                                        userInfo: @{ NSURLErrorKey: url }];
        return NO;
    }

    if ( ![self checkForProtectedFolders: [url path]] )
    {
        // User chose to grant permissions first. Treat as a user-cancel so
        // NSDocumentController doesn't open the doc or show an error sheet.
        if ( outError != nil )
            *outError = [NSError errorWithDomain: NSCocoaErrorDomain
                                            code: NSUserCancelledError
                                        userInfo: nil];
        return NO;
    }

    [_pendingScanURL release];
    _pendingScanURL = [url retain];

    // Create an empty root FSItem stub for the URL so the doc window's
    // nib load (which happens BEFORE the async scan walks the tree) has
    // a valid root for KVO/bindings to inspect. The walker fills in its
    // children later. Without this stub, TreeMapViewController's
    // -awakeFromNib creates "other space" / "free space" items with a
    // nil parent, and -fileURL recurses forever via -root.
    [_rootItem release];
    _rootItem = [[FSItem alloc] initWithURL: url];
    return YES;
}

- (void) startBackgroundScanForURL: (NSURL*) url
{
    NSParameterAssert( [NSThread isMainThread] );
    if ( _scanInProgress )
    {
        LOG(@"startBackgroundScanForURL: refusing — scan already in progress");
        return;
    }

    NSWindow *docWindow = nil;
    if ( [[self windowControllers] count] > 0 )
    {
        docWindow = [[[self windowControllers] objectAtIndex: 0] window];
        [docWindow makeKeyAndOrderFront: nil];
        // Replace the nib's default "Window" title until the scan finishes
        // and synchronizeWindowTitleWithDocumentName picks up the real name.
        [docWindow setTitle: NSLocalizedString(@"Scanning…", @"")];
    }

    // Create the per-doc serial scan queue lazily on first use.
    if ( _scanQueue == NULL )
    {
        _scanQueue = dispatch_queue_create("io.github.danifunker.disk-inventory-z.scan",
                                           DISPATCH_QUEUE_SERIAL);
    }

    // Reset run-state.
    atomic_store(&_cancelRequested, NO);
    _scanInProgress = YES;
    g_fileCount = 0;
    g_folderCount = 0;

    // _rootItem was created as an empty stub in -readFromURL:ofType:error:.
    // The walker builds each top-level child as a detached orphan
    // (parent=nil) on the worker thread, then dispatches each completed
    // orphan to main where it's spliced into _rootItem via
    // -insertChild:updateParent:YES. _rootItem is therefore mutated ONLY
    // on main — AppKit can safely redraw the treemap / outline at any
    // time (window resize, expose, modal alerts) without racing the
    // worker because the worker never touches anything main can see.
    [_rootItem setDelegate: self];

    [[NSNotificationCenter defaultCenter] postNotificationName: DIXScanStartedNotification
                                                        object: self
                                                      userInfo: @{ DIXScanPath: [url path] }];

    uint64_t startTime = getTime();
    NSURL *capturedURL = [url retain];
    BOOL usePhysicalSize = [self showPhysicalFileSize];
    BOOL showPackageContents = [self showPackageContents];

    dispatch_async(_scanQueue, ^{
        @autoreleasepool
        {
            [self runTopLevelOrchestrationForURL: capturedURL
                                 usePhysicalSize: usePhysicalSize
                             showPackageContents: showPackageContents];

            BOOL cancelled = atomic_load(&_cancelRequested);
            uint64_t doneLoadingTime = getTime();
            LOG(@"loading time: %.2f seconds (cancelled=%d)",
                subtractTime(doneLoadingTime, startTime), cancelled);
            LOG(@"%u items: %u files, %u folders",
                g_fileCount + g_folderCount, g_fileCount, g_folderCount);

            dispatch_async(dispatch_get_main_queue(), ^{
                if ( !cancelled )
                {
                    // Recompute the root's size from scratch. The per-splice
                    // -insertChild:updateParent:YES accumulates size, but a
                    // final pass guarantees we account for any edge case
                    // (hardlink dedup, package sizing) that incremental sums
                    // might have missed.
                    [_rootItem recalculateSize: [self showPhysicalFileSize]
                                  updateParent: NO];

                    // Reset color assignments so the final treemap render
                    // assigns the palette in size-descending order (matches
                    // the original sync-scan behavior). Without this the
                    // colors are whatever got handed out in scan order.
                    [_kindColors reset];
                    [_kindColors release];
                    _kindColors = nil;

                    [self refreshFileKindStatistics];
                    _lastScanDurationSeconds = subtractTime(getTime(), startTime);
                }
                [self finishBackgroundScanCancelled: cancelled];
                [capturedURL release];
            });
        }
    });
}

// Worker-side top-level orchestration. Enumerates the scan root's
// direct children (depth 1), and for each one builds a detached orphan
// FSItem on this thread, then dispatches the completed orphan to main
// where it is spliced into _rootItem. The orphan's subtree is entirely
// worker-local during the walk; once dispatched, ownership transfers
// to main and the worker never touches it again.
- (void) runTopLevelOrchestrationForURL: (NSURL*) rootURL
                        usePhysicalSize: (BOOL) usePhysicalSize
                    showPackageContents: (BOOL) showPackageContents
{
    [FSItem resetHardlinkDedup];

    NSArray<NSURLResourceKey> *keys = @[
        NSURLIsDirectoryKey, NSURLIsPackageKey, NSURLIsVolumeKey,
        NSURLNameKey, NSURLTypeIdentifierKey,
        NSURLFileSizeKey, NSURLTotalFileAllocatedSizeKey
    ];

    NSError *err = nil;
    NSArray<NSURL*> *topLevel =
        [[NSFileManager defaultManager] contentsOfDirectoryAtURL: rootURL
                                      includingPropertiesForKeys: keys
                                                         options: 0
                                                           error: &err];
    if ( topLevel == nil )
    {
        LOG(@"top-level enumeration failed for %@: %@", rootURL, err);
        return;
    }

    for ( NSURL *childURL in topLevel ) @autoreleasepool
    {
        if ( atomic_load(&_cancelRequested) )
            break;

        // /Volumes cross-mounts back to the boot volume and to every
        // disk-image / external mount on the system. Always skip.
        if ( [[childURL path] isEqualToString: @"/Volumes"] )
            continue;
        // .nofollow / .resolve are macOS 26 (Tahoe) magic root directories
        // that expose a symlink-resolution-disabled re-rooted view of the
        // filesystem — walking them effectively duplicates the entire
        // tree. Match by last path component so we catch them whether
        // they appear at / or under /System/Volumes/Data/ etc.
        NSString *leaf = [childURL lastPathComponent];
        if ( [leaf isEqualToString: @".nofollow"]
             || [leaf isEqualToString: @".resolve"] )
            continue;

        FSItem *orphan = [[FSItem alloc] initWithURL: childURL];
        [orphan setDelegate: self];

        // Update the overlay path even for non-folder top-level entries.
        [_workerCurrentPath release];
        _workerCurrentPath = [[childURL path] copy];

        BOOL isDir = NO, isPkg = NO, isVol = NO;
        NSNumber *n = nil;
        if ( [childURL getResourceValue: &n forKey: NSURLIsDirectoryKey error: nil] && n )
            isDir = [n boolValue];
        if ( [childURL getResourceValue: &n forKey: NSURLIsPackageKey error: nil] && n )
            isPkg = [n boolValue];
        if ( [childURL getResourceValue: &n forKey: NSURLIsVolumeKey error: nil] && n )
            isVol = [n boolValue];

        @try
        {
            if ( isDir && !isVol && (!isPkg || showPackageContents) )
            {
                [orphan loadChildren];
            }
            else if ( isDir && isPkg && !showPackageContents )
            {
                // Opaque package: sum descendant sizes without allocating
                // FSItems for the contents.
                unsigned long long pkgSize = 0;
                NSDirectoryEnumerator *pkgEnum =
                    [[NSFileManager defaultManager] enumeratorAtURL: childURL
                                         includingPropertiesForKeys: @[ NSURLTotalFileAllocatedSizeKey,
                                                                        NSURLFileAllocatedSizeKey ]
                                                            options: 0
                                                       errorHandler: nil];
                for ( NSURL *u in pkgEnum ) @autoreleasepool
                {
                    if ( atomic_load(&_cancelRequested) ) break;
                    NSNumber *sz = nil;
                    NSURLResourceKey sk = usePhysicalSize ? NSURLTotalFileAllocatedSizeKey
                                                          : NSURLFileAllocatedSizeKey;
                    [u getResourceValue: &sz forKey: sk error: nil];
                    if ( sz != nil )
                        pkgSize += [sz unsignedLongLongValue];
                }
                [orphan setSizeValue: pkgSize];
            }
            // else: regular file (size already set in init), or volume mount
            // point (we don't descend into mounted volumes).
        }
        @catch ( NSException *ex )
        {
            // Cancel raises FSItemLoadingCanceledException; drop the partial
            // orphan and stop iterating.
            LOG(@"top-level walk exception for %@: %@ — %@",
                childURL, [ex name], [ex reason]);
            [orphan release];
            // Clear walker-thread bookkeeping touched by loadChildren.
            [_directoryStack release];
            _directoryStack = nil;
            break;
        }

        // Reset per-orphan walker state so the next top-level call into
        // -fsItemEnteringFolder: sees an empty _directoryStack (its
        // NSParameterAssert requires lastObject == [item parent]).
        [_directoryStack release];
        _directoryStack = nil;

        // Strip delegate before publishing — once spliced under _rootItem
        // the orphan inherits the real root's delegate via [self root].
        [orphan setDelegate: nil];

        if ( atomic_load(&_cancelRequested) )
        {
            [orphan release];
            break;
        }

        // Transfer ownership of orphan + its entire subtree to main.
        FSItem *toPublish = orphan;
        dispatch_async(dispatch_get_main_queue(), ^{
            if ( atomic_load(&_cancelRequested) || !_scanInProgress )
            {
                [toPublish release];
                return;
            }
            [_rootItem insertChild: toPublish updateParent: YES];
            [toPublish release];
            [[NSNotificationCenter defaultCenter]
                postNotificationName: FSItemsChangedNotification
                              object: self];
        });

        // Refresh the overlay between top-level walks too (in case the
        // walker hasn't hit a maybeRefreshScanCheckpoint tick recently).
        [self maybeRefreshScanCheckpoint];
    }
}

// Called from the worker thread (-fsItemEnteringFolder: /
// -fsItemShouldContinueLoading) at the ~4 Hz cadence. Synchronously hops
// to main and posts notifications so the outline view, treemap, and
// overlay text refresh from a consistent snapshot of _rootItem. The
// worker is paused for the duration of the block — that pause IS the
// thread-safety mechanism (no locks needed, since the only mutator of
// the tree is this worker queue).
- (void) scanRefreshCheckpointFromWorker
{
    if ( !_scanInProgress )
        return;
    if ( atomic_load(&_cancelRequested) )
        return;

    // Snapshot what's safe to capture before hopping (g_fileCount is
    // atomic; _workerCurrentPath is set on worker so we can read it here).
    NSString *path = _workerCurrentPath != nil ? [[_workerCurrentPath copy] autorelease] : @"";
    NSUInteger items = (NSUInteger) g_fileCount + (NSUInteger) g_folderCount;

    dispatch_sync(dispatch_get_main_queue(), ^{
        if ( !_scanInProgress )
            return;
        // Only the overlay updates live during a scan. _rootItem stays
        // empty until the worker completes and we swap _workerRoot into
        // it; that's what makes redraws of the (empty) tree race-free.
        [[NSNotificationCenter defaultCenter]
            postNotificationName: DIXScanProgressNotification
                          object: self
                        userInfo: @{ DIXScanPath: path,
                                     DIXScanItemCount: @(items) }];
    });
}

- (void) finishBackgroundScanCancelled: (BOOL) cancelled
{
    NSParameterAssert( [NSThread isMainThread] );

    if ( _progressController != nil )
    {
        [_progressController close];
        [_progressController release];
        _progressController = nil;
    }

    [_directoryStack release];
    _directoryStack = nil;

    [_workerCurrentPath release];
    _workerCurrentPath = nil;
    _workerLastRefreshTime = 0;

    _scanInProgress = NO;

    // Notify the UI to tear down the inline overlay (Wave 2).
    [[NSNotificationCenter defaultCenter] postNotificationName: DIXScanFinishedNotification
                                                        object: self
                                                      userInfo: @{ @"cancelled": @(cancelled) }];

    if ( cancelled )
    {
        // Swap the partial tree for an empty stub BEFORE closing. The
        // TreeMapView keeps a TMVItem renderer cache that holds raw
        // pointers into our FSItem tree; if we close while that cache
        // still references the spliced top-level subtrees, the close →
        // doc-dealloc cascade frees those FSItems and the deferred CA
        // transaction flush during terminate redraws the treemap against
        // freed memory (boom). Posting FSItemsChangedNotification with an
        // empty _rootItem makes TreeMapViewController.itemsChanged rebuild
        // the renderer cache from nothing, so subsequent draws are safe.
        NSURL *url = [[[_rootItem fileURL] retain] autorelease];
        [_rootItem release];
        _rootItem = [[FSItem alloc] initWithURL: url];
        [[NSNotificationCenter defaultCenter]
            postNotificationName: FSItemsChangedNotification object: self];

        [self close];
        return;
    }

    // Title sync — let the window controllers pick up the new doc name
    // now that the scan produced a non-empty model.
    for ( NSWindowController *wc in [self windowControllers] )
        [wc synchronizeWindowTitleWithDocumentName];

    // Tell everyone the doc has data now.
    [[NSNotificationCenter defaultCenter] postNotificationName: FSItemsChangedNotification
                                                        object: self];
}

- (IBAction) cancelScanningFolder:(id)sender
{
	[[NSApplication sharedApplication] stopModal];
}

- (BOOL) showPhysicalFileSize;
{
    return [[self viewOptions] showPhysicalFileSize];
}

- (void) setShowPhysicalFileSize: (BOOL) show
{
	[[self viewOptions] setShowPhysicalFileSize: show];
	
	[self recalculateTotalSize];
	[self recalculateFileKindStatisticSizes];
	
	[self postViewOptionChangedNotificationForOption: ShowPhysicalFileSize];
}

- (BOOL) showPackageContents
{
    return [[self viewOptions] showPackageContents];
}

- (void) setShowPackageContents: (BOOL) show
{
    show = (show == 0) ? NO : YES;
    if ( show == [[self viewOptions] showPackageContents] )
		return;
    
	// update kind statistics to reflect the chnage in view
    {
        //remove all packages from kind statistic as they are now regarded differently (file<->folder)
        //[self removePackagesFromFileKindStatistic: nil];
        
        [[self viewOptions] setShowPackageContents: show];

        // the methods "removePackagesFromFileKindStatistic" (was called above) and "addPackagesToFileKindStatistic" (was called below)
        // do not work correctly in all cases
        // so for now, we just rebuild the whole statictics which takes more time, but works
        [self refreshFileKindStatistics];

        //re-add packages to statistic
        //[self addPackagesToFileKindStatistic: nil];
    }
    
    FSItem* selectedItem = [self selectedItem];
	
	//invalidate current selection, as the selection might be an item in a package
	//(if "show package content" is turned off, files in packages aren't visible any more)
	if ( ![self showPackageContents] && selectedItem != nil )
		[self setSelectedItem: nil];
	
	[self postViewOptionChangedNotificationForOption: ShowPackageContents];
	
	//if "show package contents" is turned off, check if selection is within a package
	//(as the selection got invalid)
	if ( ![self showPackageContents] && selectedItem != nil)
	{
		//select it's farest parent which is a package
		FSItem *packageItem = nil;
		FSItem *parentItem = [selectedItem parent];
		while ( parentItem != nil && parentItem != [self zoomedItem] )
		{
			if ( [parentItem isPackage] )
				packageItem = parentItem;
			parentItem = [parentItem parent];
		}
		
		selectedItem = packageItem;
	}
	
	//restore selection
	if ( ![self showPackageContents] && selectedItem != nil )
		[self setSelectedItem: selectedItem];
}

- (BOOL) showFreeSpace
{
    return [[self viewOptions] showFreeSpace];
}

- (void) setShowFreeSpace: (BOOL) show
{
	[[self viewOptions] setShowFreeSpace: show];
	
	[self postViewOptionChangedNotificationForOption: ShowFreeSpace];
}

- (BOOL) showOtherSpace
{
    return [[self viewOptions] showOtherSpace];
}

- (void) setShowOtherSpace: (BOOL) show
{
	[[self viewOptions] setShowOtherSpace: show];
	
	[self postViewOptionChangedNotificationForOption: ShowOtherSpace];
}

- (BOOL) ignoreCreatorCode
{
	return [[self viewOptions] ignoreCreatorCode];
}

- (void) setIgnoreCreatorCode: (BOOL) ignoreIt
{
    /*
	[[self viewOptions] setIgnoreCreatorCode: ignoreIt];
	
	[[self rootItem] setKindStringIgnoringCreatorCode: ignoreIt includeChilds: YES];
	
	[self refreshFileKindStatistics];
	
	[self postViewOptionChangedNotificationForOption: IgnoreCreatorCode];
     */
}

//helper method; returns YES/NO for packages in dependency of the showPackageContents-Flag
- (BOOL) itemIsNode: (FSItem*) item
{
    //the zoomed item is always a node, even if it is a package and "show package contents" is turned off
    //(you can always zoom into packages)
    if ( item == [self zoomedItem] )
        return YES;
    
    if ( [self showPackageContents] )
        return [item isFolder];
    else
        return [item isFolder] && ![item isPackage];
}

- (FSItem*) rootItem;
{
    return _rootItem;
}

- (BOOL) moveItemToTrash: (FSItem*) item error:(NSError **)error
{
	NSParameterAssert( item != nil && item != [self zoomedItem] && ![item isSpecialItem] );
	
	// file moved to trash (it's new URL)
    NSURL *newFileInTrash = nil;
    // FSItem representing the trash folder
    FSItem *trashItem = nil;

	//As the trash visible to the user only shows trashed files/folders on local volumes,
	//we delete files/folders on network volumes (like the Finder does).
	//If we would perform a NSWorkspaceRecycleOperation on a file/folder residing on a network volume,
	//it would be moved to .Trashes/.<user-id> on that volume.
	
	if ( [[item fileURL] isLocalVolume] )
	{
        NSFileManager *fm = [NSFileManager defaultManager];
        
        NSURL *trashURL = [fm URLForDirectory:NSTrashDirectory inDomain:NSUserDomainMask appropriateForURL:[item fileURL] create:NO error:nil];
        
        if ( trashURL != nil )
            trashItem = [[self rootItem] findItemByAbsolutePath: [trashURL path] allowAncestors: NO];
        
        // move file/folder to trash
        if ( ![fm trashItemAtURL:[item fileURL] resultingItemURL:&newFileInTrash error:error] )
            return NO;
	}
	else
    {
        // delete file
        if ( ![[NSFileManager defaultManager] removeItemAtURL:[item fileURL] error: error] )
               return NO;
    }
	
	//if the selected item should be removed, invalidate our selection
	if ( [self selectedItem] == item )
		[self setSelectedItem: nil];
    
    // keep data model in sync: remove from folder item, add to trash item, update file kind statistic
	
	// remove the item from the parent's list
	FSItem *parent = [item parent];
	NSAssert( parent != nil, @"root item shouldn't be deletable" );
	
	//retain and autorelease "item", so it will be accessible till all is done
	[[item retain] autorelease];
	
	[parent removeChild: item updateParent: YES];
	
	//keep kind statistic in sync
	[self willChangeValueForKey: @"kindStatistics"];
	[self removeItemFromFileKindStatistic: item includingChilds: YES];
	
	//the users's trash may have been created with the trash operation (if item is not on the same volume as the user's home)
	//in this case, we won't see the trashed item, as we are not showing the trash folder currently 
	if ( trashItem != nil && newFileInTrash != nil )
    {
        //keep the size of "itemTrashed", but associate with the valid URL
        [item setFileURL: newFileInTrash];

        [trashItem insertChild: item updateParent: YES];
        
        //keep kind statistic in sync
        [self addItemToFileKindStatistic: item includingChilds: YES];
    }
    
	//"checkTrash" may have editied the kind statistic, so notify observers but now
	[self didChangeValueForKey: @"kindStatistics"];
	
	//notify observers of the change
	[[NSNotificationCenter defaultCenter] postNotificationName: FSItemsChangedNotification object: self];
	
	//try to set "parent" as new selection
	if ( parent != [self zoomedItem] )
		[self setSelectedItem: parent];
	
	return YES;
}

- (void) refreshItem: (FSItem*) item
{
	//refresh zoomed item?
	if ( item == nil )
		item = [self zoomedItem];
	
	//remember selection
	NSString *selectedItemPath = nil;
	if ( [self selectedItem] != nil ) 
	{
		selectedItemPath = [[self selectedItem] path];
		[self setSelectedItem: nil];
	}
	
	//refresh item or one of it's ancestors (whichever is still valid)
	BOOL zoomedItemIsInvalid = NO;
	while ( item != nil && ![item exists] )
	{
		if ( item == [self zoomedItem] )
			zoomedItemIsInvalid = YES;
		
		item = [item parent];
	}
	
	if ( item == nil )
	{
		//the folder/volume which we are showing doesn't exist anymore!
        NSString *msg = [NSString stringWithFormat: @"\"%@\" does not exist any more.", [[self rootItem] displayPath]];
        NSString *subMsg = NSLocalizedString( @"The folder will remain visible in Disk Inventory Z, but the files cannot be accessed (e.g. shown in the Finder).",@"");
        
        NSAlert *alert = [[[NSAlert alloc] init] autorelease];
        alert.alertStyle = NSAlertStyleInformational;
        alert.messageText = msg;
        alert.informativeText = subMsg;
        [alert beginSheetModalForWindow: [[[self windowControllers] objectAtIndex: 0] window] completionHandler: nil];

		return;
	}
	
	FSItem *refreshedItem = nil;
	
	NS_DURING
		//we only show a progress indicator if the item to refresh has "many" childs
		//(of course this could have changed since the loading, but what criteria should
		//we use instead?)
		NSAssert( _progressController == nil, @"progress panel wasn't destroyed after last use" );
		unsigned progressPanelLimit = ![[item fileURL] isLocalVolume] ? 200 : 500;
		if ( [item deepFileCountIncludingPackages: YES] > progressPanelLimit )
		{
			//NSWindow *window = [[[self windowControllers] objectAtIndex: 0] window];
			_progressController = [[LoadingPanelController alloc] init];
			[_progressController startAnimation];
		}
		
		refreshedItem = [[[FSItem alloc] initWithPath: [item path]] autorelease];
		[refreshedItem setDelegate: self];
		if ( [refreshedItem isFolder] )
			 [refreshedItem loadChildren];

		[_progressController close];
		[_progressController release];
		_progressController = nil;
	NS_HANDLER
		[_progressController closeNoModalEnd];
		[_progressController release];
		_progressController = nil;
		
		if ( [[localException name] isEqualToString: FSItemLoadingCanceledException]
			 || [[localException name] isEqualToString: CollectFileKindStatisticsCanceledException] )
		{
			//refreshing canceled by user
		}
		else
		{
			//error
            NSAlert *alert = [[[NSAlert alloc] init] autorelease];
            alert.alertStyle = NSAlertStyleInformational;
            alert.messageText = NSLocalizedString( @"The folder's content could not be loaded.", @"");
            alert.informativeText = [localException reason];
            [alert beginSheetModalForWindow: [[[self windowControllers] objectAtIndex: 0] window] completionHandler: nil];

		}
		NS_VOIDRETURN;
	NS_ENDHANDLER
	
	//keep item valid till we are done
	[[item retain] autorelease];
	
	if ( _rootItem == item )
	{
		[_rootItem release];
		_rootItem = [refreshedItem retain];
		//rebuild file kind statistics
		[self refreshFileKindStatistics];
	}
	else
	{
		//update file kind statistics
		if ( !zoomedItemIsInvalid )
			[self willChangeValueForKey: @"kindStatistics"];
		
		[self removeItemFromFileKindStatistic: item includingChilds: YES];
		
		FSItem *parent = [item parent];
		[parent replaceChild: item withItem: refreshedItem updateParent: YES];
		
		[self addItemToFileKindStatistic: refreshedItem includingChilds: YES];
		
		if ( !zoomedItemIsInvalid )
			[self didChangeValueForKey: @"kindStatistics"];
	}
	
	//if current zoomed item got invalid, zoom out as far as necessary
	if ( zoomedItemIsInvalid )
	{
		FSItem *newZoomItem = item;
		//zoom to an ancestor of "item" which is in the zoom stack
		while ( [_zoomStack indexOfObjectIdenticalTo: newZoomItem] == NSNotFound && newZoomItem != nil )
			newZoomItem = [newZoomItem parent];

		//will posts a notification about the change
		[self zoomOutToItem: newZoomItem];
	}
	else
	{
		if ( [_zoomStack lastObject] == item )
			[_zoomStack replaceObjectAtIndex: ([_zoomStack count]-1) withObject: refreshedItem];
		
		//notify observers of the change
		[[NSNotificationCenter defaultCenter] postNotificationName: FSItemsChangedNotification object: self];
	}

	//set selection
	if ( selectedItemPath != nil )
	{
		//find previously select item or one of it's ancestors (whichever still exists)
		FSItem *zoomedItem = [self zoomedItem];
		
		FSItem *newSelection = [zoomedItem findItemByAbsolutePath: selectedItemPath allowAncestors: YES];
				
		if ( newSelection != nil && newSelection != zoomedItem )
			[self setSelectedItem: newSelection];
	}
}

- (FSItem*) zoomedItem
{
    return [_zoomStack count] == 0 ? [self rootItem] : [_zoomStack lastObject];
}

- (void) zoomIntoItem: (FSItem*) item
{
    if ( [_zoomStack count] > 0 && item == [_zoomStack lastObject] )
        return;
	
	FSItem *oldZoomedItem = [self zoomedItem];
    
    //reset selection as the currently selected item might not be a child of the item to zoom in
    [self setSelectedItem: nil];

    [_zoomStack addObject: item];
    
    //the file kind statistic should only cover the currently visible part of the file system tree
    //(this depends on the zoomed item and whether package contents is shown or not)
    [self refreshFileKindStatistics];

    [self postNotificationName: ZoomedItemChangedNotification oldItem: oldZoomedItem newItem: [self zoomedItem]];
}

- (void) zoomOutOneStep
{
    if ( [_zoomStack count] > 0 )
    {
		FSItem *oldZoomedItem = [[[self zoomedItem] retain] autorelease];
		
        [_zoomStack removeLastObject];
        
        //the file kind statistic should only cover the currently visible part of the file system tree
        //(this depends on the zoomed item and whether package contents is shown or not)
        [self refreshFileKindStatistics];
		
		//there is no "other" space if a complete volume is shown 
		if ( [[self viewOptions] showOtherSpace] && [[[self zoomedItem] fileURL] isVolume] )
			[[self viewOptions] setShowOtherSpace: NO]; //don't use our set-method as we don't want any notifications posted

		[self postNotificationName: ZoomedItemChangedNotification oldItem: oldZoomedItem newItem: [self zoomedItem]];
    }
}

- (void) zoomOutToItem: (FSItem*) item
{
    NSAssert( [_zoomStack count] > 0, @"can't zoom out if zoom stack is empty" );
    
    NSParameterAssert( item == nil
                       || item == [self rootItem]
                       || [_zoomStack indexOfObjectIdenticalTo: item] != NSNotFound );
    
	FSItem *oldZoomedItem = [[[self zoomedItem] retain] autorelease];
	
    if ( item == nil || item == [self rootItem] )
    {
        [_zoomStack removeAllObjects];
    }
    else if ( [_zoomStack count] == 1 )
    {
        NSAssert( item == [_zoomStack lastObject], @"zoom error");
        [_zoomStack removeAllObjects];
    }
    else
    {
        NSUInteger itemIndex = [_zoomStack indexOfObjectIdenticalTo: item];
        if ( itemIndex != NSNotFound )
        {
            unsigned itemsToRemove = [_zoomStack count] - itemIndex - 1;
            for ( ; itemsToRemove > 0; itemsToRemove-- )
                [_zoomStack removeLastObject];
        }
        
    }
    
    //the file kind statistic should only cover the currently visible part of the file system tree
    //(this depends on the zoomed item and whether package contents is shown or not)
    [self refreshFileKindStatistics];

	//there is no "other" space if a complete volume is shown 
	if ( [[self viewOptions] showOtherSpace] && [[[self zoomedItem] fileURL] isVolume] )
		[[self viewOptions] setShowOtherSpace: NO]; //don't use our set-method as we don't want any notifications posted

	[self postNotificationName: ZoomedItemChangedNotification oldItem: oldZoomedItem newItem: [self zoomedItem]];
}

- (NSArray*) zoomStack
{
	return _zoomStack;
}

- (FSItem*) selectedItem
{
    return _selectedItem;
}

- (void) setSelectedItem: (FSItem*) item
{
    if ( _selectedItem == item )
        return;

	FSItem *oldSelectedItem = _selectedItem;
    
	_selectedItem = item;
		
    //post notification
	[self postNotificationName: GlobalSelectionChangedNotification oldItem: oldSelectedItem newItem: _selectedItem];
	
	//keep info panel in sync
	if ( [[InfoPanelController sharedController] panelIsVisible] )
		[[InfoPanelController sharedController] showPanelWithFSItem: _selectedItem];
}

- (NSString *)displayName
{
    NSString *displayName = [[self zoomedItem] displayName];

	FileSizeFormatter *sizeFormatter = [[[FileSizeFormatter alloc] init] autorelease];

    displayName = [displayName stringByAppendingFormat: @" (%@)", [sizeFormatter stringForObjectValue: [[self zoomedItem] size]]];

    // Append the duration of the most recent scan so it's persistently
    // visible in the window's title bar after the loading panel closes.
    if ( _lastScanDurationSeconds > 0 )
    {
        unsigned long total = (unsigned long) _lastScanDurationSeconds;
        unsigned mm = (unsigned)(total / 60);
        unsigned ss = (unsigned)(total % 60);
        displayName = [displayName stringByAppendingFormat:
            @" — scanned in %02u:%02u", mm, ss];
    }

    return displayName;
}

- (double) lastScanDurationSeconds
{
    return _lastScanDurationSeconds;
}

- (NSDictionary*) kindStatistics
{
    // Initialized to an empty NSMutableDictionary in -init so this is never
    // nil even before the first scan completes. The old NSAssert blew up
    // during nib load now that the doc window opens before the scan.
    return _fileKindStatistics;
}

- (FileKindStatistic*) kindStatisticForItem: (FSItem*) item
{
    return [self kindStatisticForKind: [item kindName]];
}

- (FileKindStatistic*) kindStatisticForKind: (NSString*) kindName
{
    return [[self kindStatistics] objectForKey: kindName];
}

- (FileTypeColors*) fileTypeColors
{
	if ( _kindColors == nil )
	{
		if ( [[NSUserDefaults standardUserDefaults] boolForKey: ShareKindColors] )
			_kindColors = [[FileTypeColors instance] retain];
		else
			_kindColors = [[FileTypeColors alloc] init];
	}

	return _kindColors;
}

- (void) refreshFileKindStatistics
{
	[self willChangeValueForKey: @"kindStatistics"];
	
	//collect sizes and file count of all file kinds 
	[self addItemToFileKindStatistic: nil includingChilds: YES];
	
	//reserve the predefined colors for the kinds with the biggest size sums of the appropriate files
	[self reserveColorsForLargestKinds];
	
	[self didChangeValueForKey: @"kindStatistics"];
}

#pragma mark ----------------------FSItem delegates-----------------------------------

// NOTE (Stage 8.5 Wave 2): these delegate callbacks run on the worker
// scan queue. _directoryStack and _workerCurrentPath are touched only
// here, so they stay worker-thread-local except inside the dispatch_sync
// barrier (-scanRefreshCheckpointFromWorker) where the worker is paused
// and main reads them safely.
- (BOOL) fsItemEnteringFolder: (FSItem*) item
{
	if ( !_scanInProgress )
		return YES; //YES == continue loading

	if ( _directoryStack == nil )
		_directoryStack = [[NSMutableArray alloc] initWithCapacity: 20];

	NSParameterAssert( [_directoryStack lastObject] == [item parent] );
	[_directoryStack addObject: item];

	// Track the current top-level folder for the inline-overlay progress
	// text. We surface only the top 4 levels and ignore folders inside
	// packages, matching the original loading-sheet behavior.
	if ( [_directoryStack count] <= 4 )
	{
		FSItem* parentItem = [item parent];
		while ( parentItem != nil && ![parentItem isPackage] )
			parentItem = [parentItem parent];

		if ( parentItem == nil )
		{
			NSString *path = [[item displayPath] copy];
			[_workerCurrentPath release];
			_workerCurrentPath = path; // retained via copy above
		}
	}

	[self maybeRefreshScanCheckpoint];
	return !atomic_load(&_cancelRequested);
}

// Time-gate around -scanRefreshCheckpointFromWorker. Called from the
// per-folder enter callback AND the per-64-files continuation poll, so
// we get refreshes whether the scan is dominated by huge flat folders
// or by deep directory trees.
- (void) maybeRefreshScanCheckpoint
{
	uint64_t now = getTime();
	if ( _workerLastRefreshTime != 0
		 && subtractTime(now, _workerLastRefreshTime) < 0.25 )
		return;
	_workerLastRefreshTime = now;
	[self scanRefreshCheckpointFromWorker];
}

- (BOOL) fsItemExittingFolder: (FSItem*) item
{
	if ( !_scanInProgress )
		return YES; //YES == continue loading

    NSAssert( [_directoryStack lastObject] == item, @"last stack object: %@, item: %@", [[_directoryStack lastObject] fileURL], [item fileURL] );
	[_directoryStack removeLastObject];

	return YES;
}

// Periodic checkpoint inside large folders (no stack accounting). Called
// every ~64 files by the walker so cancel is responsive within ~milliseconds.
// Also drives the ~4 Hz UI refresh barrier so a single huge flat folder
// (node_modules, mailbox stores) still updates the live UI.
- (BOOL) fsItemShouldContinueLoading
{
	[self maybeRefreshScanCheckpoint];
	return !atomic_load(&_cancelRequested);
}

- (BOOL) fsItemShouldIgnoreCreatorCode: (FSItem*) item
{
	return [self ignoreCreatorCode];
}

- (BOOL) fsItemShouldLookIntoPackages: (FSItem*) item
{
	return [self showPackageContents];
}

- (BOOL) fsItemShouldUsePhysicalFileSize: (FSItem*) item
{
	return [self showPhysicalFileSize];
}

#pragma mark --------KVO-----------------

- (void)observeValueForKeyPath:(NSString*)keyPath
					  ofObject:(id)object
						change:(NSDictionary*)change
					   context:(void*)context
{
	LOG( @"FileSystemDoc.observeValueForKeyPath: keyPath: %@, change dict:%@", keyPath, change );
	
	//this global preference option is cached in an instance variable for performance reasons
	if ( context == ShareKindColors )
	{
		//if "share colors" was enabled previously, reset the shared colors so we get "fresh" colors the next time it is turned on again
		[_kindColors reset];
		[_kindColors release];
		_kindColors = nil;

		[self reserveColorsForLargestKinds];
	}
	else if ( context == ShowFreeSpace )
	{
		BOOL newValue = [[NSUserDefaults standardUserDefaults] boolForKey: ShowFreeSpace];
		if ( newValue != [self showFreeSpace] )
			[self setShowFreeSpace: newValue];
	}
	else if ( context == ShowOtherSpace )
	{
		BOOL newValue = [[NSUserDefaults standardUserDefaults] boolForKey: ShowOtherSpace];
		if ( newValue != [self showOtherSpace] )
			[self setShowOtherSpace: newValue];
	}
}

@end

//================ implementation FileSystemDoc(Private) ======================================================

@implementation FileSystemDoc(Private)

- (NSMutableDictionary*) viewOptions
{
	return _viewOptions;
}

- (void) postViewOptionChangedNotificationForOption: (NSString*) optionName
{
	NSDictionary *userInfo = [NSDictionary dictionaryWithObject: optionName forKey: ChangedViewOption];
	
	[[NSNotificationCenter defaultCenter] postNotificationName: ViewOptionChangedNotification
														object: self
													  userInfo: userInfo];
}

- (void) postNotificationName: (NSString*) name oldItem: (FSItem*) old newItem: (FSItem*) new
{
	NSDictionary *info = [NSDictionary dictionaryWithObjectsAndKeys: old, OldItem, new, NewItem, nil];
	
	[[NSNotificationCenter defaultCenter] postNotificationName: name object: self userInfo: info];
}

- (void) recalculateTotalSize
{
	[[self rootItem] recalculateSize: [self showPhysicalFileSize] updateParent: NO];
}

- (void) addItemToFileKindStatistic: (FSItem*) item includingChilds: (BOOL) includingChilds
{
    //if we are called with nil as item, we rebuild the statistic
    if ( item == nil )
    {
        [_fileKindStatistics release];
		_fileKindStatistics = [[NSMutableDictionary alloc] init];
        
        item = [self zoomedItem];
    }
	
    if ( ![self itemIsNode: item] )
    {
        //item is a file (or regarded as such if item is a package and "show package contents" is turned off),
        //so add it's informations to the appropriate statistic object
        if ( [item kindName] != nil )
        {
            FileKindStatistic* kindStatistic = [self kindStatisticForItem: item];
            if ( kindStatistic == nil )
            {
                //we don't have a statistic object for the item's kind yet, so create one
                kindStatistic = [[FileKindStatistic alloc] initWithItem: item];
                [_fileKindStatistics setObject: kindStatistic forKey: [item kindName]];
                [kindStatistic release];
            }
            else
                [kindStatistic addItem: item];
        }
	}
	else if ( includingChilds )
	{
		//if the item is a folder, recurse through it's childs
        unsigned i = [item childCount];
        while ( i-- )
            [self addItemToFileKindStatistic: [item childAtIndex: i] includingChilds: YES];
    }
}

- (void) removeItemFromFileKindStatistic: (FSItem*) item includingChilds: (BOOL) includingChilds
{
	NSParameterAssert( item != nil );
	
    if ( ![self itemIsNode: item] )
    {
        //item is a file (or regarded as such if item is a package and "show package contents" is turned off),
		//so remove it's information from the appropriate statistic object
        FileKindStatistic* kindStatistic = [self kindStatisticForItem: item];
        if ( kindStatistic != nil )
            [kindStatistic removeItem: item];
	}
	else if ( includingChilds )
	{
		//if the item is a folder, recurse through it's childs
        unsigned i = [item childCount];
        while ( i-- )
            [self removeItemFromFileKindStatistic: [item childAtIndex: i] includingChilds: YES];		
    }
}

- (void) recalculateFileKindStatisticSizes
{
	[self willChangeValueForKey: @"kindStatistics"];
	
	NSEnumerator *statisticEnum = [[self kindStatistics] objectEnumerator];
	FileKindStatistic *statistic = nil;
	while ( (statistic = [statisticEnum nextObject]) != nil )
		[statistic recalculateSize];
	
	[self didChangeValueForKey: @"kindStatistics"];
}

- (void) removePackagesFromFileKindStatistic: (FSItem*) item
{
	BOOL bDoKVO = NO;
	if ( item == nil )
	{
		bDoKVO = YES;
		[self willChangeValueForKey: @"kindStatistics"];
		item = [self zoomedItem];
	}
	
	if ( [self itemIsNode: item] )
	{
		//if the item is regarded as a folder, recurse through it's childs
		unsigned i = [item childCount];
		while ( i-- )
			[self removePackagesFromFileKindStatistic: [item childAtIndex: i]];
	}
	else
	{
		if ( [item isPackage] )
			[self removeItemFromFileKindStatistic: item includingChilds: YES];
	}
	
	if ( bDoKVO )
	{
		[self removeEmptyKindStatistics];
		[self didChangeValueForKey: @"kindStatistics"];
	}
}

// !! does not work correctly in all cases (see comment in "setShowPackageContents")
- (void) addPackagesToFileKindStatistic: (FSItem*) item
{
	BOOL bDoKVO = NO;
	if ( item == nil )
	{
		bDoKVO = YES;
		[self willChangeValueForKey: @"kindStatistics"];
		item = [self zoomedItem];
	}
	
	if ( [self itemIsNode: item] )
	{
		//if the item is regarded as a folder, recurse through it's childs
		unsigned i = [item childCount];
		while ( i-- )
			[self addPackagesToFileKindStatistic: [item childAtIndex: i]];
	}
	else
	{
		if ( [item isPackage] )
			[self addItemToFileKindStatistic: item includingChilds: YES];
	}
	
	if ( bDoKVO )
		[self didChangeValueForKey: @"kindStatistics"];
}

- (void) removeEmptyKindStatistics
{
	NSEnumerator *keyEnumerator = [[[self kindStatistics] allKeys] objectEnumerator];
	NSString *kindName;
	while ( (kindName = [keyEnumerator nextObject]) != nil )
	{
		FileKindStatistic *stat = [_fileKindStatistics objectForKey: kindName];
		if ( [stat fileCount] == 0 )
			[_fileKindStatistics removeObjectForKey: kindName];
	}
}

- (void) reserveColorsForLargestKinds
{
	//get a mutable copy of the keys
    NSMutableArray *kinds = [[[self kindStatistics] allValues] mutableCopy];

    //order Statistics descendantly by size
    [kinds sortUsingSelector: @selector(compareSizeDescendingly:)];

    NSEnumerator *kindNameEnum = [kinds objectEnumerator];
    FileKindStatistic *kindStat;
    while ( ( kindStat = [kindNameEnum nextObject] ) != nil )
    {
        [[self fileTypeColors] colorForKind: [kindStat kindName]];
    }
	
	[kinds release]; //mutableCopy returns a retained object (not autoreleased)
}

- (BOOL)checkForProtectedFolders:(NSString * _Nonnull)folder
{
    NSFileManager *fileMgr = [NSFileManager defaultManager];
    NSArray<NSURL*> *protectedFolders = [fileMgr privacyProtectedFoldersInURL:[NSURL fileURLWithPath:folder]];
    if ( [protectedFolders count] == 0 )
        return YES;

    // If we already have access to every protected folder in the scan path,
    // there is nothing the user needs to do — skip the warning entirely.
    if ( [fileMgr hasAccessToProtectedFolders: protectedFolders] )
        return YES;

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    BOOL shouldContinue = YES;

    if ( ![defaults boolForVersionDependantKey: DontShowPrivacyWarningMessage] )
    {
        NSAlert *alert = [[[NSAlert alloc] init] autorelease];

        alert.alertStyle = NSAlertStyleInformational;

        alert.messageText = NSLocalizedString(@"Some folders in this scan are protected by macOS privacy protection.\n\nDisk Inventory Z does not read any file contents — only sizes and metadata.", @"");
        alert.informativeText = NSLocalizedString(@"Recommended: click “Open System Settings” and enable Disk Inventory Z under Privacy & Security → Full Disk Access. The scan will not start; restart the app after granting permission and then run the scan again for full results.\n\nIf you click “Continue Anyway,” the scan will run now but protected folders may be reported as empty or partial.", @"");

        // Primary button: deep-link to the Full Disk Access pane.
        [alert addButtonWithTitle: NSLocalizedString(@"Open System Settings", @"")];
        [alert addButtonWithTitle: NSLocalizedString(@"Continue Anyway", @"")];

        alert.showsSuppressionButton = YES;
        alert.suppressionButton.title = NSLocalizedString(@"Do not show this information again.", @"");

        NSModalResponse response = [alert runModal];

        if (alert.suppressionButton.state == NSControlStateValueOn)
        {
            // Suppress this alert for the current version
            [defaults setBool: YES forVersionDependantKey: DontShowPrivacyWarningMessage];
        }

        if ( response == NSAlertFirstButtonReturn )
        {
            // User chose to fix permissions first. Open the System
            // Settings pane and abort the scan so they can grant access
            // (and, for Full Disk Access, relaunch) before re-triggering.
            NSURL *fdaPane = [NSURL URLWithString:
                @"x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"];
            [[NSWorkspace sharedWorkspace] openURL: fdaPane];
            shouldContinue = NO;
        }

        // let the alert disappear before any further work
        [[NSRunLoop currentRunLoop] runUntilDate: [NSDate date]];
    }

    if ( !shouldContinue )
        return NO;

    // User chose Continue Anyway (or suppressed the alert). Fire per-folder
    // consent dialogs (Music, Photos, Apps, etc.) so they get prompted and
    // each category is registered in System Settings → Privacy & Security
    // before the actual scan starts.
    [fileMgr triggerConsentDialogForPrivacyProtectedFolders:protectedFolders];
    return YES;
}

//@@test
- (void)canCloseDocumentWithDelegate:(id)delegate
                 shouldCloseSelector:(nullable SEL)shouldCloseSelector
                         contextInfo:(nullable void *)contextInfo
{
    @try
    {
        [super canCloseDocumentWithDelegate:delegate
                        shouldCloseSelector:shouldCloseSelector
                                contextInfo:contextInfo];
    }
    @catch (NSException *exception)
    {
        NSString *msg = [exception reason];
        
        NSLog(@"%@ exception catched: %@", [exception className], msg);
        
        
        NSError *error = NULL;
        NSRegularExpression *regex = [NSRegularExpression
                                      regularExpressionWithPattern:@"0x([a-f]*\\d*)*(\\w|$)"
                                      options:NSRegularExpressionCaseInsensitive
                                      error:&error];
        
        [regex enumerateMatchesInString:msg
                                options:NSMatchingReportCompletion
                                  range:NSMakeRange(0, [msg length])
                             usingBlock:^(NSTextCheckingResult *match, NSMatchingFlags flags, BOOL *stop)
         {
             for (NSUInteger i = 0; i < [match numberOfRanges]; i++)
             {
                 NSObject *obj = nil;
                 NSString *objAddress = [msg substringWithRange:[match rangeAtIndex:i]];
                 
                 NSScanner* scanner = [NSScanner scannerWithString:objAddress];
                 if ( [scanner scanHexLongLong:(unsigned long long*)&objAddress] )
                 {
                     NSLog(@"%@: %@", objAddress, [obj className]);
                 }
                 else
                 {
                     NSLog(@"'%@' could not be parsed as hex string", objAddress);
                 }
             }
         }];
        
        @throw exception;
    }
}


@end

