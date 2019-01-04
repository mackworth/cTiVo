//
//  NSString+Helpers.h
//  cTiVo
//
//  Created by Scott Buchanan on 6/1/13.
//  Copyright (c) 2013 cTiVo. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NSString (Helpers)

-(BOOL)contains:(NSString *)string;

+ (NSString *)stringFromTimeInterval:(NSTimeInterval)interval;

+ (NSString *)stringFromBytesPerSecond: (double) speed;

- (BOOL) isEquivalentToPath: (NSString *) path;

+(NSString *) stringWithEndOfFile:(NSString *) path;

-(BOOL) hasCaseInsensitivePrefix: (NSString *) prefix;

-(NSString *) removeParenthetical;

-(NSString *) escapedQueryString;

-(NSString *) pathForParentDirectoryWithName: (NSString *) parent;
//traverses up chain looking for directory "parent"; if not found, returns self.

//for these two, assumed that self is a filename and we're getting/setting filesystem attributes
-(NSString *) getXAttr:(NSString *) key;

-(void) setXAttr:(NSString *) key toValue:(NSString *) value;

-(NSString *) maskSerialNumber: (NSString *) TSN;

@end
