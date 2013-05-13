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
		calendar = [NSCalendar autoupdatingCurrentCalendar];
		
		calendarUnitFlags = 0;
		calendarUnitFlags |= NSYearCalendarUnit;
		calendarUnitFlags |= NSMonthCalendarUnit;
		calendarUnitFlags |= NSDayCalendarUnit;
		calendarUnitFlags |= NSHourCalendarUnit;
		calendarUnitFlags |= NSMinuteCalendarUnit;
		calendarUnitFlags |= NSSecondCalendarUnit;
//		if (aDateFormatter)
//		{
//			dateFormatter = aDateFormatter;
//		}
//		else
//		{
//			dateFormatter = [[NSDateFormatter alloc] init];
//			[dateFormatter setDateFormat:@"yyyy/MM/dd HH:mm:ss:SSS"];
//		}
	}
	return self;
}

- (NSString *)formatLogMessage:(DDLogMessage *)logMessage
{
	//NSString *dateAndTime = [dateFormatter stringFromDate:(logMessage->timestamp)];
	
	// Calculate timestamp.
	// The technique below is faster than using NSDateFormatter.
	
	NSDateComponents *components = [calendar components:calendarUnitFlags fromDate:logMessage->timestamp];
	
	NSTimeInterval epoch = [logMessage->timestamp timeIntervalSinceReferenceDate];
	int milliseconds = (int)((epoch - floor(epoch)) * 1000);
	
	char ts[24];
	int len;
	len = snprintf(ts, 24, "%04ld-%02ld-%02ld %02ld:%02ld:%02ld:%03d", // yyyy-MM-dd HH:mm:ss:SSS
				   (long)components.year,
				   (long)components.month,
				   (long)components.day,
				   (long)components.hour,
				   (long)components.minute,
				   (long)components.second, milliseconds);
	return [NSString stringWithFormat:@"%s %@>%s@%d>%@", ts, DDExtractFileNameWithoutExtension(logMessage->file,NO),logMessage->function, logMessage->lineNumber, logMessage->logMsg];
}

@end
