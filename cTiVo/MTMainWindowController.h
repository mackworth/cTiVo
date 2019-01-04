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

@interface MTMainWindowController : NSWindowController <NSMenuDelegate, NSPopoverDelegate> 

@property (weak, readonly) MTDownloadTableView *downloadQueueTable;
@property (weak, readonly) MTProgramTableView *tiVoShowTable;
@property (weak, readonly) MTSubscriptionTableView *subscriptionTable;

-(void) playTrashSound;
-(void) showCancelQuitView:(BOOL) show;
-(NSArray <MTTiVoShow *> *) showsForDownloads:(NSArray <MTDownload *> *) downloads includingDone: (BOOL) includeDone;

@end
