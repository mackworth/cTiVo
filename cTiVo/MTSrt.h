//
//  MTSrt.h
//  SRT_EDL_TEST
//
//  Created by Scott Buchanan on 3/28/13.
//  Copyright (c) 2013 Fawkesconsulting LLC. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface MTSrt : NSObject

@property (nonatomic) double startTime, endTime;
@property (nonatomic, retain) NSString * caption;

-(NSString *)formatedSrt:(int)count;

@end
