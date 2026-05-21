//
//  LoadingPanelController.m
//  Disk Inventory Z
//
//  Created by Tjark Derlien on 03.12.04.
//
//  Copyright (C) 2004 Tjark Derlien.
//  
//  This program is free software; you can redistribute it and/or
//  modify it under the terms of the GNU General Public License
//  as published by the Free Software Foundation; either version 3
//  of the License, or any later version.

//

#import "LoadingPanelController.h"
#import "FSItem.h"
#import "Timing.h"
#import <objc/runtime.h>

// Trivial NSButton subclass that returns YES from -acceptsFirstMouse:. Used
// for the Cancel button so the very first click fires the action even when
// the loading panel isn't the key window.
@interface DIXFirstMouseButton : NSButton @end
@implementation DIXFirstMouseButton
- (BOOL) acceptsFirstMouse: (NSEvent*) event { return YES; }
@end

@interface LoadingPanelController (StatusLine)
- (void) installStatusFieldInPanel;
- (void) startStatusTimer;
- (void) stopStatusTimer;
- (void) updateStatus: (NSTimer*) timer;
@end

// Holds the nib's top-level objects. -[NSBundle loadNibNamed:owner:] (deprecated)
// gave its top-level objects an extra retain; the modern instance method hands
// ownership to the caller, so we retain them here to keep the panel alive.
@interface LoadingPanelController ()
@property (nonatomic, retain) NSArray *nibTopLevelObjects;
@end

@implementation LoadingPanelController

- (id) init
{
	self = [super init];
	
    //load Nib with progress panel
	NSArray *topLevelObjects = nil;
	if ( ![[NSBundle mainBundle] loadNibNamed: @"LoadingPanel" owner: self topLevelObjects: &topLevelObjects] )
		NSAssert( NO, @"couldn't load LoadingPanel.nib" );
	self.nibTopLevelObjects = topLevelObjects;

	[_loadingProgressIndicator setUsesThreadedAnimation: NO];
    [_loadingProgressIndicator startAnimation: self];

	[self installStatusFieldInPanel];
	_scanStartTime = getTime();
	[self startStatusTimer];

	// Show the panel as a non-modal floating window. We used to call
	// -beginModalSessionForWindow: which kept the panel app-modal --
	// that blocked NSApp.terminate: (Cmd-Q) and -orderFrontStandardAboutPanel:
	// from reaching their targets, so the user had no way to quit or to
	// open the About panel while a long scan was running. With a normal
	// floating window, the scan still blocks the main thread but the
	// periodic -runEventLoop call pumps the runloop and standard App-menu
	// commands work as expected. The Cancel button still works because
	// the scan polls -cancelPressed inside the same runloop pump.
	[_loadingPanel setHidesOnDeactivate: NO];
	[_loadingPanel setLevel: NSFloatingWindowLevel];
	[_loadingPanel makeKeyAndOrderFront: nil];
	[_loadingPanel display];

	// Make the Cancel button respond to the FIRST mouse click even when
	// the panel is not the key window. Without this, stock NSPanel
	// behaviour eats the first click for "make this panel key" and the
	// user has to click twice -- which feels broken because the panel
	// usually IS key already (this is just defensive). We do this by
	// swapping in a subclass that overrides -acceptsFirstMouse: to YES.
	object_setClass( _loadingCancelButton, [DIXFirstMouseButton class] );

	_loadingPanelModalSession = 0;
	_lastEventLoopRun = 0;

	_cancelPressed = NO;

	return self;
}

- (id) initAsSheetForWindow: (NSWindow*) window
{
	self = [super init];
	
    //load Nib with progress panel
	NSArray *topLevelObjects = nil;
	if ( ![[NSBundle mainBundle] loadNibNamed: @"LoadingPanel" owner: self topLevelObjects: &topLevelObjects] )
		NSAssert( NO, @"couldn't load LoadingPanel.nib" );
	self.nibTopLevelObjects = topLevelObjects;

	[NSApp beginSheet: _loadingPanel
	   modalForWindow: window
		modalDelegate: self
	   didEndSelector: nil
		  contextInfo: NULL];
	
	[_loadingPanel setWorksWhenModal: YES];
	
	[_loadingProgressIndicator setUsesThreadedAnimation: NO];
    [_loadingProgressIndicator startAnimation: self];

	[self installStatusFieldInPanel];
	_scanStartTime = getTime();
	[self startStatusTimer];

	//we don't have modal session if we show the panel as a sheet
	_loadingPanelModalSession = 0;
	
	_lastEventLoopRun = 0;
	
	_cancelPressed = NO;
	
	return self;
}

- (void) dealloc
{
	if ( _loadingPanel != nil )
		[self close];
	[self stopStatusTimer];
	// _statusField is owned by the panel's content view; no separate release.
	[_nibTopLevelObjects release];

	[super dealloc];
}

- (void) close
{
	[self stopStatusTimer];

	if ( _loadingPanel == nil )
		return;

	if ( [_loadingPanel isSheet] )
	{
		[NSApp endSheet: _loadingPanel];
		[_loadingPanel close]; //will be released (panel has style "release when close")

		_loadingPanel = nil;
		_loadingProgressIndicator = nil;
		_loadingTextField = nil;
		_loadingCancelButton = nil;
	}
	else
	{
		// The initial-scan panel is now a non-modal floating window (see
		// -init), so the modal session may be zero. Older callers using
		// the modal-session path are still supported.
		if ( _loadingPanelModalSession != 0 )
		{
			[[NSApplication sharedApplication] endModalSession: _loadingPanelModalSession];
			_loadingPanelModalSession = 0;
		}

		[self closeNoModalEnd];
	}
}

- (void) closeNoModalEnd
{
	[self stopStatusTimer];

	//this only works if we startet a modal session for a panel (no sheet)
	OBPRECONDITION( ![_loadingPanel isSheet] );
	
	//the sender asked us not to end the modal session (maybe because sender has run into an exception)
	_loadingPanelModalSession = 0;
	
	[_loadingPanel close]; //will be released (panel has style "release when close")
	
	_loadingPanel = nil;
    _loadingProgressIndicator = nil;
	_loadingTextField = nil;
	_loadingCancelButton = nil;
}

- (void) enableCancelButton: (BOOL) enable
{
	[_loadingCancelButton setEnabled: enable];
}

- (BOOL) cancelPressed
{
	return _cancelPressed;
}

- (void) startAnimation;
{
	[_loadingProgressIndicator startAnimation: nil];
}

- (void) stopAnimation;
{
	[_loadingProgressIndicator stopAnimation: nil];
}

- (void) setMessageText: (NSString*) msg
{
	[msg retain];
	[_message release];
	_message = msg;
}

- (void) runEventLoop
{
	// Pump the runloop at ~20 Hz during a scan. The original 0.2s (5 Hz)
	// throttle dates from 2004-era hardware where pumping was expensive.
	// On modern macs the per-pump cost is microseconds, and 5 Hz is just
	// past the threshold where macOS draws the beach-ball, so users
	// couldn't click Cancel or use the App menu (Quit / About) reliably
	// during long scans.
	uint64_t currentTime = getTime();
	BOOL runEventLoop = _lastEventLoopRun == 0 || subtractTime( currentTime, _lastEventLoopRun ) > 0.05;

	if ( _message != nil )
	{
		[_loadingTextField setStringValue: _message];
		
		//set message to nil so it won't be set a again in the NSTextField
		[self setMessageText: nil];
			
		//if we don't run the event loop, just update the text field
		if ( !runEventLoop )
			[_loadingTextField displayIfNeeded];
	}
	
	if ( runEventLoop )
	{
		_lastEventLoopRun = currentTime;

		//give progress dialog some processor cycles
		if ( _loadingPanelModalSession != 0 )
		{
			if ( [[NSApplication sharedApplication] runModalSession: _loadingPanelModalSession]
																			!= NSRunContinuesResponse )
			{
				NSAssert( NO, @"run loop stopped by unknown party" );
			}
		}
		else
		{
			// Drain every event currently queued, dispatching each one via
			// -sendEvent: so mouse-down/-up pairs on the Cancel button both
			// land in the same yield (otherwise the action wouldn't fire
			// until two pumps later, and on a non-key panel mouse-down can
			// be consumed by activation while mouse-up sits in the queue).
			NSEvent *ev;
			while ( (ev = [NSApp nextEventMatchingMask: NSEventMaskAny
											untilDate: [NSDate distantPast]
											   inMode: NSDefaultRunLoopMode
											  dequeue: YES]) != nil )
			{
				[NSApp sendEvent: ev];
			}
			// Also let timers / blocks scheduled with the runloop fire
			// (this is what advances the elapsed-time counter, for one).
			CFRunLoopRunInMode( kCFRunLoopDefaultMode, 0, false );
		}
	}
}

- (IBAction) cancel:(id)sender
{
	_cancelPressed = YES;

	[_loadingCancelButton setEnabled: NO];
}

@end

#pragma mark ----------------- elapsed / scan-rate status line -----------------

@implementation LoadingPanelController (StatusLine)

// Add a small text field below the existing message field. We do this in code
// so the four localized LoadingPanel.nib files don't have to be edited. To
// avoid overlap the panel is grown in height by exactly the room we need.
- (void) installStatusFieldInPanel
{
    if ( _statusField != nil || _loadingPanel == nil || _loadingTextField == nil )
        return;

    const CGFloat lineHeight = 16;
    const CGFloat gap        = 2;
    const CGFloat extra      = lineHeight + gap + 4;  // a little breathing room

    // Grow the panel upward so existing controls don't have to move.
    NSRect frame = [_loadingPanel frame];
    frame.size.height += extra;
    [_loadingPanel setFrame: frame display: NO];

    // Shift every existing subview up by 'extra' so the bottom of the
    // content view is freed up for the new status line.
    NSView *content = [_loadingPanel contentView];
    for ( NSView *sub in [content subviews] )
    {
        NSRect r = [sub frame];
        r.origin.y += extra;
        [sub setFrame: r];
    }

    NSRect msgFrame = [_loadingTextField frame];
    NSRect statusFrame = NSMakeRect( msgFrame.origin.x,
                                     msgFrame.origin.y - lineHeight - gap,
                                     msgFrame.size.width,
                                     lineHeight );

    NSTextField *f = [[NSTextField alloc] initWithFrame: statusFrame];
    [f setEditable: NO];
    [f setSelectable: NO];
    [f setBezeled: NO];
    [f setBordered: NO];
    [f setDrawsBackground: NO];
    [f setFont: [NSFont monospacedDigitSystemFontOfSize: [NSFont smallSystemFontSize]
                                                weight: NSFontWeightRegular]];
    [f setTextColor: [NSColor secondaryLabelColor]];
    [f setStringValue: @"Elapsed: 00:00"];
    [f setAutoresizingMask: [_loadingTextField autoresizingMask]];
    [content addSubview: f];
    _statusField = f;  // retain via subview ownership; +1 from alloc is balanced in dealloc
}

- (void) startStatusTimer
{
    [self stopStatusTimer];
    // The runloop already retains the timer; we only need a weak pointer to
    // call -invalidate from -stopStatusTimer. NOT retaining here makes the
    // closeable cycle explicit: when the runloop drops the timer (after
    // -invalidate), the timer's retain on self goes away and the controller
    // is reclaimed. With our own retain on the timer we'd build a cycle:
    // self -> _statusTimer -> self.
    _statusTimer = [NSTimer scheduledTimerWithTimeInterval: 0.5
                                                    target: self
                                                  selector: @selector(updateStatus:)
                                                  userInfo: nil
                                                   repeats: YES];
    // Schedule on the modal panel run-loop mode too so the timer fires while
    // the modal session is running (NSDefaultRunLoopMode alone won't fire
    // during -runModalSession:).
    [[NSRunLoop currentRunLoop] addTimer: _statusTimer forMode: NSModalPanelRunLoopMode];
    [[NSRunLoop currentRunLoop] addTimer: _statusTimer forMode: NSEventTrackingRunLoopMode];
}

- (void) stopStatusTimer
{
    if ( _statusTimer != nil )
    {
        [_statusTimer invalidate];   // runloop releases its retain; timer releases self
        _statusTimer = nil;          // unsafe-unretained reference: just drop it
    }
}

- (void) updateStatus: (NSTimer*) timer
{
    if ( _statusField == nil || _scanStartTime == 0 )
        return;

    double secs = subtractTime( getTime(), _scanStartTime );
    if ( secs < 0 ) secs = 0;

    unsigned long total = secs;
    unsigned mm = (unsigned) (total / 60);
    unsigned ss = (unsigned) (total % 60);

    // g_fileCount / g_folderCount are incremented from FSItem's scan loop.
    unsigned long files = (unsigned long) g_fileCount + (unsigned long) g_folderCount;
    double rate = (secs > 0.1) ? (files / secs) : 0;

    NSNumberFormatter *fmt = [[[NSNumberFormatter alloc] init] autorelease];
    [fmt setNumberStyle: NSNumberFormatterDecimalStyle];
    [fmt setGroupingSeparator: @","];
    [fmt setUsesGroupingSeparator: YES];
    [fmt setMaximumFractionDigits: 0];

    NSString *filesStr = [fmt stringFromNumber: @(files)];
    NSString *rateStr  = [fmt stringFromNumber: @((long long) rate)];

    NSString *line;
    if ( files == 0 )
        line = [NSString stringWithFormat: @"Elapsed: %02u:%02u", mm, ss];
    else
        line = [NSString stringWithFormat: @"Elapsed: %02u:%02u  ·  %@ files scanned (%@/sec)",
                mm, ss, filesStr, rateStr];

    [_statusField setStringValue: line];
}

@end

