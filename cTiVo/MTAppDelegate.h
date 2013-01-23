//
//  MTAppDelegate.h
//  myTivo
//
//  Created by Scott Buchanan on 12/6/12.
//  Copyright (c) 2012 Scott Buchanan. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "MTTiVoManager.h"
#import "MTProgramTableView.h"
#import "MTDownloadTableView.h"
#import "MTMainWindowController.h"
#import "MTSubscriptionTableView.h"
#import "MTFormatEditorController.h"

@interface MTAppDelegate : NSObject <NSApplicationDelegate, NSTableViewDataSource, NSTableViewDelegate> {
	MTTiVoManager *tiVoGlobalManager;
	MTMainWindowController *mainWindowController;
	IBOutlet NSMenuItem *refreshTiVoMenuItem, *iTunesMenuItem, *simulEncodeItem;
    IBOutlet NSView *formatSelectionTable;
    IBOutlet NSTableView *exportTableView;
	NSMutableArray *mediaKeyQueue;
	BOOL gettingMediaKey;
}

@property (assign) IBOutlet NSWindow *window;
@property (nonatomic, retain) 	MTFormatEditorController *formatEditorController;
@property (nonatomic, readonly) NSNumber *numberOfUserFormats;


-(IBAction)editFormats:(id)sender;

@end
