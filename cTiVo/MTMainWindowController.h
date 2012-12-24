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


@interface MTMainWindowController : NSWindowController {
	IBOutlet NSPopUpButton *tiVoListPopUp, *formatListPopUp;
    IBOutlet NSButton *addToQueueButton, *removeFromQueueButton, *addToiTunesButton, *simultaneousEncodeButton;
	IBOutlet NSTextField  *mediaKeyLabel, *loadingProgramListLabel, *downloadDirectory;
	IBOutlet NSProgressIndicator *loadingProgramListIndicator;
	IBOutlet MTDownloadList *downloadQueueTable;
	IBOutlet MTProgramList  *tiVoShowTable;

}

@property (nonatomic, assign) MTNetworkTivos *myTiVos;
@property (nonatomic, assign) NSMutableDictionary *mediaKeys;
@property (nonatomic, assign) NSNetService *selectedTiVo;
@property (nonatomic, assign) NSMutableArray *tiVoList, *formatList;
@property (nonatomic, assign) NSDictionary *selectedFormat;
@property (nonatomic, readonly) IBOutlet MTProgramList  *tiVoShowTable;

@end
