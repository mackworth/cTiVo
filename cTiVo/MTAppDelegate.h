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
#import "MTAdvPreferencesViewController.h"

@interface MTAppDelegate : NSObject <NSApplicationDelegate, NSTableViewDataSource, NSTableViewDelegate> {
	MTMainWindowController *mainWindowController;
	IBOutlet NSMenuItem *refreshTiVoMenuItem, *iTunesMenuItem, *markCommecialsItem, *skipCommercialsItem, *pauseMenuItem, *apmMenuItem;
	IBOutlet NSMenuItem *playVideoMenuItem, *showInFinderMenuItem;
	IBOutlet NSMenu *optionsMenu;
    IBOutlet NSView *formatSelectionTable;
    IBOutlet NSTableView *exportTableView;
	NSMutableArray *mediaKeyQueue;
	BOOL gettingMediaKey;
	NSTimer * checkingDone;
	
}

@property (weak) IBOutlet NSWindow *window;
@property (nonatomic, strong) MTPreferencesWindowController *preferencesController;
@property (nonatomic, strong) MTPreferencesWindowController *advPreferencesController;
@property (weak, nonatomic, readonly) NSNumber *numberOfUserFormats;
@property (nonatomic, strong) MTTiVoManager *tiVoGlobalManager;


-(IBAction)togglePause:(id)sender;
-(IBAction)editFormats:(id)sender;
- (IBAction)findShows:(id)sender;
- (IBAction)clearHistory:(id)sender;

@end
