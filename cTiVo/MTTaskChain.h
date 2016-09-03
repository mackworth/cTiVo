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

/*
Task Chain structure
 A TaskChain describes a set of file processing steps to be executed concurrently
It has an array of array of MTTasks to be chained in order. We call each subarray of tasks a group.
Each group receives the same input, and the output of the first task in the group is fed to the next group

                         Group 1         Group2
                         +-----+         +-----+
 dataSource  +------->+> |TaskA+----->+> |TaskD|-----> dataSink
                      |  +-----+      |  +-----+
                      |               |
                      |  +-----+      |  +-----+
                      +> |TaskB|      +> |TaskE|
                      |  +-----+      |  +-----+
                      |               |
                      |  +-----+      |  +-----+
                      +> |TaskC|      +> |TaskF|
                         +-----+         +-----+

During configuration, IF a task in a group can't stream output (e.g. not MTTask.requiresOutputPipe),
in other words, that the group has to complete before the next group can run
then the group is automatically split off into a new TaskChain and linked to nextTaskChain
Thus when all tasks in the current chain are completed, the nextTaskChain is started,

Flow of data:
 MTDownload initiates the URL download from the Tivo in MTDownload>download.
 When a packet arrives, the system calls MTDownload connection:didReceiveData which either stores it in memory in urlBuffer or writes it to bufferFileHandle.
 Then download>WriteData in the background reads that data and writes it to the taskchain's inputhandle.
 If the first group of the taskchain only has one member, then we don't need to tee, we just connect the inputhandle directly as a pipe into the task.
 OR if there's more than one, then MTTaskChain runs tee on a ReadAndNotifyInBackground

 Note that tee is not necessarily run in all configurations, so be careful of assuming it does


Progress Tracking:
A taskchain is a group of concurrent tasks ((e.g. decrypt, caption and encode; an NSTask wrapped in MTTask) for a single show.  Each task, taskchain and download is timed.

 MTTask's trackProcess is run every 0.5 seconds, and if the task is done, it runs the completion process and sets itself to "not isRunning". If not running, then it runs the progress calculation (either Regex or progressCalc) to set the download's progress.

 MTTaskChain follows a similar process with trackProgress being run every 0.5 seconds. It checks each task in the chain for isRunning. If all are done, then it launches its nextTaskChain if any.

 MTDownload uses a more convoluted process currently, where the completion process of either encode or commercial tasks (whichever is run last) calls the FinishUpPostEncodeProcessing routine. In the future, it would be cleaner to add a completion task to MTTaskChain which gets called when the final taskchain is completed.

 MTDownload also runs a deadman checkStillActive method every two minutes and relies on the progress setting of MTTask to ensure that progress is actually being made. Note that at 100%, Handbrake can take a couple minutes of post processing without showing any signs of progress, so we extend this time to 8 minutes when we're at 100% to give it the benefit of the doubt.

 Because of the flexibility of the architecture, tracking overall download progress is a bit of a mess, provided by a couple of sources (in addition to various places that initialize and finalize)
	NSTask progress tracking sets overall download progress in each task that has a progressCalc set
	MTDownload>WriteData sets it for data written to the inputhandle of the taskchain iff encoder doesn't track progress. As there is little buffer on inputhandle, this is essentially the same as tracking the bytes processed by the task.
	MTTaskChain>teeInBackground will provide it for files read from disk (not currently implemented)

 There is a separate progressTimer in MTDownload, used solely for user interface updating for speed, progress bar and completion time calculation.


*/
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
