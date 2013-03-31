//
//  MTEdl.m
//  SRT_EDL_TEST
//
//  Created by Scott Buchanan on 3/28/13.
//  Copyright (c) 2013 Fawkesconsulting LLC. All rights reserved.
//

#import "MTEdl.h"

@implementation MTEdl

__DDLOGHERE__

-(NSString *)description
{
    return [NSString stringWithFormat:@"Start = %lf, End  = %lf, type=%d, offset = %lf",self.startTime, self.endTime, self.edlType,self.offset];
}

+(MTEdl *)edlFromString:edlString {
	NSArray *items = [edlString componentsSeparatedByString:@"\t"];
	if (items.count < 3) {
		DDLogReport(@"Bad EDL: not enough items: %@", edlString);
		return nil;
	}
	MTEdl *newEdl =  [[MTEdl new] autorelease];
	newEdl.startTime = [items[0] doubleValue];
	newEdl.endTime = [items[1] doubleValue];
	if (newEdl.startTime >= newEdl.endTime ) {
		DDLogReport(@"Bad EDL: inaccurate times: %@", edlString);
		return nil;
	}
	newEdl.edlType = [items[2] intValue];
   return newEdl;
	}


@end
