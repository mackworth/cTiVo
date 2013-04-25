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

@implementation MTTask

__DDLOGHERE__

+(MTTask *)taskWithName:(NSString *)name download:(MTDownload *)download completionHandler:(void(^)(void))completionHandler
{
	MTTask *mTTask = [MTTask taskWithName:name download:download];
	mTTask.completionHandler = completionHandler;
	return mTTask;
}
+(MTTask *)taskWithName:(NSString *)name download:(MTDownload *)download
{
    DDLogVerbose(@"Creating Task %@",name);
    MTTask *mTTask = [MTTask new];
//    mTTask.task  = [NSTask new];
    mTTask.download = download;
    mTTask.taskName = name;
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
        _progressCalc = nil;
        _cleanupHandler = nil;
		_nextTaskChain = nil;
        _requiresInputPipe = YES;
        _requiresOutputPipe = YES;
		_successfulExitCode = 0;
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
        self.logFilePath = [NSString stringWithFormat:@"%@%@%@.txt",kMTTmpDir,taskName,self.download.baseFileName];
		[[NSFileManager defaultManager] createFileAtPath:_logFilePath contents:[NSData data] attributes:nil];
        self.logFileWriteHandle = [NSFileHandle fileHandleForWritingAtPath:_logFilePath];
        self.logFileReadHandle	= [NSFileHandle fileHandleForReadingAtPath:_logFilePath];
        self.errorFilePath = [NSString stringWithFormat:@"%@%@%@.err",kMTTmpDir,taskName,self.download.baseFileName];
		[[NSFileManager defaultManager] createFileAtPath:_errorFilePath contents:[NSData data] attributes:nil];
        self.errorFileHandle = [NSFileHandle fileHandleForWritingAtPath:_errorFilePath];
        [self setStandardOutput:self.logFileWriteHandle];
        [self setStandardInput:self.logFileWriteHandle];
        [self setStandardError:self.errorFileHandle];
    }
}

-(void)cancel
{
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    DDLogVerbose(@"Terminating task %@",_taskName);
	[_task terminate];
    [self cleanUp];
}

-(void)cleanUp
{
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
    if (_cleanupHandler) {
        _cleanupHandler();
    }

}

-(void) saveLogFile
{
    NSFileHandle *logHandle = [NSFileHandle fileHandleForReadingAtPath:_logFilePath];
	if (ddLogLevel >= LOG_LEVEL_DETAIL) {
		unsigned long long logFileSize = [logHandle seekToEndOfFile];
		NSInteger backup = 2000;  //how much to log
		if (logFileSize < backup) backup = (NSInteger)logFileSize;
		[logHandle seekToFileOffset:(logFileSize-backup)];
		NSData *tailOfFile = [logHandle readDataOfLength:backup];
		if (tailOfFile.length > 0) {
			NSString * logString = [[NSString alloc] initWithData:tailOfFile encoding:NSUTF8StringEncoding];
			DDLogDetail(@"logFile for task %@: %@", _taskName,  logString);
		}
	}
}


-(void) trackProcess
{
	DDLogVerbose(@"Tracking %@",_taskName);
	if (![self.task isRunning]) {
//        DDLogMajor(@"Task %@ Stopped for show %@",_taskName,_download.show.showTitle);
		NSLog(@"Finished task %@ of show %@ with completion code %d and reason %@",_taskName, _download.show.showTitle, _task.terminationStatus, (_task.terminationReason == NSTaskTerminationReasonUncaughtSignal) ? @"uncaught signal" : @"exit");
//		_download.processProgress = 1.0;
//		[[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationProgressUpdated object:nil];
		if (_task.terminationReason == NSTaskTerminationReasonUncaughtSignal || _task.terminationStatus != _successfulExitCode) {
			[self cleanUp];
			_nextTaskChain = nil;
			if (!_download.isCanceled) [_download rescheduleShowWithDecrementRetries:@YES];
		} else {
			if (_completionHandler) {
				_completionHandler();
			}
			[self cleanUp];
			if (_nextTaskChain) {
				self.download.activeTaskChain = _nextTaskChain;
				[_nextTaskChain run];
			}
		}
	} else {
		double newProgressValue = -1;
		int sizeOfFileSample = 100;
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
            }
			if (newProgressValue > _download.processProgress) {
				_download.processProgress = newProgressValue;
                [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationProgressUpdated object:nil];
			}
		}
		[self performSelector:@selector(trackProcess) withObject:nil afterDelay:0.5];
	}
}

-(double)progressValueWithRx:(NSString *)data
{
//    NSRegularExpression *percents = [NSRegularExpression regularExpressionWithPattern:@"(\\d+)%" options:NSRegularExpressionCaseInsensitive error:nil];
    NSArray *values = nil;
    NSLog(@"tracking using data %@",data);
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
    desc = [desc stringByAppendingFormat:@"\nbasename = %@",_baseName];
    desc = [desc stringByAppendingFormat:@"\noutputFilePath = %@",_outputFilePath];
    desc = [desc stringByAppendingFormat:@"\nlogFilePath = %@",_logFilePath];
    desc = [desc stringByAppendingFormat:@"\nerrorFilePath = %@",_errorFilePath];
    desc = [desc stringByAppendingFormat:@"\nFile Handles: output: %p; error: %p, logFileRead:%p, logFileWrite:%p ",_outputFileHandle, _errorFileHandle, _logFileReadHandle, _logFileWriteHandle];
    desc = [desc stringByAppendingFormat:@"\nTracking RegEx = %@",_trackingRegEx];
    desc = [desc stringByAppendingFormat:@"\n%@ completionHandler",_completionHandler ? @"Has" : @"Does not have"];
    desc = [desc stringByAppendingFormat:@"\n%@ progressCalc",_progressCalc ? @"Has" : @"Does not have"];
    desc = [desc stringByAppendingFormat:@"\n%@ startupHandler",_startupHandler ? @"Has" : @"Does not have"];
    desc = [desc stringByAppendingFormat:@"\n%@ a following task chain",_nextTaskChain ? @"Has" : @"Does not have"];
    return desc;
}

#pragma mark - Task Mapping Functions

-(void)setLaunchPath:(NSString *)path
{
    [_task setLaunchPath:path];
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
    if (_startupHandler) {
        _startupHandler();
    }
    [_task launch];
    _pid = [_task processIdentifier];
    [self trackProcess];
}

-(void)terminate
{
    [_task terminate];
}

-(void)interrupt
{
    [_task interrupt];
}

-(void)suspend
{
    [_task suspend];
}

-(void)waitUntilExit
{
    [_task waitUntilExit];
}

-(BOOL)isRunning
{
    return [_task isRunning];
}

-(void)dealloc
{
    if (_pid && !kill(_pid, 0)) {
        DDLogVerbose(@"Killing process %@",_taskName);
        kill(_pid , SIGKILL);
    }
    _task = nil;
	[self cleanUp];
}

@end
