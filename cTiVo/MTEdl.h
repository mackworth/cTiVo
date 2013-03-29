//
//  MTEdl.h
//  SRT_EDL_TEST
//
//  Created by Scott Buchanan on 3/28/13.
//  Copyright (c) 2013 Fawkesconsulting LLC. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface MTEdl : NSObject

#define kMinEdlLength 5

@property (nonatomic) double startTime, endTime;
@property (nonatomic) int edlType;
@property (nonatomic) double offset;

+(MTEdl *)edlFromString:edlString;

@end
