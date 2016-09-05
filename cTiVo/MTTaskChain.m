//
//  MTTaskChain.m
//  cTiVo
//
//  Created by Scott Buchanan on 4/10/13.
//  Copyright (c) 2013 cTiVo. All rights reserved.
//

#import "MTTaskChain.h"
#import "MTDownload.h"
#import "NSNotificationCenter+Threads.h"
#import "MTTiVoManager.h" //Just for maskMediaKeys

@interface MTTaskChain ()

@property (atomic, strong) NSMapTable *teeBranches;
@property (atomic, assign) ssize_t totalDataRead;

@end

@implementation MTTaskChain

__DDLOGHERE__

-(id)init
{
    self = [super init];
    if (self) {
        _dataSink = nil;
        _dataSource = nil;
        _isRunning = NO;
        _providesProgress = NO;
		_beingRescheduled = NO;

    }
    return self;
}

-(BOOL)configure
{
	// Check for misconfigured chains
	
   if (_taskArray.count == 0) {
	   DDLogMajor(@"Task chain with no content found");
        return NO; //nothing to do
    }
	if (((NSArray *)[_taskArray lastObject]).count > 1 && _dataSink) { //Can't use the same datasink for multiple
		DDLogMajor(@"Can't use a TaskChain dataSink for multiple tasks");
		return NO;
	}
	if (_dataSource && [_dataSource isKindOfClass:[NSString class]]) {
		if (![[NSFileManager defaultManager] fileExistsAtPath:_dataSource]) {
			DDLogMajor(@"Specified file path not found for taskChain");
			return NO;	
		}
	}
	
	//No problems found so configure
	NSFileHandle *sourceToTee = nil;
	if (_dataSource) {
		if ([_dataSource isKindOfClass:[NSPipe class]]) { //Data source from pipe
			sourceToTee = [(NSPipe *)_dataSource fileHandleForReading];
		}
		if ([_dataSource isKindOfClass:[NSFileHandle class]]) {//Data source from filehandel
			sourceToTee = (NSFileHandle *)_dataSource;
		}
		if (([_dataSource isKindOfClass:[NSString class]])) { //Data source from file path
			sourceToTee = [NSFileHandle fileHandleForReadingAtPath:_dataSource];
		}
	}

    self.teeBranches = [NSMapTable mapTableWithKeyOptions:NSMapTableWeakMemory
                                             valueOptions:NSMapTableStrongMemory];
    for (NSArray <MTTask *> *currentTaskGroup in self.taskArray) {
        NSMutableArray *inputPipes = [NSMutableArray array];
		if (currentTaskGroup.count ==1 ) {
            MTTask *currentTask = currentTaskGroup[0];
			// No need to tee if only 1 task in group
			if (sourceToTee && currentTask.requiresInputPipe) {
				currentTask.task.standardInput = sourceToTee;
			}
		} else {
			for (MTTask *task in currentTaskGroup) {
                if (task.requiresInputPipe) {
                    NSPipe *pipe = [NSPipe new];
                    task.task.standardInput = pipe;
                    [inputPipes addObject:pipe];
                }
			}
            if (sourceToTee) {
                [self.teeBranches setObject:[NSArray arrayWithArray:inputPipes] forKey:sourceToTee];
            }
		}
		if (currentTaskGroup != self.taskArray.lastObject ) {
            //Set up the next source (except for the last set)
            MTTask *currentTask = currentTaskGroup[0];  //Source for next group is first task of this group
			if (currentTask.requiresOutputPipe) {
				NSPipe *outputPipe = [NSPipe pipe];
				currentTask.task.standardOutput = outputPipe;
				sourceToTee = [outputPipe fileHandleForReading];
			} else {
                //as next group of tasks requires a finished file, not a pipe, we have to separate into a new taskChain
				NSMutableArray *nextChainTasks = [NSMutableArray array];
                NSUInteger i = [self.taskArray indexOfObject:currentTaskGroup];
				for (NSUInteger k = i+1; k<_taskArray.count; k++) {
					[nextChainTasks addObject:_taskArray[k]];
				}
				if (nextChainTasks.count) {
					self.nextTaskChain = [MTTaskChain new];
                    self.nextTaskChain.download = self.download;
                    self.nextTaskChain.taskArray = [NSArray arrayWithArray: nextChainTasks] ;
                    self.nextTaskChain.dataSink = self.dataSink;
                    self.dataSink = nil;
                    NSMutableArray *newTaskArray = [NSMutableArray arrayWithArray:self.taskArray];
                    [newTaskArray removeObjectsInArray:nextChainTasks];
                    self.taskArray = [NSArray arrayWithArray:newTaskArray];
				}
				break;
			}
		}
	}
	for (NSArray <MTTask *> *tasks in self.taskArray) {
		for (MTTask *task in tasks) {
			task.myTaskChain = self;
		}
	}
	if (self.dataSink) {
        NSArray <MTTask *> *lastTaskGroup = [self.taskArray lastObject];
        [lastTaskGroup firstObject].task.standardOutput = self.dataSink;
	}
    DDLogVerbose(@" teeBranches = %@", self.teeBranches);
    //Show configuration
    DDLogDetail(@"\n\n***Configured Task Chain***: %@",[self maskMediaKeys]);
	return YES;
}

-(NSString *)description
{
	NSString *desc = @"";
	desc = [desc stringByAppendingFormat:@"\ndataSource: %@",_dataSource];
	desc = [desc stringByAppendingFormat:@"\ndataSink: %@",_dataSink];
	desc = [desc stringByAppendingFormat:@"\nNumber of Task Groups: %ld",_taskArray.count];
	for (NSArray *tasks in _taskArray) {
        desc = [desc stringByAppendingFormat:@"\n---------------------------------------\nThis group has %ld tasks",tasks.count];
        for (MTTask *task in tasks) {
            desc = [desc stringByAppendingFormat:@"\n%@",task];
        }
    }
    if (self.nextTaskChain) {
        desc = [desc stringByAppendingFormat:@"\n=======================================\nNext Chain: %@",self.nextTaskChain];
    }
	return desc;
}

-(void)cancel
{
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    for (int i=(int)_taskArray.count-1; i >=0 ; i--) {
        for (MTTask *task in _taskArray[i]) {
            DDLogMajor(@"Canceling task %@ for show %@",task.taskName,task.download.show.showTitle);
			[task cancel];
        }
    }
    _isRunning = NO;
}

-(BOOL)run
{
    BOOL isConfigured = [self configure];
	if (isConfigured) {
        self.totalDataRead  = 0;
		for (int i=(int)_taskArray.count-1; i >=0 ; i--) {
			for (MTTask *task in _taskArray[i]) {
                DDLogMajor(@"Starting task %@ for show %@",task.taskName,task.download.show.showTitle);
				[task launch];				
			}
		}
		for (NSFileHandle *fileHandle in self.teeBranches) {
            DDLogDetail(@"Setting up reading of filehandle %p",fileHandle);
			[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(tee:) name:NSFileHandleReadCompletionNotification object:fileHandle];
            [fileHandle readInBackgroundAndNotify];
		}

        _isRunning = YES;
        [self performSelector:@selector(trackProgress) withObject:nil afterDelay:0.5];
    }
    return isConfigured;
}

-(void)startReading:(NSNotification *)notification
{
    [(NSFileHandle *)(notification.object) readInBackgroundAndNotify];

}


-(void)trackProgress //See if any tasks in this chain are running
{
    if (!_isRunning) return;   //check if we've been canceled
    BOOL taskRunning = NO;
    for (NSArray *taskset in _taskArray) {
        for(MTTask *task in taskset) {
            if (task.isRunning) {
                taskRunning = YES;
                DDLogVerbose(@"Tracking task chain: %@ for %@",task.taskName, self.download.show.showTitle);
                break;
            }
        }
        if (taskRunning) break;
    }
    if (!taskRunning) {
        //We need to move on
        DDLogVerbose(@"Finished task chain: moving on to %@", _nextTaskChain ?: @"finish up");
        self.isRunning = NO;
        if (_nextTaskChain && !_beingRescheduled) {
            self.download.activeTaskChain = _nextTaskChain;
            [_nextTaskChain run];
        }
    } else {
        [self performSelector:@selector(trackProgress) withObject:nil afterDelay:0.5];

    }
}

-(MTTask *) taskforPipe: (NSPipe *) pipe {
    for (NSArray <MTTask *> * taskGroup in self.taskArray) {
        for (MTTask *task in taskGroup) {
            if (task.task.standardInput == pipe) {
                return task;
            }
        }
    }
    return nil;
}

-(void)tee:(NSNotification *)notification {
    dispatch_async(dispatch_get_global_queue( DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(void){
        //run on Background Thread
        [self teeInBackground:notification];
     });
}

-(void)teeInBackground:(NSNotification *)notification {

	NSData *readData = notification.userInfo[NSFileHandleNotificationDataItem];
    self.totalDataRead += readData.length;
    if (_providesProgress) {
        _download.processProgress = self.totalDataRead/_download.show.fileSize;
        }
//    NSLog(@"Total Data Read %ld",totalDataRead);
    NSFileHandle * incomingHandle = (NSFileHandle *) notification.object;
    NSArray *pipes = [self.teeBranches objectForKey:incomingHandle];
    if (readData.length) {
        DDLogVerbose(@"Tee got %ld bytes", readData.length);
    } else {
        DDLogMajor(@"Tee got 0 bytes, and is %@cancelled",_download.isCanceled ? @"" : @"not ");
    }
	if (readData.length && !_download.isCanceled) {
        for (NSPipe *pipe in pipes ) {
			//			NSLog(@"Writing data on %@",pipe == subtitlePipe ? @"subtitle" : @"encoder");
            if (!_download.isCanceled){
               //should be just the following, but writedata ignores @try/@catch
                 // @try {
                //  [[pipe fileHandleForWriting] writeData:readData];
                // @catch (NSException *exception) {
                NSInteger numTries = 3;
                size_t bytesLeft = readData.length;
                MTTask * currentTask = nil;
                while (bytesLeft > 0 && numTries > 0 ) {
                    ssize_t amountSent= write ([[pipe fileHandleForWriting] fileDescriptor], [readData bytes]+readData.length-bytesLeft, bytesLeft);
                    if (amountSent < 0) {
                        currentTask = [self taskforPipe:pipe];
                        break;
                    } else {
                        bytesLeft = bytesLeft- amountSent;
                        if (bytesLeft > 0) {
                            DDLogMajor(@"pipe full, retrying; tried %lu bytes; wrote %zd", (unsigned long)[readData length], amountSent);
                            sleep(1);  //probably too long, but this should be quite rare
                            numTries--;
                        }
                    }
                }
                if (bytesLeft >0 && !_download.isCanceled){
                    //Couldn't write all data
                    NSString * taskName = currentTask.taskName ?: @"unknown task";
                    if (numTries == 0) {
                        DDLogReport(@"Write Fail: couldn't write to pipe after three tries; %@ may have crashed.", taskName);
                    } else {
                        DDLogReport(@"Write Fail; tried %lu bytes; error: %zd; %@ may have crashed.", bytesLeft, errno, taskName);
                    }
                    if (!currentTask || currentTask.shouldReschedule) {
                        [_download rescheduleOnMain];
                    } else if (! currentTask.shouldReschedule) {
                        //this task not critical, proceeding without it.
                        if (pipes.count <= 1) {
                            [self.teeBranches removeObjectForKey:incomingHandle];
                            incomingHandle = nil;  //no more reads here
                                                   //Do we need to reset pipes across this one?
                        } else {
                            NSMutableArray * newPipes = [pipes mutableCopy];
                            [newPipes removeObject:pipe];
                            [self.teeBranches setObject:[NSArray arrayWithArray:newPipes] forKey:incomingHandle];
                        }
                        [currentTask cancel];
                    }

                }
			}
        }
		if (!_download.isCanceled) {
            dispatch_async(dispatch_get_main_queue(), ^{
                @try {
                    [incomingHandle readInBackgroundAndNotify];
                }
                @catch (NSException *exception) {
                    DDLogDetail(@"download read data in background fail: %@", exception.reason);
                    if (!_download.isCanceled) {
                        [_download rescheduleOnMain];
                    }
                    return;
                    
                }
                @finally {
                }
            });

		}

	} else {
        DDLogMajor(@"Really Quitting because data length is %ld and is %@cancelled",readData.length, _download.isCanceled ? @"" : @"not ");
        for (NSPipe *pipe in pipes) {
			@try{
				[[pipe fileHandleForWriting] closeFile];
                DDLogDetail(@"Closing pipe %p",pipe);
			}
			@catch (NSException *exception) {
				DDLogDetail(@"download close pipe fileHandleForWriting fail: %@", exception.reason);
				if (!_download.isCanceled) {
					[_download rescheduleOnMain];
					DDLogDetail(@"Rescheduling");
				}
				return;
				
			}
			@finally {
			}
		}
    }
}

-(void)dealloc
{
    DDLogVerbose(@"Deallocing taskChain");
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}


@end
