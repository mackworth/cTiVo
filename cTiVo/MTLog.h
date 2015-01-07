#import "DDLog.h"

// We want to use the following log levels:
//
// Fatal
// Error
// Warn
// Notice
// Info
// Debug
//
// All we have to do is undefine the default values,
// and then simply define our own however we want.

// First undefine the default stuff we don't want to use.

#undef LOG_FLAG_ERROR
#undef LOG_FLAG_WARN
#undef LOG_FLAG_INFO
#undef LOG_FLAG_DEBUG
#undef LOG_FLAG_VERBOSE

#undef LOG_LEVEL_ERROR
#undef LOG_LEVEL_WARN
#undef LOG_LEVEL_INFO
#undef LOG_LEVEL_DEBUG
#undef LOG_LEVEL_VERBOSE

#undef LOG_ERROR
#undef LOG_WARN
#undef LOG_INFO
#undef LOG_DEBUG
#undef LOG_VERBOSE

#undef DDLogError
#undef DDLogWarn
#undef DDLogInfo
#undef DDLogDebug
#undef DDLogVerbose

#undef DDLogCError
#undef DDLogCWarn
#undef DDLogCInfo
#undef DDLogCDebug
#undef DDLogCVerbose

/* Now define everything how we want it
ERROR => REPORT
WARN ==> MAJOR
INFO ==> DETAIL

Error ==> Report
Warn ==> Major
Info ==> Detail

VERBOSE is reused
*/

#define LOG_FLAG_REPORT   (1 << 0)  // 0...00001
#define LOG_FLAG_MAJOR    (1 << 1)  // 0...00010
#define LOG_FLAG_DETAIL    (1 << 2)  // 0...00100
#define LOG_FLAG_VERBOSE   (1 << 3)  // 0...01000

#define LOG_LEVEL_REPORT   (LOG_FLAG_REPORT  ) // 0...00001
#define LOG_LEVEL_MAJOR    (LOG_FLAG_MAJOR   | LOG_LEVEL_REPORT ) // 0...00011
#define LOG_LEVEL_DETAIL    (LOG_FLAG_DETAIL   | LOG_LEVEL_MAJOR) // 0...00111
#define LOG_LEVEL_VERBOSE   (LOG_FLAG_VERBOSE | LOG_LEVEL_DETAIL  ) // 0...01111

#define LOG_REPORT   (ddLogLevel & LOG_FLAG_REPORT )
#define LOG_MAJOR    (ddLogLevel & LOG_FLAG_MAJOR  )
#define LOG_DETAIL  (ddLogLevel & LOG_FLAG_DETAIL)
#define LOG_VERBOSE   (ddLogLevel & LOG_FLAG_VERBOSE  )

#define DDLogReport(frmt, ...)    SYNC_LOG_OBJC_MAYBE(ddLogLevel, LOG_FLAG_REPORT,  0, frmt, ##__VA_ARGS__)
#define DDLogMajor(frmt, ...)    ASYNC_LOG_OBJC_MAYBE(ddLogLevel, LOG_FLAG_MAJOR,   0, frmt, ##__VA_ARGS__)
#define DDLogDetail(frmt, ...)  ASYNC_LOG_OBJC_MAYBE(ddLogLevel, LOG_FLAG_DETAIL, 0, frmt, ##__VA_ARGS__)
#define DDLogVerbose(frmt, ...)  ASYNC_LOG_OBJC_MAYBE(ddLogLevel, LOG_FLAG_VERBOSE, 0, frmt, ##__VA_ARGS__)

#define DDLogCReport(frmt, ...)   SYNC_LOG_C_MAYBE(ddLogLevel, LOG_FLAG_REPORT,  0, frmt, ##__VA_ARGS__)
#define DDLogCMajor(frmt, ...)   ASYNC_LOG_C_MAYBE(ddLogLevel, LOG_FLAG_MAJOR,   0, frmt, ##__VA_ARGS__)
#define DDLogCDetail(frmt, ...)   ASYNC_LOG_C_MAYBE(ddLogLevel, LOG_FLAG_DETAIL,   0, frmt, ##__VA_ARGS__)
#define DDLogCVerbose(frmt, ...)  ASYNC_LOG_C_MAYBE(ddLogLevel, LOG_FLAG_VERBOSE,  0, frmt, ##__VA_ARGS__)

#define __DDLOGHERE__  static int ddLogLevel = LOG_LEVEL_REPORT; + (int)ddLogLevel { return ddLogLevel; }+ (void)ddSetLogLevel:(int)logLevel {ddLogLevel = logLevel;}

@interface DDLog (UserDefaults)
+(void)setAllClassesLogLevelFromUserDefaults: (NSString *)defaultsKey;
+ (void) writeAllClassesLogLevelToUserDefaults;
+(void)setAllClassesLogLevel: (int) debugLevel;

@end
