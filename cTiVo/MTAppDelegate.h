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
#import "MTPreferencesWindowController.h"

@interface MTAppDelegate : NSObject <NSApplicationDelegate, NSTableViewDataSource, NSTableViewDelegate> {
	MTMainWindowController *mainWindowController;
	IBOutlet NSMenuItem *refreshTiVoMenuItem, *iTunesMenuItem, *simulEncodeItem, *skipCommercialsItem, *pauseMenuItem;
	IBOutlet NSMenu *optionsMenu;
    IBOutlet NSView *formatSelectionTable;
    IBOutlet NSTableView *exportTableView;
	NSMutableArray *mediaKeyQueue;
	BOOL gettingMediaKey;
	
}

@property (assign) IBOutlet NSWindow *window;
@property (nonatomic, retain) MTPreferencesWindowController *preferencesController;
@property (nonatomic, retain) MTPreferencesWindowController *advPreferencesController;
@property (nonatomic, readonly) NSNumber *numberOfUserFormats;
@property (nonatomic, retain) MTTiVoManager *tiVoGlobalManager;


-(IBAction)togglePause:(id)sender;
-(IBAction)editFormats:(id)sender;

@end
