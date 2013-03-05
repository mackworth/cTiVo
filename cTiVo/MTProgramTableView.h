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


@interface MTProgramTableView : NSTableView <NSTableViewDataSource, NSTableViewDelegate, NSDraggingSource, MTTableViewProtocol, NSControlTextEditingDelegate>{
    IBOutlet MTMainWindowController *myController;
	MTTiVoManager *tiVoManager;
    NSTableColumn *tiVoColumnHolder;
}

@property (nonatomic, retain) NSArray *sortedShows;
@property (nonatomic, retain) NSString *selectedTiVo;
@property (assign) IBOutlet NSTextField *findLabel;
@property (assign) IBOutlet NSTextField *findText; //filter for displaying found subset of programs

-(NSArray *)sortedShows;
-(IBAction)selectTivo:(id)sender;
-(IBAction)findShows:(id)sender;

@end
