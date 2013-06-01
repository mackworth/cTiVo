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
	IBOutlet NSButton *addToQueueButton, *subscribeButton;
	MTTiVoManager *tiVoManager;
    NSTableColumn *tiVoColumnHolder;
}

@property (nonatomic, strong) NSArray *sortedShows;
@property (nonatomic, strong) NSString *selectedTiVo;
@property (weak) IBOutlet NSTextField *findLabel;
@property (weak) IBOutlet NSSearchField *findText; //filter for displaying found subset of programs

-(NSArray *)sortedShows;
-(IBAction)selectTivo:(id)sender;
-(IBAction)findShows:(id)sender;
-(IBAction)changedSearchText:(id) sender;
@end
