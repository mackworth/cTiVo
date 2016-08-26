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

//A TaskChain describes a set of file processing steps to be executed concurrently
//It has an array of array of MTTasks to be chained in order. We call each subarray of tasks a group.
//Each group receives the same input, and the output of the first task in the group is fed to the next group

//                         Group 1         Group2
//                         +-----+         +-----+
// dataSource  +------->+> |TaskA+----->+> |TaskD|-----> dataSink
//                      |  +-----+      |  +-----+
//                      |               |
//                      |  +-----+      |  +-----+
//                      +> |TaskB|      +> |TaskE|
//                      |  +-----+      |  +-----+
//                      |               |
//                      |  +-----+      |  +-----+
//                      +> |TaskC|      +> |TaskF|
//                         +-----+         +-----+
//
//During configuration, IF a task in a group can't stream output (e.g. not MTTask.requiresOutputPipe),
//in other words, that the group has to complete before the next group can run
//then the group is automatically split off into a new TaskChain and linked to nextTaskChain
//Thus when all tasks in the current chain are completed, the nextTaskChain is starte,

@interface MTTaskChain : NSObject

@property (strong, nonatomic) NSArray
                                <NSArray
                                    <MTTask *> *> *taskArray;

@property (strong, nonatomic) MTTaskChain *nextTaskChain;

@property (strong, nonatomic) id dataSource, dataSink;  //These should be an NSFileHandle, NSPipe, or for dataSource an NSString (pathname)

@property (weak, nonatomic) MTDownload *download;

@property BOOL isRunning, providesProgress, beingRescheduled;

-(BOOL)run;
-(BOOL)configure;
-(void)cancel;
-(void)trackProgress;

@end
