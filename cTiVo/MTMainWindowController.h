//
//  MTMainWindowController.h
//  cTiVo
//
//  Created by Scott Buchanan on 12/13/12.
//  Copyright (c) 2012 Scott Buchanan. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "MTNetworkTivos.h"
#import "MTDownloadList.h"
#import "MTProgramList.h"
#import "MTSubscriptionList.h"


@interface MTMainWindowController : NSWindowController {
	IBOutlet NSPopUpButton *tiVoListPopUp, *formatListPopUp;
    IBOutlet NSButton *addToQueueButton, *removeFromQueueButton, *addToiTunesButton, *simultaneousEncodeButton, *subscribeButton;
	IBOutlet NSTextField  *mediaKeyLabel, *loadingProgramListLabel, *downloadDirectory;
	IBOutlet NSProgressIndicator *loadingProgramListIndicator;
	IBOutlet MTDownloadList *downloadQueueTable;
	IBOutlet MTProgramList  *tiVoShowTable;
	IBOutlet MTSubscriptionList  *subscriptionTable;
}

-(IBAction)selectTivo:(id)sender;
-(IBAction)selectFormat:(id)sender;
-(IBAction)subscribe:(id) sender;
-(IBAction)downloadSelectedShows:(id)sender;
-(IBAction)removeFromDownloadQueue:(id)sender;
-(IBAction)getDownloadDirectory:(id)sender;
-(IBAction)changeSimultaneous:(id)sender;
-(IBAction)changeiTunes:(id)sender;

@property (nonatomic, assign) MTNetworkTivos *myTiVos;
@property (nonatomic, assign) NSMutableDictionary *mediaKeys;
@property (nonatomic, assign) NSNetService *selectedTiVo;
@property (nonatomic, assign) NSMutableArray *tiVoList, *formatList;
@property (nonatomic, assign) NSDictionary *selectedFormat;

@end
