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

@interface MTSubscriptionTableView : NSTableView <NSTableViewDataSource, NSTableViewDelegate, NSDraggingDestination, NSDraggingSource, MTTableViewProtocol> {
    IBOutlet MTMainWindowController *myController;

}

-(IBAction) unsubscribeSelectedItems:(id) sender;

@property (weak) IBOutlet NSButton *unsubscribeButton;
@property (nonatomic, strong) NSArray *sortedSubscriptions;

@end
