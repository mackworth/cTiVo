//
//  MTDDSwiftLogger.h
//  cTiVo
//
//  Created by Hugh Mackworth on 8/7/22.
//  Copyright © 2022 cTiVo. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MTTVDBLog : NSObject


+(void) DSLogAlways: (NSString *) msg module: (const char *) function line: (NSInteger) line;
+(void) DSLogReport: (NSString *) msg module: (const char *) function line: (NSInteger) line;
+(void) DSLogMajor:  (NSString *) msg module: (const char *) function line: (NSInteger) line;
+(void) DSLogDetail: (NSString *) msg module: (const char *) function line: (NSInteger) line;
+(void) DSLogVerbose:(NSString *) msg module: (const char *) function line: (NSInteger) line;

@end

NS_ASSUME_NONNULL_END
