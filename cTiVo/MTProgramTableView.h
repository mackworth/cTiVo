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


@interface MTProgramTableView : NSOutlineView <NSOutlineViewDelegate, NSOutlineViewDataSource, NSDraggingSource, NSControlTextEditingDelegate>

@property (nonatomic, readonly) NSArray *selectedShows;

-(IBAction)selectTivo:(id)sender;
-(IBAction)findShows:(id)sender;
-(IBAction)changedSearchText:(id) sender;
@end
