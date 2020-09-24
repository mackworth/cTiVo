//
//  NSDate+Tomorrow.m
//  cTiVo
//
//  Created by Hugh Mackworth on 3/8/18.
//  Copyright © 2018 cTiVo. All rights reserved.
//

#import "NSDate+Tomorrow.h"

@implementation NSDate (Tomorrow)

-(double) secondsUntilNextTimeOfDay {
	NSCalendar *myCalendar = [NSCalendar currentCalendar];
	NSDateComponents *currentComponents = [myCalendar components:(NSCalendarUnitHour | NSCalendarUnitMinute | NSCalendarUnitSecond) fromDate:[NSDate date]];
	NSDateComponents *targetComponents = [myCalendar components:(NSCalendarUnitHour | NSCalendarUnitMinute | NSCalendarUnitSecond) fromDate:self];
	double currentSeconds = (double)currentComponents.hour * 3600.0 +(double) currentComponents.minute * 60.0 + (double) currentComponents.second;
	double targetSeconds = (double)targetComponents.hour * 3600.0 + (double)targetComponents.minute * 60.0 + (double) targetComponents.second;
	if (targetSeconds <= currentSeconds) {
		targetSeconds += 3600 * 24;
	}
	return targetSeconds - currentSeconds;
}

+(NSDate *) tomorrowAtTime: (NSInteger) minutes {
	//may be called at launch, so don't assume anything is setup
	NSUInteger units = NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay | NSCalendarUnitHour | NSCalendarUnitMinute | NSCalendarUnitSecond  ;
	NSDateComponents *comps = [[NSCalendar currentCalendar] components:units fromDate:[NSDate date]];
	comps.day = comps.day + 1;    // Add one day
	comps.hour = minutes / 60;
	comps.minute = minutes % 60;
	comps.second = 0;
	NSDate *tomorrowTime = [[NSCalendar currentCalendar] dateFromComponents:comps];
	return tomorrowTime;
}

@end
