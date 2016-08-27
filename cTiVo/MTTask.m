//
//  MTTask.m
//  cTiVo
//
//  Created by Scott Buchanan on 4/9/13.
//  Copyright (c) 2013 cTiVo. All rights reserved.
//

#import "MTTask.h"
#import "MTDownload.h"
#import "MTTaskChain.h"
#import "MTTiVoManager.h"
#import "NSNotificationCenter+Threads.h"
#ifndef DEBUG
#import "Crashlytics/Crashlytics.h"
#endif

@interface MTTask ()
{
    BOOL launched;
}

@end

@implementation MTTask

__DDLOGHERE__

+(MTTask *)taskWithName:(NSString *)name download:(MTDownload *)download completionHandler:(BOOL(^)(void))completionHandler
{
	MTTask *mTTask = [MTTask taskWithName:name download:download];
	mTTask.completionHandler = completionHandler;
	return mTTask;
}
+(MTTask *)taskWithName:(NSString *)name download:(MTDownload *)download
{
    DDLogDetail(@"Creating Task %@",name);
    MTTask *mTTask = [MTTask new];
//    mTTask.task  = [NSTask new];
    mTTask.download = download;
    mTTask.taskName = name;
    mTTask.task.currentDirectoryPath = [tiVoManager tmpFilesDirectory];
    return mTTask;
}

-(id)init
{
    self = [super init];
    if (self) {
        self.task = [NSTask new];
        self.taskName = @"";
        _startupHandler = nil;
        _completionHandler = nil;
		_terminationHandler = nil;
        _progressCalc = nil;
        _cleanupHandler = nil;
        _requiresInputPipe = YES;
        _requiresOutputPipe = YES;
        _shouldReschedule = YES;
		_successfulExitCodes = @[@0];
        launched = NO;
        _taskRunning = NO;
    }
    return self;
}

-(void)setTaskName:(NSString *)taskName
{
	if (taskName == _taskName) {
		return;
	}
	[self cleanUp];
	_taskName = taskName;
    if (self.download) {
        self.logFilePath = [NSString stringWithFormat:@"%@/%@%@.txt",tiVoManager.tmpFilesDirectory,taskName,self.download.baseFileName];
        if (![[NSFileManager defaultManager] createFileAtPath:_logFilePath contents:[NSData data] attributes:nil]) {
            DDLogReport(@"Could not create logfile at %@",_logFilePath);
#ifndef DEBUG
            [CrashlyticsKit setObjectValue:_logFilePath forKey:@"CreateLogFile"];
#endif
        }
        self.logFileWriteHandle = [NSFileHandle fileHandleForWritingAtPath:_logFilePath];
        self.logFileReadHandle	= [NSFileHandle fileHandleForReadingAtPath:_logFilePath];
        self.errorFilePath = [NSString stringWithFormat:@"%@/%@%@.err",tiVoManager.tmpFilesDirectory,taskName,self.download.baseFileName];
        if (![[NSFileManager defaultManager] createFileAtPath:_errorFilePath contents:[NSData data] attributes:nil]) {
            DDLogReport(@"Could not create errfile at %@",_logFilePath);
#ifndef DEBUG
            [CrashlyticsKit setObjectValue:_logFilePath forKey:@"CreateErrFile"];
#endif
        }

        self.errorFileHandle = [NSFileHandle fileHandleForWritingAtPath:_errorFilePath];
        if (self.logFileWriteHandle) {
            [self setStandardOutput:self.logFileWriteHandle];
        } else {
            DDLogReport(@"Could not open logfile at %@",_logFilePath);
#ifndef DEBUG
            [CrashlyticsKit setObjectValue:_logFilePath forKey:@"BadLogFile"];
#endif
        }
        [self setStandardInput:self.logFileReadHandle];
        [self setStandardError:self.errorFileHandle];
    }
}

-(void)cancel
{
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    DDLogDetail(@"Terminating task %@",_taskName);
	if (_terminationHandler) {
		_terminationHandler();
	}
	[self terminate];

	//following line has important side effect that it lets the task do whatever it needs to do to terminate before killing it dead in dealloc
	[self performSelector:@selector(saveLogFile) withObject:self afterDelay:2.0];
}

-(void)cleanUp
{
    if (_cleanupHandler) {
        _cleanupHandler();
        _cleanupHandler = nil; //only call once
    }
	if (_logFileWriteHandle) {
		[_logFileWriteHandle closeFile];
		self.logFileWriteHandle = nil;
	}
	if (_logFileReadHandle) {
		[_logFileReadHandle closeFile];
		self.logFileReadHandle = nil;
	}
	if (_errorFileHandle) {
		[_errorFileHandle closeFile];
		self.errorFileHandle = nil;
	}
	if ([[NSFileManager defaultManager] fileExistsAtPath:_logFilePath]) {
		if (![[NSUserDefaults standardUserDefaults] boolForKey:kMTSaveTmpFiles]) {
			[[NSFileManager defaultManager] removeItemAtPath:_logFilePath error:nil];
		}
	}
	if ([[NSFileManager defaultManager] fileExistsAtPath:_errorFilePath]) {
		if (![[NSUserDefaults standardUserDefaults] boolForKey:kMTSaveTmpFiles]) {
			[[NSFileManager defaultManager] removeItemAtPath:_errorFilePath error:nil];
		}
	}
}

-(void) saveLogFileType:(NSString *) type fromPath: (NSString *) path {
	NSFileHandle *logHandle = [NSFileHandle fileHandleForReadingAtPath:path];
	unsigned long long logFileSize = [logHandle seekToEndOfFile];
	if (logFileSize > 0) {
		NSUInteger backup = 2000;  //how much to log
		if (logFileSize < backup) backup = (NSInteger)logFileSize;
		[logHandle seekToFileOffset:(logFileSize-backup)];
		NSData *tailOfFile = [logHandle readDataOfLength:backup];
		if (tailOfFile.length > 0) {
			NSString * logString = [[NSString alloc] initWithData:tailOfFile encoding:NSUTF8StringEncoding];
			DDLogMajor(@"%@File for task %@: %@",type, _taskName,  [logString maskMediaKeys]);
		}
	}
}

-(void) saveLogFile
{
	if (ddLogLevel >= LOG_LEVEL_REPORT) {
		[self saveLogFileType:@"log" fromPath:_logFilePath];
		[self saveLogFileType:@"err" fromPath:_errorFilePath];
	}
}

-(void)completeProcess
{
    _taskRunning = NO;
    DDLogMajor(@"Finished task %@ of show %@ with completion code %d and reason %@",_taskName, _download.show.showTitle, _task.terminationStatus,[self reasonForTermination]);
    if (self.taskFailed) {
		[self failedTaskCompletion];
    } else {
        if (_completionHandler) {
			if(!_completionHandler()) { //The task actually failed
				[self failedTaskCompletion];
				return;
			}
        }
        [self cleanUp];
    }
}

-(void)failedTaskCompletion
{
	DDLogReport(@"Task %@ failed",self.taskName);
	[self saveLogFile];
	[self cleanUp];
	if (!_download.isCanceled && _shouldReschedule){  // _shouldReschedule is for failure of non-critical tasks
		_myTaskChain.beingRescheduled = YES;
		[_download rescheduleShowWithDecrementRetries:@YES];
	}
	
}

-(NSString *)reasonForTermination
{
    if (launched ) {
        if (! _task.isRunning) {
            return (_task.terminationReason == NSTaskTerminationReasonUncaughtSignal) ? @"uncaught signal" : @"exit";
        } else {
            return @"still running";
        }
    } else {
        return @"not launched";
    }
}

-(BOOL)taskFailed
{
    if (!launched || _task.isRunning) {
        return NO;
    } else {
        return _task.terminationReason == NSTaskTerminationReasonUncaughtSignal || ![self successfulExit] ;
    }
}

-(BOOL)successfulExit
{
	BOOL ret = NO;
    if (!launched || _task.isRunning) return NO;
	for (NSNumber *exitCode in _successfulExitCodes) {
		if ([exitCode intValue] == _task.terminationStatus) {
			ret = YES;
			break;
		}
	}
	return ret;
}


-(void) trackProcess
{
	DDLogVerbose(@"Tracking %@ for show %@",_taskName,_download.show.showTitle);
	if (![self.task isRunning]) {
        [self completeProcess];
	} else {
		double newProgressValue = -1;
		NSUInteger sizeOfFileSample = 180;
		unsigned long long logFileSize = [self.logFileReadHandle seekToEndOfFile];
		if (logFileSize > sizeOfFileSample) {
			[self.logFileReadHandle seekToFileOffset:(logFileSize-sizeOfFileSample)];
			NSData *tailOfFile = [self.logFileReadHandle readDataOfLength:sizeOfFileSample];
			NSString *data = [[NSString alloc] initWithData:tailOfFile encoding:NSUTF8StringEncoding];
            if (_trackingRegEx) {
                newProgressValue = [self progressValueWithRx:data];
            }
            if (_progressCalc) {
                newProgressValue = _progressCalc(data);
            }
            if (newProgressValue != -1) {
                DDLogVerbose(@"New progress value for %@ is %lf",_taskName,newProgressValue);
				if ((newProgressValue != _download.processProgress) && (newProgressValue != 0)) {
					_download.processProgress = newProgressValue;
				}
			}
		}
		[self performSelector:@selector(trackProcess) withObject:nil afterDelay:0.5];
	}
}

-(double)progressValueWithRx:(NSString *)data
{
//    NSRegularExpression *percents = [NSRegularExpression regularExpressionWithPattern:@"(\\d+)%" options:NSRegularExpressionCaseInsensitive error:nil];
    NSArray *values = nil;
    if (data) {
        values = [_trackingRegEx matchesInString:data options:NSMatchingWithoutAnchoringBounds range:NSMakeRange(0, data.length)];
    }
    if (values && values.count) {
        NSTextCheckingResult *lastItem = [values lastObject];
        NSRange valueRange = [lastItem rangeAtIndex:1];
        return ([[data substringWithRange:valueRange] doubleValue]/100.0);

    } else {
        DDLogMajor(@"Track progress with Rx failed for task %@ for show %@",_taskName,_download.show.showTitle);
        return 0.0;
    }
}

-(NSString *)description
{
    NSString *desc = [NSString stringWithFormat:@"Task Name: %@",_taskName];
    desc = [desc stringByAppendingFormat:@"\n%@ input pipe",_requiresInputPipe ? @"Requires" : @"Does not require"];
    desc = [desc stringByAppendingFormat:@"\n%@ output pipe",_requiresOutputPipe ? @"Requires" : @"Does not require"];
    desc = [desc stringByAppendingFormat:@"\nStandard Input: %@",_task.standardInput];
    desc = [desc stringByAppendingFormat:@"\nStandard Output: %@",_task.standardOutput];
    desc = [desc stringByAppendingFormat:@"\nStandard Error: %@",_task.standardError];
    //    desc = [desc stringByAppendingFormat:@"\nbasename = %@",_baseName];
    //    desc = [desc stringByAppendingFormat:@"\noutputFilePath = %@",_outputFilePath];
    desc = [desc stringByAppendingFormat:@"\nlogFilePath = %@",_logFilePath];
    desc = [desc stringByAppendingFormat:@"\nerrorFilePath = %@",_errorFilePath];
    desc = [desc stringByAppendingFormat:@"\nFile Handles: output: %p; error: %p, logFileRead:%p, logFileWrite:%p ",_outputFileHandle, _errorFileHandle, _logFileReadHandle, _logFileWriteHandle];
    desc = [desc stringByAppendingFormat:@"\nTracking RegEx = %@",_trackingRegEx];
    desc = [desc stringByAppendingFormat:@"\n%@ completionHandler",_completionHandler ? @"Has" : @"Does not have"];
    desc = [desc stringByAppendingFormat:@"\n%@ progressCalc",_progressCalc ? @"Has" : @"Does not have"];
    desc = [desc stringByAppendingFormat:@"\n%@ startupHandler",_startupHandler ? @"Has" : @"Does not have"];
//    desc = [desc stringByAppendingFormat:@"\n%@ a following task chain",_nextTaskChain ? @"Has" : @"Does not have"];
    return desc;
}

#pragma mark - Task Mapping Functions

-(void)setLaunchPath:(NSString *)path
{
    if (path.length > 0) {
        [_task setLaunchPath:path];
    } else {
        DDLogReport(@"Error: executable path for %@ not found", self.taskName);
    }
}

-(void)setCurrentDirectoryPath:(NSString *)path
{
    [_task setCurrentDirectoryPath:path];
}

-(void)setEnvironment:(NSDictionary *)env
{
    [_task setEnvironment:env];
}

-(void)setArguments:(NSArray *)args
{
    [_task setArguments:args];
}

-(void)setStandardOutput:(id)stdo
{
    [_task setStandardOutput:stdo];
}

-(void)setStandardInput:(id)stdi
{
    [_task setStandardInput:stdi];
}

-(void)setStandardError:(id)stde
{
    [_task setStandardError:stde];
}

-(void)launch
{
    if (!_task.launchPath) {
        DDLogReport(@"Error: no executable for %@; cannot launch", self.taskName);
       return;
    }
    BOOL shouldLaunch = YES;
    if (_startupHandler) {
        shouldLaunch = _startupHandler();
    }
    if (shouldLaunch) {
        [_task launch];
        launched = YES;
        _taskRunning = YES;
        _pid = [_task processIdentifier];
        [self trackProcess];
    } else {
        if (_completionHandler) {
            _completionHandler();
        }
    }
}

-(void)terminate
{
    _taskRunning = NO;
    if ([_task isRunning]) {
        [_task terminate];

    }
}

-(void)interrupt
{
    if ([_task isRunning]) {
        [_task interrupt];
    }
}

-(void)suspend
{
    if ([_task isRunning]) {
        [_task suspend];
    }
}

-(void)waitUntilExit
{
    if ([_task isRunning]) {
        [_task waitUntilExit];
    }
    [self completeProcess];
}

-(BOOL)isRunning
{
    return _taskRunning;
}

-(void)dealloc
{
    if (_pid && !kill(_pid, 0)) {
        DDLogDetail(@"Killing process %@",_taskName);
        kill(_pid , SIGKILL);
    }
	_task = nil;
	[self cleanUp];
}

@end
