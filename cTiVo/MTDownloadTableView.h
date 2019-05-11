//
//  MTDownloadList.h
//  myTivo
//
//  Created by Scott Buchanan on 12/8/12.
//  Copyright (c) 2012 Scott Buchanan. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "MTTiVoManager.h"
#import "MTMainWindowController.h"
#import "MTDownloadCheckTableCell.h"
#import "MTProgressindicator.h"

@interface MTDownloadTableView : NSTableView <NSTableViewDataSource, NSTableViewDelegate, NSDraggingDestination, NSDraggingSource> {
    IBOutlet MTMainWindowController *myController;
	IBOutlet NSButton *removeFromQueueButton;
}

@property (nonatomic, strong) NSArray <MTDownload *> * sortedDownloads;


-(BOOL)playVideo;
-(BOOL)selectionContainsCompletedShows;
-(NSArray <MTDownload *> *) actionItems;
-(void)columnChanged:(NSTableColumn *) column;

- (IBAction)clearHistory:(id)sender;
@end
