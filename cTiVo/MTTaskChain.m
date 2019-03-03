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

    self.teeBranches = [NSMapTable strongToStrongObjectsMapTable];

    DDLogVerbose(@"tasks BEFORE config: %@", [self maskMediaKeys]);
    for (NSArray <MTTask *> *currentTaskGroup in self.taskArray) {
        NSMutableArray *inputPipes = [NSMutableArray array];
		if (currentTaskGroup.count ==1 ) {
            MTTask *currentTask = currentTaskGroup[0];
			// No need to tee if only 1 task in group
			if (sourceToTee && currentTask.requiresInputPipe) {
				currentTask.standardInput = sourceToTee;
			}
		} else {
			for (MTTask *task in currentTaskGroup) {
                if (task.requiresInputPipe) {
                    NSPipe *pipe = [NSPipe new];
                    task.standardInput = pipe;
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
				currentTask.standardOutput = outputPipe;
				sourceToTee = [outputPipe fileHandleForReading];
			} else {
                //as next group of tasks requires a finished file, not a pipe, we have to separate into a new taskChain
				NSMutableArray *nextChainTasks = [NSMutableArray array];
                NSUInteger i = [self.taskArray indexOfObject:currentTaskGroup];
				for (NSUInteger k = i+1; k<_taskArray.count; k++) {
					[nextChainTasks addObject:_taskArray[k]];
				}
                self.nextTaskChain = [MTTaskChain new];
                self.nextTaskChain.download = self.download;
                self.nextTaskChain.taskArray = [NSArray arrayWithArray: nextChainTasks] ;
                self.nextTaskChain.dataSink = self.dataSink;
                self.dataSink = nil;
                NSMutableArray *newTaskArray = [NSMutableArray arrayWithArray:self.taskArray];
                [newTaskArray removeObjectsInArray:nextChainTasks];
                self.taskArray = [NSArray arrayWithArray:newTaskArray];
                //rest of array will be configured next time (and we've modified self.taskArray!), so...
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
        [lastTaskGroup firstObject].standardOutput = self.dataSink;
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
	if ([_dataSource isKindOfClass:[NSPipe class]]) { //Data source from pipe
		[[(NSPipe *)_dataSource fileHandleForReading] closeFile];
	}
	if ([_dataSource isKindOfClass:[NSFileHandle class]]) {//Data source from filehandel
		[(NSFileHandle *)_dataSource closeFile];
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
                if (![task launch]) {
                    return NO;
                };
			}
		}

        long priority;
        if (@available (macOS 10.10, *)) {
            priority = QOS_CLASS_UTILITY;
        } else {
            priority = DISPATCH_QUEUE_PRIORITY_LOW;
        }
        dispatch_queue_t queue = dispatch_get_global_queue (priority, 0);

        for (NSFileHandle *fileHandle in self.teeBranches) {
            DDLogDetail(@"Setting up reading of filehandle %p",fileHandle);
            dispatch_io_t channel = dispatch_io_create(DISPATCH_IO_STREAM, [fileHandle fileDescriptor], queue, ^(int error) {
                if(error)
                    DDLogMajor(@"got an error from fildHandle %@ %d (%s)\n", fileHandle, error, strerror(error));
            });
            //    DDLogReport(@"just about to read channel %@", channel);
            dispatch_io_set_low_water(channel, 524288);  //512K
            __weak typeof(self) weakSelf = self;
            dispatch_io_read( channel, 0, SIZE_MAX, queue,
                             ^(bool done,
                               dispatch_data_t  _Nullable data,
                               int error) {
                                 typeof(self) strongSelf = weakSelf;
                                 if (strongSelf) {
                                     if (strongSelf.beingRescheduled || strongSelf.download.isCanceled) return;
                                     [strongSelf teeInBackground:(NSData *)(data) isDone: done forHandle:fileHandle];
                                 }
                             });
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
        DDLogDetail(@"Finished task chain: moving on to %@", _nextTaskChain ?: @"finish up");
        self.isRunning = NO;
        if (_nextTaskChain && !_beingRescheduled && !self.download.isCanceled) {
            self.download.activeTaskChain = _nextTaskChain;
            if (![_nextTaskChain run]) {
				[self.download rescheduleDownload];
            };
        }
    } else if (self.isRunning) {
        [self performSelector:@selector(trackProgress) withObject:nil afterDelay:0.5];

    }
}

-(MTTask *) taskforPipe: (NSPipe *) pipe {
    for (NSArray <MTTask *> * taskGroup in self.taskArray) {
        for (MTTask *task in taskGroup) {
            if (task.standardInput == pipe) {
                return task;
            }
        }
    }
    return nil;
}

-(void)teeInBackground: (NSData *) readData isDone:(BOOL) done forHandle: (NSFileHandle *) incomingHandle {
    self.totalDataRead += readData.length;
    if (self.providesProgress) {
        _download.processProgress = self.totalDataRead/_download.show.fileSize;
    }
    NSArray *pipes = [self.teeBranches objectForKey:incomingHandle];
    if (readData.length) {
        DDLogVerbose(@"Tee got %ld bytes on %@ thread; total: %ld", readData.length, [NSThread isMainThread ] ? @"main" : @"background",self.totalDataRead);
    } else {
        DDLogDetail(@"Tee got 0 bytes after %ld, and is %@cancelled", self.totalDataRead,_download.isCanceled ? @"" : @"not ");
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
					if (currentTask && !currentTask.terminatesEarly && !currentTask.successfulExit) {
						if (numTries == 0) {
							DDLogReport(@"Write Fail: couldn't write to pipe after three tries; %@ may have failed.", taskName);
						} else {
							DDLogReport(@"Write Fail; tried %lu bytes; error: %d; %@ may have failed.", bytesLeft, errno, taskName);
						}
					}
                    if (!currentTask || currentTask.shouldReschedule) {
                        [_download rescheduleDownload];
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
	} else {
        DDLogMajor(@"Finishing Tee because we are %@.",_download.isCanceled ? @"cancelled" : @"finished");
        for (NSPipe *pipe in pipes) {
			@try{
				[[pipe fileHandleForWriting] closeFile];
                DDLogDetail(@"Closing pipe %p",pipe);
			}
			@catch (NSException *exception) {
				DDLogDetail(@"download close pipe fileHandleForWriting fail: %@", exception.reason);
				if (!_download.isCanceled) {
					[_download rescheduleDownload];
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
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}


@end
