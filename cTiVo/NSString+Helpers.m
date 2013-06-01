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

@end
