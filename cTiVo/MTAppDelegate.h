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
#import "MTiTivoImport.h"
#import "MTHelpViewController.h"

@interface MTAppDelegate : NSObject <NSApplicationDelegate, NSTableViewDataSource, NSTableViewDelegate, NSPopoverDelegate> {
	IBOutlet NSMenuItem *refreshTiVoMenuItem, *iTunesMenuItem, *markCommercialsItem, *skipCommercialsItem, *pauseMenuItem, *apmMenuItem;
	IBOutlet NSMenuItem *playVideoMenuItem, *showInFinderMenuItem;
	IBOutlet NSMenu *optionsMenu;
    IBOutlet NSView *formatSelectionTable;
    IBOutlet NSTableView *exportTableView;
//    IBOutlet NSArrayController *manualTiVoArrayController, *networkTiVoArrayController;
	NSMutableArray *mediaKeyQueue;
	BOOL gettingMediaKey;
	NSTimer * checkingDone;
	NSTimer * saveQueueTimer;
    
}

@property (nonatomic, strong) MTPreferencesWindowController *preferencesController;
@property (nonatomic, strong) MTPreferencesWindowController *advPreferencesController;
@property (nonatomic, strong) MTMainWindowController  *mainWindowController;
@property (weak, nonatomic, readonly) NSNumber *numberOfUserFormats;
@property (nonatomic, strong) MTTiVoManager *tiVoGlobalManager;
@property (nonatomic, strong) NSTimer * pseudoTimer;


-(IBAction)togglePause:(id)sender;
-(IBAction)editFormats:(id)sender;
-(IBAction)editManualTiVos:(id)sender;
-(IBAction)createManualSubscription:(id)sender;
- (IBAction)findShows:(id)sender;
- (IBAction)clearHistory:(id)sender;
-(IBAction)showLogs:(id)sender;

@end
