//
//  MTMainWindowController.h
//  cTiVo
//
//  Created by Scott Buchanan on 12/13/12.
//  Copyright (c) 2012 Scott Buchanan. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "MTTiVoManager.h"
#import "MTDownloadList.h"
#import "MTProgramList.h"
#import "MTSubscriptionTableView.h"
#import "MTPopUpButton.h"


@interface MTMainWindowController : NSWindowController {
	IBOutlet NSPopUpButton *tiVoListPopUp, *formatListPopUp;
    IBOutlet NSButton *addToQueueButton, *removeFromQueueButton, *addToiTunesButton, *simultaneousEncodeButton, *subscribeButton;
	IBOutlet NSTextField *loadingProgramListLabel, *downloadDirectory;
	IBOutlet NSProgressIndicator *loadingProgramListIndicator;
	IBOutlet MTDownloadList *downloadQueueTable;
	IBOutlet MTProgramList  *tiVoShowTable;
	IBOutlet MTSubscriptionTableView  *subscriptionTable;
    IBOutlet NSView *view;
	NSMutableArray *loadingTiVos;
}

@property (nonatomic, assign) MTDownloadList *downloadQueueTable;
@property (nonatomic, assign) MTProgramList *tiVoShowTable;
@property (nonatomic, assign) MTSubscriptionTableView *subscriptionTable;
@property (nonatomic, retain) NSString *selectedTiVo;

-(IBAction)selectFormat:(id)sender;
-(IBAction)subscribe:(id) sender;
-(IBAction)downloadSelectedShows:(id)sender;
-(IBAction)removeFromDownloadQueue:(id)sender;
-(IBAction)getDownloadDirectory:(id)sender;
-(IBAction)changeSimultaneous:(id)sender;
-(IBAction)changeiTunes:(id)sender;

@end
