//
//  MTTVDBLog.m
//  cTiVo
//
//  Created by Hugh Mackworth on 8/7/22.
//  Copyright © 2022 cTiVo. All rights reserved.
//
#import "MTDDSwiftLogger.h"


@implementation MTTVDBLog

__DDLOGHERE__

#define LOG_MACRO2(isAsynchronous, lvl, flg, ctx, atag, fnct, line, frmt, ...) \
        [DDLog log : isAsynchronous                                     \
             level : lvl                                                \
              flag : flg                                                \
           context : ctx                                                \
              file : ""                                                 \
          function : fnct                                               \
              line : line                                               \
               tag : atag                                               \
            format : (frmt), ## __VA_ARGS__]

#define LOG_MAYBE2(async, lvl, flg, ctx, tag, file, fnct, line, frmt, ...) \
        do { if(lvl & flg) LOG_MACRO2(async, lvl, flg, ctx, tag, file, fnct, line, frmt, ##__VA_ARGS__); } while(0)

+(void) DSLogAlways:(NSString *) msg module: (const char *) func line: (NSInteger) line {
  LOG_MACRO2(LOG_ASYNC_ENABLED, DDLogLevelAll, DDLogFlagWarning, 0, nil, func, line, @"%@", msg);
}

+(void) DSLogReport:(NSString *) msg module: (const char *) func line: (NSInteger) line {
  LOG_MAYBE2(LOG_ASYNC_ENABLED, ddLogLevel, DDLogFlagError,   0, nil, func, line, @"%@", msg);
}

+(void) DSLogMajor:(NSString *) msg module: (const char *) func line: (NSInteger) line {
  LOG_MAYBE2(LOG_ASYNC_ENABLED, ddLogLevel, DDLogFlagWarning, 0, nil, func, line, @"%@", msg);
}

+(void) DSLogDetail:(NSString *) msg module: (const char *) func line: (NSInteger) line {
  LOG_MAYBE2(LOG_ASYNC_ENABLED, ddLogLevel, DDLogFlagInfo,    0, nil, func, line, @"%@", msg);
}

+(void) DSLogVerbose:(NSString *) msg module: (const char *) func line: (NSInteger) line {
  LOG_MAYBE2(LOG_ASYNC_ENABLED, ddLogLevel, DDLogFlagDebug,   0, nil, func, line, @"%@", msg);
}


@end
