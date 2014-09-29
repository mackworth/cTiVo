//
//  NSString+Helpers.m
//  cTiVo
//
//  Created by Scott Buchanan on 6/1/13.
//  Copyright (c) 2013 cTiVo. All rights reserved.
//

#import "NSString+Helpers.h"

@implementation NSString (Helpers)

-(BOOL)contains:(NSString *)string
{
    BOOL retValue = NO;
    NSRange r = [self rangeOfString:string];
    if (r.location != NSNotFound) {
        retValue = YES;
    }
    return retValue;    
}

-(BOOL)startsWith:(NSString *)string
{
    BOOL retValue = NO;
    NSRange r = [self rangeOfString:string];
    if (r.location == 0) {
        retValue = YES;
    }
    return retValue;
}

+ (NSString *)stringFromTimeInterval:(NSTimeInterval)interval {
    NSInteger ti = (NSInteger)interval;
    NSInteger seconds = ti % 60;
    NSInteger minutes = (ti / 60) % 60;
    NSInteger hours = (ti / 3600);
    if (hours > 0 || minutes >= 10) {
        return [NSString stringWithFormat:@"%02ld:%02ld", (long)hours, (long)minutes];
    } else {
        return [NSString stringWithFormat:@"%02ld:%02ld:%02ld", (long)hours, (long)minutes, (long)seconds];
    }
}

+ (NSString *)stringFromBytesPerSecond: (double) speed {
    if (speed >= 1000000000) {
        return[NSString stringWithFormat:@"%0.1f GBps",speed/(1000000000.0)];
    } else if (speed >= 10000000) {
        return[NSString stringWithFormat:@"%0.0f MBps",speed/(1000000.0)];
    } else if (speed >= 1000000) {
        return[NSString stringWithFormat:@"%0.1f MBps",speed/(1000000.0)];
    } else if (speed >= 10000) {
        return[NSString stringWithFormat:@"%0.0f KBps",speed/(1000.0)];
    } else if (speed >= 1000) {
        return[NSString stringWithFormat:@"%0.1f KBps",speed/(1000.0)];
    } else if (speed > 0) {
        return[NSString stringWithFormat:@"%0.0f Bps",(speed) ];
    } else {
        return @"-";
    }
}


@end
