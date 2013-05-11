//
//  MTLogFormatter.m
//  cTiVo
//
//  Created by Hugh Mackworth on 5/11/13.
//  Copyright (c) 2013 cTiVo. All rights reserved.
//
#import "DDLog.h"
#import "MTLogFormatter.h"

@implementation MTLogFormatter

- (id)init
{
	return [self initWithDateFormatter:nil];
}

- (id)initWithDateFormatter:(NSDateFormatter *)aDateFormatter
{
	if ((self = [super init]))
	{
		if (aDateFormatter)
		{
			dateFormatter = aDateFormatter;
		}
		else
		{
			dateFormatter = [[NSDateFormatter alloc] init];
			[dateFormatter setFormatterBehavior:NSDateFormatterBehavior10_4]; // 10.4+ style
			[dateFormatter setDateFormat:@"yyyy/MM/dd HH:mm:ss:SSS"];
		}
	}
	return self;
}


- (NSString *)formatLogMessage:(DDLogMessage *)logMessage
{
	NSString *dateAndTime = [dateFormatter stringFromDate:(logMessage->timestamp)];
    return [NSString stringWithFormat:@"%@ %s>%s@%d>%@", dateAndTime, logMessage->file,logMessage->function, logMessage->lineNumber, logMessage->logMsg];
}

@end
