//
//  MTSrt.m
//  SRT_EDL_TEST
//
//  Created by Scott Buchanan on 3/28/13.
//  Copyright (c) 2013 Fawkesconsulting LLC. All rights reserved.
//

#import "MTSrt.h"

@implementation MTSrt

__DDLOGHERE__

-(NSString *)description
{
    return [NSString stringWithFormat:@"Start = %lf, End = %lf\n%@",self.startTime, self.endTime, self.caption];
}

+(MTSrt *) srtFromString: srtString {
	NSArray *lines = [srtString componentsSeparatedByString:@"\r\n"];
	if (lines.count < 3) {
		DDLogReport(@"Bad SRT: no enough lines: %@",srtString);
		return nil;
	}
	NSArray *times = [lines[1] componentsSeparatedByString:@" --> "];
	if (times.count < 2) {
		DDLogReport(@"Bad SRT: no enough times: %@",srtString);
		return nil;
	}
	NSArray *hmsStart = [times[0] componentsSeparatedByString:@":"];
	if (hmsStart.count < 3) {
		DDLogReport(@"Bad SRT: start time bad: %@",srtString);
		return nil;
	}
	double secondsStart = [[hmsStart[2] stringByReplacingOccurrencesOfString:@"," withString:@"."] doubleValue];
	secondsStart += 60.0 * ([hmsStart[0] doubleValue] * 60.0 + [hmsStart[1] doubleValue]);
	
	NSArray *hmsEnd = [times[1] componentsSeparatedByString:@":"];
	if (hmsEnd.count < 3) {
		DDLogReport(@"Bad SRT: end time bad: %@",srtString);
		return nil;
	}
	double secondsEnd = [[hmsEnd[2] stringByReplacingOccurrencesOfString:@"," withString:@"."] doubleValue];
	secondsEnd += 60.0 * ([hmsEnd[0] doubleValue] * 60.0 + [hmsEnd[1] doubleValue]);
	if (secondsStart >= secondsEnd ) {
		DDLogReport(@"Bad SRT: inaccurate times: %@", srtString);
		return nil;
	}
	
	MTSrt * newSrt =[[MTSrt new] autorelease];
	newSrt.startTime = secondsStart;
	newSrt.endTime = secondsEnd;
	newSrt.caption = @"";

	NSArray * captionArray = [lines subarrayWithRange:NSMakeRange(2,lines.count-2)];
	newSrt.caption = [captionArray componentsJoinedByString:@"\r\n"];

	return newSrt;
}

-(NSString *) secondsToString: (double) seconds {
   int hrs = seconds/3600.0;
    int min = (seconds - hrs * 3600)/60;
    float sec = seconds - hrs * 3600 - min * 60;
    NSString *result = [NSString stringWithFormat:@"%02d:%02d:%06.3f",hrs,min,sec];
    result = [result stringByReplacingOccurrencesOfString:@"." withString:@","];
	return result;
}

-(NSString *)formatedSrt:(int)count
{
    NSString * startString = [self secondsToString:_startTime];
    NSString * endString = [self secondsToString:_endTime];
	
	NSString *output = [NSString stringWithFormat:@"%d\r\n%@ --> %@\r\n%@\r\n\r\n",
													count,
													startString,
													endString,
													_caption];
							

    return output;
    
}

@end
