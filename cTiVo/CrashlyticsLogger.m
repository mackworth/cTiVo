//  CrashlyticsLogger.m
//
//  Created by Simons, Mike on 5/16/13.
//  Copyright (c) 2013 TechSmith. All rights reserved.
//

#import "CrashlyticsLogger.h"
#ifndef DEBUG
@import Firebase;
#endif

@implementation CrashlyticsLogger

-(void) logMessage:(DDLogMessage *) logMessage {
#ifndef DEBUG
	NSString *logMsg = logMessage->_message;
	if (_logFormatter) {
		logMsg = [_logFormatter formatLogMessage:logMessage];
	}
	
	if (logMsg) {
		[[FIRCrashlytics crashlytics] log:logMsg];
	}
#endif
}


+(CrashlyticsLogger*) sharedInstance {
	static dispatch_once_t pred = 0;
	static CrashlyticsLogger *_sharedInstance = nil;
	
	dispatch_once(&pred, ^{
		_sharedInstance = [[self alloc] init];
	});
	
	return _sharedInstance;
}

@end
