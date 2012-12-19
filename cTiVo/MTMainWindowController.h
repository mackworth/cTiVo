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
    IBOutlet NSButton *addToQueueButton, *removeFromQueueButton;
	IBOutlet NSTextField  *mediaKeyLabel, *loadingProgramListLabel, *downloadDirectory;
	IBOutlet NSProgressIndicator *loadingProgramListIndicator;
	IBOutlet MTDownloadList *downloadQueueTable;
	IBOutlet MTProgramList  *tiVoShowTable;
    
	
}

@property (nonatomic, unsafe_unretained) MTNetworkTivos *myTiVos;
@property (nonatomic, unsafe_unretained) NSMutableDictionary *mediaKeys;
@property (nonatomic, unsafe_unretained) NSNetService *selectedTiVo;
@property (nonatomic, unsafe_unretained) NSMutableArray *tiVoList, *formatList;
@property (nonatomic, unsafe_unretained) NSDictionary *selectedFormat;

@end
