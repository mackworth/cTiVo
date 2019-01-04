//  CrashlyticsLogger.m
//
//  Created by Simons, Mike on 5/16/13.
//  Copyright (c) 2013 TechSmith. All rights reserved.
//

#import "CrashlyticsLogger.h"
#import "Crashlytics/Crashlytics.h"

@implementation CrashlyticsLogger

-(void) logMessage:(DDLogMessage *)logMessage
{
	NSString *logMsg = logMessage->_message;
	
	if (_logFormatter)
	{
		logMsg = [_logFormatter formatLogMessage:logMessage];
	}
	
	if (logMsg)
	{
		CLSLog(@"%@",logMsg); 
	}
}


+(CrashlyticsLogger*) sharedInstance
{
	static dispatch_once_t pred = 0;
	static CrashlyticsLogger *_sharedInstance = nil;
	
	dispatch_once(&pred, ^{
		_sharedInstance = [[self alloc] init];
	});
	
	return _sharedInstance;
}

@end
