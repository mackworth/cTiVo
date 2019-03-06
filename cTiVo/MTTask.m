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
#import "NSArray+Map.h"
#import "NSString+Helpers.h"

#ifndef DEBUG
#import "Crashlytics/Crashlytics.h"
#endif

@interface MTTask ()
{
    BOOL launched;
}
@property (strong, nonatomic) NSTask *task;

@property (strong, nonatomic) NSString	*taskName,
//                                        *baseName,
//										*outputFilePath,
*logFilePath,
*errorFilePath;

@property (strong, nonatomic) NSFileHandle	*outputFileHandle,
*errorFileHandle,
*logFileWriteHandle,
*logFileReadHandle;

@property (strong, nonatomic) NSRegularExpression *trackingRegEx; //not currently used

@property (atomic) BOOL taskRunning;

@property int pid;

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
    if (@available (macOS 10.10, *)) {
        if ([mTTask.task respondsToSelector:@selector(setQualityOfService:)]) {  //os10.10 and later
            mTTask.task.qualityOfService = NSQualityOfServiceUtility;
        }
    }
    NSString * tmpDir = download.tmpDirectory;
    if (tmpDir) {
        mTTask.task.currentDirectoryPath = tmpDir;  //just protective
    } else {
        DDLogReport(@"Temp dir not found!");
    }
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
        _taskRunning = NO;  //need to be sure we've processed before reporting to taskChain
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
    NSError * error = nil;
    if (self.download) {
        self.logFilePath = [NSString stringWithFormat:@"%@/%@%@.txt",self.download.tmpDirectory,taskName,self.download.baseFileName];
        if (![[NSData data] writeToFile:self.logFilePath options:0 error:&error]) {
            DDLogReport(@"Could not create logfile at %@: %@",_logFilePath, error);
        }
        self.logFileWriteHandle = [NSFileHandle fileHandleForWritingAtPath:_logFilePath];
        self.logFileReadHandle	= [NSFileHandle fileHandleForReadingAtPath:_logFilePath];
        self.errorFilePath = [NSString stringWithFormat:@"%@/%@%@.err",self.download.tmpDirectory,taskName,self.download.baseFileName];
        if (![[NSData data] writeToFile:self.errorFilePath options:0 error:&error]) {
            DDLogReport(@"Could not create errfile at %@:%@",_errorFilePath, error);
        }
        self.errorFileHandle = [NSFileHandle fileHandleForWritingAtPath:_errorFilePath];
        
        if (self.logFileWriteHandle) {
            [self setStandardOutput:self.logFileWriteHandle];
        } else {
            DDLogReport(@"%@ Could not write logfile at %@",taskName, _logFilePath);
        }
        if (self.logFileReadHandle) {
            [self setStandardInput:self.logFileReadHandle];
        } else {
            DDLogReport(@"%@ Could not read logfile at %@",taskName, _logFilePath);
        }
        if (self.errorFileHandle) {
            [self setStandardError:self.errorFileHandle];
        } else {
            DDLogReport(@"%@ Could not write error file at %@",taskName, _errorFilePath);
        }
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

	if (ddLogLevel & LOG_FLAG_DETAIL) {
		usleep (100);
		[self saveLogFile];
	}
	//following line has important side effect that it lets the task do whatever it needs to do to terminate before killing it dead in dealloc
	[self performSelector:@selector(doNothing) withObject:self afterDelay:2.0];
}

-(void) doNothing {
	
}

-(void)cleanUp
{
	self.taskRunning = NO;
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

-(void) reportOldProcessor {
    NSString * title = @"Your processor may be too old";
    if (_task.launchPath.length > 0) {
        title = [title stringByAppendingString: @" for "];
        title = [title stringByAppendingString: [_task.launchPath lastPathComponent]];
    }

    NSString * subtitle = @"You may need '10.7' version of cTiVo";
    [tiVoManager notifyWithTitle: title
                      subTitle: subtitle ];
    [self.download cancel];
}

-(void) saveLogFileType:(NSString *) type fromPath: (NSString *) path {
    NSString * logString = [NSString stringWithEndOfFile:path ];
    if ([logString contains:@"Exit 132"]) {
        [self reportOldProcessor];
    }
    if (logString.length > 0) {
        DDLogReport(@"%@File for task %@: %@",type, _taskName,  [logString maskMediaKeys]);
    } else {
        DDLogDetail(@"%@File for task %@ was empty", type, _taskName);
    }
}

-(void) saveLogFile
{
    [self saveLogFileType:@"log" fromPath:_logFilePath];
    [self saveLogFileType:@"err" fromPath:_errorFilePath];
}

-(void)completeProcess
{
	_task.terminationHandler = NULL; // in case timer went off before handler
    DDLogMajor(@"Finished task %@ of show %@ with completion code %d and reason %@",_taskName, _download.show.showTitle, _task.terminationStatus,[self reasonForTermination]);
    if (self.taskFailed) {
        if (_task.terminationStatus == 0x4 && _task.terminationReason == NSTaskTerminationReasonUncaughtSignal) {
            [self reportOldProcessor];
        }
		[self failedTaskCompletion];
    } else {
        if (_completionHandler) {
			if(!_completionHandler()) { //The task actually failed
				_completionHandler = nil;
				[self failedTaskCompletion];
				return;
			} else {
				_completionHandler = nil;
			}
        }
        [self cleanUp];
    }
}

-(void)failedTaskCompletion
{
	if (!_download.isCanceled || (ddLogLevel & LOG_FLAG_DETAIL)) {
		DDLogReport(@"Task %@ failed",self.taskName);
    	[self saveLogFile];
	}
	[self cleanUp];

	if (!_download.isCanceled && _shouldReschedule){
		_myTaskChain.beingRescheduled = YES;
		[_download rescheduleDownload];
    } else {
        // a non-critical task; so just continue
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
        if (_trackingRegEx || _progressCalc) {
            double newProgressValue = -1;
            unsigned long long logFileSize = [self.logFileReadHandle seekToEndOfFile];
            if (logFileSize > 20) {
                NSUInteger sizeOfFileSample = 256;
                unsigned long long startPoint = logFileSize-sizeOfFileSample;
                if (logFileSize < sizeOfFileSample) {
                    startPoint = 0;
                    sizeOfFileSample = logFileSize;
                }
                [self.logFileReadHandle seekToFileOffset:(startPoint)];
                NSData *tailOfFile = [self.logFileReadHandle readDataOfLength:sizeOfFileSample];
                NSString *data = [[NSString alloc] initWithData:tailOfFile encoding:NSUTF8StringEncoding];
                if (_trackingRegEx) {
                    newProgressValue = [self progressValueWithRx:data];
                }
                if (_progressCalc) {
                    newProgressValue = _progressCalc(data);
                }
                if (newProgressValue != -1) {
                    DDLogVerbose(@"New progress value for %@ is %0.1lf%%",_taskName,newProgressValue*100);
                    if ((newProgressValue != _download.processProgress) && (newProgressValue != 0)) {
                        _download.processProgress = newProgressValue;
                    }
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

    //try to provide argument list in cut/paste form for bash
    NSCharacterSet *specialCharSet = [NSCharacterSet characterSetWithCharactersInString:@" $\"\\"];
    // space, dollar sign, quote, backslash

    NSArray * arguments = [_task.arguments mapObjectsUsingBlock:^id(NSString * argument, NSUInteger idx) {
        if (argument.length ==0) {
            return @"\"\"";
        }
        if ([argument rangeOfCharacterFromSet:specialCharSet].length) {
            return [NSString stringWithFormat:@"'%@'",argument]; //surround with 's; if ' also, then fails!
        }
        if ([argument contains:@"'"]) {
            return [NSString stringWithFormat:@"\"%@\"", argument]; //if single quote, surround with double.

        }
        return argument;
    }];
    desc = [desc stringByAppendingFormat:@"\nLaunchPath: %@ %@", _task.launchPath, [[arguments componentsJoinedByString:@" "] maskMediaKeys]] ;
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
    desc = [desc stringByAppendingFormat:@"\nDirectoryPath: %@",_task.currentDirectoryPath ];
    desc = [desc stringByAppendingFormat:@"\nEnvironment: %@",_task.environment ];

//    desc = [desc stringByAppendingFormat:@"\n%@ a following task chain",_nextTaskChain ? @"Has" : @"Does not have"];
    return desc;
}

#pragma mark - Task Mapping Functions

-(void)setLaunchPath:(NSString *)path
{
    if (path.length > 0) {
        BOOL isDir = NO;
        if ([[NSFileManager defaultManager]  fileExistsAtPath:path isDirectory:&isDir ]) {
            if (!isDir && [[NSFileManager defaultManager]  isExecutableFileAtPath:path]) {
                [_task setLaunchPath:path];
            } else {
                DDLogReport(@"Error: %@ file at path %@ not marked as executable", self.taskName, path);
            }
        } else {
            DDLogReport(@"Error: no %@ file at %@", self.taskName, path);
        }
    } else {
        DDLogReport(@"Error: no executable path for %@ ", self.taskName);
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

-(id)standardInput
{
	return _task.standardInput;
}


-(void)setStandardInput:(id)stdi
{
    [_task setStandardInput:stdi];
}

-(void)setStandardError:(id)stde
{
    [_task setStandardError:stde];
}

-(BOOL)launch
{
    if (!_task.launchPath) {
        DDLogReport(@"Error: no executable for %@; cannot launch", self.taskName);
       return NO;
    }
    BOOL shouldLaunch = YES;
    if (_startupHandler) {
        shouldLaunch = _startupHandler();
    }
    if (shouldLaunch) {
        DDLogDetail(@"Launching: %@",self);
        NSFileManager * fm = [NSFileManager defaultManager];
        NSString * errorString = nil;
        if ([fm fileExistsAtPath:_task.currentDirectoryPath]) {
            errorString = [NSString stringWithFormat: @"current folder %@ exists", _task.currentDirectoryPath];
        } else {
            DDLogReport(@"Error on launch: No current directory %@", _task.currentDirectoryPath);
            NSError * error = nil;
           [fm createDirectoryAtPath:_task.currentDirectoryPath withIntermediateDirectories:YES  attributes: nil error: &error];
            errorString = error.localizedDescription;
        }
		__weak __typeof__(self) weakSelf = self;
		_task.terminationHandler = ^(NSTask * _Nonnull task) {
			__typeof__(self) strongSelf = weakSelf; if (!strongSelf) return;
			dispatch_async(dispatch_get_main_queue(), ^{
				[NSObject cancelPreviousPerformRequestsWithTarget:strongSelf selector:@selector(trackProcess) object:nil ]; //this has to be on main queue
				DDLogDetail(@"%@ task terminated. Status: %@",strongSelf.taskName, @(strongSelf.task.terminationStatus));
				[strongSelf trackProcess];
			});
		};
        @try {
            [_task launch];
            launched = YES;
            self.taskRunning = YES;
            _pid = [_task processIdentifier];
            [self trackProcess];
        } @catch (NSException *exception) {
            NSString * desc = self.description;
            DDLogReport(@"Error on launch: %@ for %@; cannot launch: %@",  [exception reason], self.taskName, desc);
#ifndef DEBUG
            NSMutableDictionary * info = [NSMutableDictionary dictionary];
            [info setValue:exception.name forKey:@"MTExceptionName"];
            [info setValue:exception.reason forKey:@"MTExceptionReason"];
            [info setValue:exception.callStackReturnAddresses forKey:@"MTExceptionCallStackReturnAddresses"];
            [info setValue:exception.callStackSymbols forKey:@"MTExceptionCallStackSymbols"];
            [info setValue:exception.userInfo forKey:@"MtExceptionUserInfo"];
            [info setValue:errorString forKey:@"MtExceptionTmpError"];
            [info setValue:desc forKey:@"MTExceptionTaskInfo"];

            NSError *error = [[NSError alloc] initWithDomain:@"MTExceptionDomain" code:1 userInfo:info];
            [[Crashlytics sharedInstance] recordError:error];
#endif
            return NO;
        }
    } else {
        if (_completionHandler) {
            _completionHandler();
        }
    }
    return shouldLaunch;
}

-(void)terminate
{
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
    return self.taskRunning;
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
