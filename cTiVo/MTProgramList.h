//
//  MTProgramList.h
//  myTivo
//
//  Created by Scott Buchanan on 12/7/12.
//  Copyright (c) 2012 Scott Buchanan. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "MTNetworkTivos.h"

@interface MTProgramList : NSTableView <NSTableViewDataSource, NSTableViewDelegate>{
    IBOutlet NSWindowController *myController;
}

@property (nonatomic, assign) NSMutableArray *tiVoShows;

@end
