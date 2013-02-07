//
//  MTTableView.h
//  cTiVo
//
//  Created by Hugh Mackworth on 2/6/13.
//  Copyright (c) 2013 Scott Buchanan. All rights reserved.
//
#import <Cocoa/Cocoa.h>

@class MTTiVoManager, MTMainWindowController;

@interface MTTableView : NSTableView <NSTableViewDataSource, NSTableViewDelegate, NSDraggingDestination, NSDraggingSource> {
	
    IBOutlet MTMainWindowController *myController;
    NSTableColumn *tiVoColumnHolder;
}

@property (nonatomic, retain) NSArray *sortedShows;
@property (nonatomic, retain) NSString *selectedTiVo;

-(NSArray *)sortedShows;
-(IBAction)selectTivo:(id)sender;
-(BOOL)selectionContainsCompletedShows;
-(void) setupNotifications;

@end
