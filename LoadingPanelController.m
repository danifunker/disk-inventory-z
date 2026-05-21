//
//  LoadingPanelController.m
//  Disk Inventory X
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

@interface LoadingPanelController (StatusLine)
- (void) installStatusFieldInPanel;
- (void) startStatusTimer;
- (void) stopStatusTimer;
- (void) updateStatus: (NSTimer*) timer;
@end

@implementation LoadingPanelController

- (id) init
{
	self = [super init];
	
    //load Nib with progress panel
	if ( ![NSBundle loadNibNamed: @"LoadingPanel" owner: self] )
		NSAssert( NO, @"couldn't load LoadingPanel.nib" );
	
	[_loadingProgressIndicator setUsesThreadedAnimation: NO];
    [_loadingProgressIndicator startAnimation: self];

	[self installStatusFieldInPanel];
	_scanStartTime = getTime();
	[self startStatusTimer];

	[_loadingPanel display];

	//start modal session for the progress window
	_loadingPanelModalSession = [[NSApplication sharedApplication] beginModalSessionForWindow: _loadingPanel];
	_lastEventLoopRun = 0;

	_cancelPressed = NO;

	return self;
}

- (id) initAsSheetForWindow: (NSWindow*) window
{
	self = [super init];
	
    //load Nib with progress panel
	if ( ![NSBundle loadNibNamed: @"LoadingPanel" owner: self] )
		NSAssert( NO, @"couldn't load LoadingPanel.nib" );
	
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

	[super dealloc];
}

- (void) close
{
	[self stopStatusTimer];

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
		OBPRECONDITION( _loadingPanelModalSession != 0 );
		[[NSApplication sharedApplication] endModalSession: _loadingPanelModalSession];
		_loadingPanelModalSession = 0;
		
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
	//we only let the UI update itself every 0.2 second, otherwise running
	//the event loop eats over half of the total scan time!
	uint64_t currentTime = getTime();
	BOOL runEventLoop = _lastEventLoopRun == 0 || subtractTime( currentTime, _lastEventLoopRun ) > 0.2;

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
			[[NSRunLoop currentRunLoop] runUntilDate: [NSDate date]];
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

