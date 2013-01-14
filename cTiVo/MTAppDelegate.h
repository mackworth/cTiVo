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

@interface MTAppDelegate : NSObject <NSApplicationDelegate> {
	MTTiVoManager *tiVoGlobalManager;
	MTMainWindowController *mainWindowController;
	IBOutlet NSMenuItem *refreshTiVoMenuItem;
	NSMutableArray *mediaKeyQueue;
	BOOL gettingMediaKey;
}

@property (assign) IBOutlet NSWindow *window;
@property (nonatomic, retain) 	MTFormatEditorController *formatEditorController;


-(IBAction)editFormats:(id)sender;

@end
