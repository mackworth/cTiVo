//
//  MTSrt.m
//  SRT_EDL_TEST
//
//  Created by Scott Buchanan on 3/28/13.
//  Copyright (c) 2013 Fawkesconsulting LLC. All rights reserved.
//

#import "MTSrt.h"

@implementation MTSrt

-(NSString *)description
{
    return [NSString stringWithFormat:@"Start Time = %lf, End Time = %lf\n%@",self.startTime, self.endTime, self.caption];
}

-(NSString *)formatedSrt:(int)count
{
    NSString *output = [NSString stringWithFormat:@"%d\r\n",count];
    int startHrs = _startTime/3600.0;
    int startMins = (_startTime - startHrs * 3600)/60;
    float startSec = _startTime - startHrs * 3600 - startMins * 60;
    NSString *startSecString = [NSString stringWithFormat:@"%.3f",startSec];
    startSecString = [startSecString stringByReplacingOccurrencesOfString:@"." withString:@","];
    
    int endHrs = _endTime/3600.0;
    int endMins = (_endTime - endHrs * 3600)/60;
    float endSec = _endTime - endHrs * 3600 - endMins * 60;
    NSString *endSecString = [NSString stringWithFormat:@"%.3f",endSec];
    endSecString = [endSecString stringByReplacingOccurrencesOfString:@"." withString:@","];
    output = [output stringByAppendingFormat:@"%d:%d:%@ --> %d:%d:%@\r\n%@\r\n",startHrs, startMins, startSecString,endHrs, endMins, endSecString,_caption];
    

    return output;
    
}

@end
