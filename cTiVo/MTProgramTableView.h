//
//  MTProgramList.h
//  myTivo
//
//  Created by Scott Buchanan on 12/7/12.
//  Copyright (c) 2012 Scott Buchanan. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "MTTiVo.h"

@class MTTiVoManager, MTMainWindowController;


@interface MTProgramTableView : NSTableView <NSTableViewDataSource, NSTableViewDelegate, NSDraggingSource, MTTableViewProtocol>{
    IBOutlet MTMainWindowController *myController;
	MTTiVoManager *tiVoManager;
    NSTableColumn *tiVoColumnHolder;
}

@property (nonatomic, retain) NSArray *sortedShows;
@property (nonatomic, retain) NSString *selectedTiVo;

-(NSArray *)sortedShows;
-(IBAction)selectTivo:(id)sender;
-(BOOL)revealInFinder;
-(BOOL)playVideo;
-(BOOL)selectionContainsCompletedShows;

@end
