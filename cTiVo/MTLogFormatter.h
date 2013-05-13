//
//  MTLogFormatter.h
//  cTiVo
//
//  Created by Hugh Mackworth on 5/11/13.
//  Copyright (c) 2013 cTiVo. All rights reserved.
//

#import <Foundation/Foundation.h>
@protocol DDLogFormatter;

@interface MTLogFormatter : NSObject<DDLogFormatter> {
	NSDateFormatter *dateFormatter;
	NSCalendar *calendar;
	NSUInteger calendarUnitFlags;
}
@end
