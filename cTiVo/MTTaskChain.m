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

@implementation MTTaskChain

__DDLOGHERE__

-(id)init
{
    self = [super init];
    if (self) {
        _dataSink = nil;
        _dataSource = nil;
		isConfigured = NO;
        _isRunning = NO;
        _providesProgress = NO;
		_beingRescheduled = NO;

    }
    return self;
}

-(BOOL)configure
{
    if (isConfigured) {
        return YES;
    }
//    DDLogVerbose(@"Input Task Chain: %@",self);
	//Called configure starts over
	teeBranches = [NSMutableDictionary new];
	branchFileHandles = [NSMutableArray new];
	
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
	
	NSArray *currentTasks = nil;
	NSFileHandle *sourceToTee = nil;
	NSFileHandle *fileHandleToTee = nil;
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
	MTTask *currentTask = nil;
	NSMutableArray *inputPipes = [NSMutableArray array];
	for (NSUInteger i=0; i < _taskArray.count; i++) {
        fileHandleToTee = nil;
		currentTasks = _taskArray[i];
		if (currentTasks.count ==1 ) {
            currentTask = currentTasks[0];
			// No need to tee if only 1 task in level
			if (sourceToTee && currentTask.requiresInputPipe) {
				currentTask.task.standardInput = sourceToTee;
			}
		} else {
			fileHandleToTee = sourceToTee;
			for (NSUInteger j=0; j< currentTasks.count; j++) {
				MTTask *nextTask = currentTasks[j];
                if (nextTask.requiresInputPipe) {
                    NSPipe *pipe = [NSPipe new];
                    nextTask.task.standardInput = pipe;
                    [inputPipes addObject:pipe];
                }
			}
		}
		if (fileHandleToTee) {
			[teeBranches setObject:[NSArray arrayWithArray:inputPipes] forKey:(id)fileHandleToTee];
			[branchFileHandles addObject:fileHandleToTee];
		}
		if (i < _taskArray.count - 1) {		//Set up the next source except for the last set or if stdout is already set
											//If stdout is set the the next task will be sequential, not piped.
			currentTask = currentTasks[0];  //Next potential source
			if (currentTask.requiresOutputPipe) {
				NSPipe *outputPipe = [NSPipe pipe];
				currentTask.task.standardOutput = outputPipe;
				sourceToTee = [outputPipe fileHandleForReading];
			} else {
				NSMutableArray *nextChain = [NSMutableArray array];
                NSMutableArray *newTaskArray = [NSMutableArray arrayWithArray:_taskArray];
				for (NSUInteger k = i+1; k<_taskArray.count; k++) {
					[nextChain addObject:_taskArray[k]];
				}
				if (nextChain.count) {
					self.nextTaskChain = [MTTaskChain new];
                    self.nextTaskChain.taskArray = nextChain;
                    [newTaskArray removeObjectsInArray:nextChain];
                    _taskArray = [NSArray arrayWithArray:newTaskArray];
				}
				break;
			}
		}
	}
	for (NSArray *tasks in _taskArray) {
		for (MTTask *task in tasks) {
			task.myTaskChain = self;
		}
	}
	if (_dataSink) {
		((MTTask *)currentTasks[0]).task.standardOutput = _dataSink;
	}
    //Show configuration
    DDLogVerbose(@"\n\nConfigured Task Chain: %@",self);
	isConfigured = YES;
	return YES;
}

-(NSString *)description
{
	NSString *desc = @"";
	desc = [desc stringByAppendingFormat:@"dataSource: %@",_dataSource];
	desc = [desc stringByAppendingFormat:@"\ndataSink: %@",_dataSink];
	desc = [desc stringByAppendingFormat:@"\nNumber of Task Levels: %ld",_taskArray.count];
	for (NSArray *tasks in _taskArray) {
        desc = [desc stringByAppendingFormat:@"\n---------------------------------------\nThis level has %ld tasks",tasks.count];
        for (MTTask *task in tasks) {
            desc = [desc stringByAppendingFormat:@"\n%@",task];
        }
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
	if (!isConfigured) { //Try 
		[self configure];
	}
	if (isConfigured) {
        totalDataRead  = 0;
		for (int i=(int)_taskArray.count-1; i >=0 ; i--) {
			for (MTTask *task in _taskArray[i]) {
                DDLogMajor(@"Starting task %@ for show %@",task.taskName,task.download.show.showTitle);
				[task launch];				
			}
		}
		for (NSFileHandle *fileHandle in branchFileHandles) {
            DDLogDetail(@"Setting up reading of filehandle %p",fileHandle);
			[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(tee:) name:NSFileHandleReadCompletionNotification object:fileHandle];
            [fileHandle readInBackgroundAndNotify];
		}

	}
    _isRunning = YES;
    [self performSelector:@selector(trackProgress) withObject:nil afterDelay:0.5];
	return isConfigured;
}

-(void)startReading:(NSNotification *)notification
{
    [(NSFileHandle *)(notification.object) readInBackgroundAndNotify];

}


-(void)trackProgress //See if any tasks in this chain are running
{
    BOOL isRunning = NO;
    DDLogVerbose(@"Tracking task chain");
    for (NSArray *taskset in _taskArray) {
        for(MTTask *task in taskset) {
            if (task.taskRunning) {
                isRunning = YES;
                break;
            }
        }
    }
    if (!isRunning) {
        //We need to move on
        if (_nextTaskChain && !_beingRescheduled) {
            self.download.activeTaskChain = _nextTaskChain;
            [_nextTaskChain run];
        }
    } else {
        [self performSelector:@selector(trackProgress) withObject:nil afterDelay:0.5];

    }
}

-(void)tee:(NSNotification *)notification
{
//    NSLog(@"Got read for tee ");
	NSData *readData = notification.userInfo[NSFileHandleNotificationDataItem];
    totalDataRead += readData.length;
    if (_providesProgress) {
        _download.processProgress = totalDataRead/_download.show.fileSize;
        [NSNotificationCenter postNotificationNameOnMainThread:kMTNotificationProgressUpdated object:nil];
    }
//    NSLog(@"Total Data Read %ld",totalDataRead);
    NSArray *pipes = [teeBranches objectForKey:notification.object];
    if (readData.length) {
        DDLogVerbose(@"Got %ld bytes", readData.length);
    } else {
        DDLogMajor(@"Got 0 bytes, and is %@cancelled",_download.isCanceled ? @"" : @"not ");
    }
	if (readData.length && !_download.isCanceled) {
        for (NSPipe *pipe in pipes ) {
			//			NSLog(@"Writing data on %@",pipe == subtitlePipe ? @"subtitle" : @"encoder");
            if (!_download.isCanceled){
				@try {
                    //should be just the following, but it ignores @try/@catch
                    //[[pipe fileHandleForWriting] writeData:readData];
                    ssize_t amountSent= write ([[pipe fileHandleForWriting] fileDescriptor], [readData bytes], [readData length]);
                    if (amountSent < 0 || ((NSUInteger)amountSent != [readData length])) {
                        if (!_download.isCanceled){
                            [_download rescheduleOnMain];
                            DDLogDetail(@"Rescheduling");
                        };
                        DDLogDetail(@"download tee: write fail2; tried %lul bytes; wrote %zd", (unsigned long)[readData length], amountSent);
                    }
				}
				@catch (NSException *exception) {
					DDLogMajor(@"download tee: write fail: Bug in Encoder? %@", exception.reason);
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
		if (!_download.isCanceled) {
			@try {
				[(NSFileHandle *)(notification.object) readInBackgroundAndNotify];
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
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}


@end
