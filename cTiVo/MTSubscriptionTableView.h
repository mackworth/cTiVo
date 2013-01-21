//
//  MTSubscriptionTableView.h
//  myTivo
//
//  Created by Scott Buchanan on 12/7/12.
//  Copyright (c) 2012 Scott Buchanan. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "MTTiVoManager.h"
#import "MTDownloadCheckTableCell.h"
#import "MTPopUpTableCellView.h"
@class MTMainWindowController;

@interface MTSubscriptionTableView : NSTableView <NSTableViewDataSource, NSTableViewDelegate, NSDraggingDestination, NSDraggingSource> {
    IBOutlet MTMainWindowController *myController;

}

-(IBAction) unsubscribeSelectedItems:(id) sender;

@property (assign) IBOutlet NSButton *unsubscribeButton;
@property (nonatomic, retain) NSArray *sortedSubscriptions;

@end
