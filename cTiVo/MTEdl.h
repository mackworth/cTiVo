//
//  MTEdl.h
//  SRT_EDL_TEST
//
//  Created by Scott Buchanan on 3/28/13.
//  Copyright (c) 2013 Fawkesconsulting LLC. All rights reserved.
//

#import <Foundation/Foundation.h>
#include "mp4v2.h"

@interface MTEdl : NSObject <NSSecureCoding>

#define kMinEdlLength 5

@property (nonatomic) double startTime, endTime;
@property (nonatomic) int edlType;
@property (nonatomic) double offset;

@end

@interface NSArray (MTEDLList)

+(NSArray *)getFromEDLFile:(NSString *)edlFile;
-(BOOL) writeToEDLFile:(NSString *) edlFile;

-(BOOL)addAsChaptersToMP4File: (MP4FileHandle *) encodedFile forShow:(NSString *) showName withLength:(double) length keepingCommercials: (BOOL) keepCommercials; 

+(NSArray *)edlListFromSegments:(NSArray <NSNumber *> *) segments andStartPoints:(NSArray <NSNumber *> *) startPoints;

@end

