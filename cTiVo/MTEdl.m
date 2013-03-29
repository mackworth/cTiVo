//
//  MTEdl.m
//  SRT_EDL_TEST
//
//  Created by Scott Buchanan on 3/28/13.
//  Copyright (c) 2013 Fawkesconsulting LLC. All rights reserved.
//

#import "MTEdl.h"

@implementation MTEdl

-(NSString *)description
{
    return [NSString stringWithFormat:@"Start Time = %lf, End Time = %lf, type=%d",self.startTime, self.endTime, self.edlType];
}

@end
