//
//  MTTaskChain.h
//  cTiVo
//
//  Created by Scott Buchanan on 4/10/13.
//  Copyright (c) 2013 cTiVo. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "MTTask.h"

@class MTDownload;

@interface MTTaskChain : NSObject {
    
    NSMutableDictionary *teeBranches;
	NSMutableArray *branchFileHandles;
	BOOL isConfigured;
    ssize_t totalDataRead;
}

@property (strong, nonatomic) NSArray *taskArray;   //An array of arrays of tasks to be chained in order.  Single branching is allow so that one tasks output can be piped to two tasks.
                                                    //If the chain continues after a branch it is assumed that the first task in the multiple branch is the source for the next array of tasks.

@property (strong, nonatomic) MTTaskChain *nextTaskChain;

@property (strong, nonatomic) id dataSource, dataSink;  //These should be either NSFileHandle or NSPipe

@property (weak, nonatomic) MTDownload *download;

@property BOOL isRunning, providesProgress;

-(BOOL)run;
-(BOOL)configure;
-(void)cancel;
-(void)trackProgress;

@end
