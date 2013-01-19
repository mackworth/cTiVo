//
//  MTMainWindowController.h
//  cTiVo
//
//  Created by Scott Buchanan on 12/13/12.
//  Copyright (c) 2012 Scott Buchanan. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "MTTiVoManager.h"
#import "MTFormatEditorController.h"

@class MTDownloadTableView;
@class MTProgramTableView;
@class MTSubscriptionTableView;
@class MTFormatPopUpButton;

@interface MTMainWindowController : NSWindowController {
	IBOutlet NSPopUpButton *tiVoListPopUp;
	IBOutlet MTFormatPopUpButton *formatListPopUp;
    IBOutlet NSButton *addToQueueButton, *removeFromQueueButton, *addToiTunesButton, *simultaneousEncodeButton, *subscribeButton, *subDirectoriesButton;
	IBOutlet NSTextField *loadingProgramListLabel, *downloadDirectory, *tiVoListPopUpLabel;
	IBOutlet NSProgressIndicator *loadingProgramListIndicator;
	IBOutlet MTDownloadTableView *downloadQueueTable;
	IBOutlet MTProgramTableView  *tiVoShowTable;
	IBOutlet MTSubscriptionTableView  *subscriptionTable;
    IBOutlet NSView *view;
	NSMutableArray *loadingTiVos;
}

@property (nonatomic, assign) MTDownloadTableView *downloadQueueTable;
@property (nonatomic, assign) MTProgramTableView *tiVoShowTable;
@property (nonatomic, assign) MTSubscriptionTableView *subscriptionTable;
@property (nonatomic, retain) NSString *selectedTiVo;
@property (nonatomic, retain) IBOutlet NSButton *showProtectedShows;

-(IBAction)selectFormat:(id)sender;
-(IBAction)subscribe:(id) sender;
-(IBAction)downloadSelectedShows:(id)sender;
-(IBAction)removeFromDownloadQueue:(id)sender;
-(IBAction)getDownloadDirectory:(id)sender;
-(IBAction)changeSimultaneous:(id)sender;
-(IBAction)changeiTunes:(id)sender;


@end
