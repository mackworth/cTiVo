//
//  NSString+RFC3339Date.m
//  cTiVo
//
//  Created by Hugh Mackworth on 2/26/13.
//  Copyright (c) 2013 Scott Buchanan. All rights reserved.
//

#import "NSString+RFC3339Date.h"

@implementation NSString (RFC3339Date)

-(NSDate *)dateForRFC3339DateTimeString
// Returns a  date  that corresponds to the
// specified RFC 3339 date time string. Note that this does not handle
// all possible RFC 3339 date time strings, just one of the most common
// styles.
{
    static NSDateFormatter *    sRFC3339DateFormatter;
    NSDate *                    date;
	
    // If the date formatters aren't already set up, do that now and cache them
    // for subsequence reuse.
	
    if (sRFC3339DateFormatter == nil) {
        NSLocale *enUSPOSIXLocale;
		
        sRFC3339DateFormatter = [[NSDateFormatter alloc] init];
		
        enUSPOSIXLocale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
		
        [sRFC3339DateFormatter setLocale:enUSPOSIXLocale];
        [sRFC3339DateFormatter setDateFormat:@"yyyy'-'MM'-'dd'T'HH':'mm':'ss'Z'"];
        [sRFC3339DateFormatter setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];
    }
	
    // Convert the RFC 3339 date time string to an NSDate.
    // Then convert the NSDate to a user-visible date string.
	
 	
    date = [sRFC3339DateFormatter dateFromString:self];
	return date;
}


@end
