#import <Foundation/Foundation.h>

/**
 * Welcome to Cocoa Lumberjack!
 *
 * The project page has a wealth of documentation if you have any questions.
 * https://github.com/robbiehanson/CocoaLumberjack
 *
 * If you're new to the project you may wish to read the "Getting Started" wiki.
 * https://github.com/robbiehanson/CocoaLumberjack/wiki/GettingStarted
 *
 * Otherwise, here is a quick refresher.
 * There are three steps to using the macros:
 *
 * Step 1:
 * Import the header in your implementation file:
 *
 * #import "DDLog.h"
 *
 * Step 2:
 * Define your logging level in your implementation file:
 *
 * // Log levels: off, error, warn, info, verbose
 * static const int ddLogLevel = LOG_LEVEL_VERBOSE;
 *
 * Step 3:
 * Replace your NSLog statements with DDLog statements according to the severity of the message.
 *
 * NSLog(@"Fatal error, no dohickey found!"); -> DDLogError(@"Fatal error, no dohickey found!");
 *
 * DDLog works exactly the same as NSLog.
 * This means you can pass it multiple variables just like NSLog.
 **/

@class DDLogMessage;

@protocol DDLogger;
@protocol DDLogFormatter;

/**
 * This is the single macro that all other macros below compile into.
 * This big multiline macro makes all the other macros easier to read.
 **/

#define LOG_MACRO(isAsynchronous, lvl, flg, ctx, atag, fnct, frmt, ...) \
  do { if(lvl & LOG_LEVEL_REPORT) NSLog(@"%@>%s@%d>"  frmt,THIS_FILE,fnct, __LINE__, ##__VA_ARGS__); else NSLog(frmt,##__VA_ARGS__); } while(0)

/**
 * Define the Objective-C and C versions of the macro.
 * These automatically inject the proper function name for either an objective-c method or c function.
 *
 * We also define shorthand versions for asynchronous and synchronous logging.
 **/

#define LOG_OBJC_MACRO(async, lvl, flg, ctx, frmt, ...) \
LOG_MACRO(async, lvl, flg, ctx, nil, sel_getName(_cmd), frmt, ##__VA_ARGS__)

#define LOG_C_MACRO(async, lvl, flg, ctx, frmt, ...) \
LOG_MACRO(async, lvl, flg, ctx, nil, __FUNCTION__, frmt, ##__VA_ARGS__)

#define  SYNC_LOG_OBJC_MACRO(lvl, flg, ctx, frmt, ...) \
LOG_OBJC_MACRO( NO, lvl, flg, ctx, frmt, ##__VA_ARGS__)

#define ASYNC_LOG_OBJC_MACRO(lvl, flg, ctx, frmt, ...) \
LOG_OBJC_MACRO(YES, lvl, flg, ctx, frmt, ##__VA_ARGS__)

#define  SYNC_LOG_C_MACRO(lvl, flg, ctx, frmt, ...) \
LOG_C_MACRO( NO, lvl, flg, ctx, frmt, ##__VA_ARGS__)

#define ASYNC_LOG_C_MACRO(lvl, flg, ctx, frmt, ...) \
LOG_C_MACRO(YES, lvl, flg, ctx, frmt, ##__VA_ARGS__)

/**
 * Define version of the macro that only execute if the logLevel is above the threshold.
 * The compiled versions essentially look like this:
 *
 * if (logFlagForThisLogMsg & ddLogLevel) { execute log message }
 *
 * As shown further below, Lumberjack actually uses a bitmask as opposed to primitive log levels.
 * This allows for a great amount of flexibility and some pretty advanced fine grained logging techniques.
 *
 * Note that when compiler optimizations are enabled (as they are for your release builds),
 * the log messages above your logging threshold will automatically be compiled out.
 *
 * (If the compiler sees ddLogLevel declared as a constant, the compiler simply checks to see if the 'if' statement
 *  would execute, and if not it strips it from the binary.)
 *
 * We also define shorthand versions for asynchronous and synchronous logging.
 **/

#define LOG_MAYBE(async, lvl, flg, ctx, fnct, frmt, ...) do { if(lvl & flg) LOG_MACRO(async, lvl, flg, ctx, nil, fnct, frmt, ##__VA_ARGS__); } while(0)

#define LOG_OBJC_MAYBE(async, lvl, flg, ctx, frmt, ...)  LOG_MAYBE(async, lvl, flg, ctx, sel_getName(_cmd), frmt, ##__VA_ARGS__)

#define LOG_C_MAYBE(async, lvl, flg, ctx, frmt, ...) \
LOG_MAYBE(async, lvl, flg, ctx, __FUNCTION__, frmt, ##__VA_ARGS__)

#define  SYNC_LOG_OBJC_MAYBE(lvl, flg, ctx, frmt, ...) \
LOG_OBJC_MAYBE( NO, lvl, flg, ctx, frmt, ##__VA_ARGS__)

#define ASYNC_LOG_OBJC_MAYBE(lvl, flg, ctx, frmt, ...) \
LOG_OBJC_MAYBE(YES, lvl, flg, ctx, frmt, ##__VA_ARGS__)

#define  SYNC_LOG_C_MAYBE(lvl, flg, ctx, frmt, ...) \
LOG_C_MAYBE( NO, lvl, flg, ctx, frmt, ##__VA_ARGS__)

#define ASYNC_LOG_C_MAYBE(lvl, flg, ctx, frmt, ...) \
LOG_C_MAYBE(YES, lvl, flg, ctx, frmt, ##__VA_ARGS__)

/**
 * Define versions of the macros that also accept tags.
 *
 * The DDLogMessage object includes a 'tag' ivar that may be used for a variety of purposes.
 * It may be used to pass custom information to loggers or formatters.
 * Or it may be used by 3rd party extensions to the framework.
 *
 * Thes macros just make it a little easier to extend logging functionality.
 **/

#define LOG_OBJC_TAG_MACRO(async, lvl, flg, ctx, tag, frmt, ...) \
LOG_MACRO(async, lvl, flg, ctx, tag, sel_getName(_cmd), frmt, ##__VA_ARGS__)

#define LOG_C_TAG_MACRO(async, lvl, flg, ctx, tag, frmt, ...) \
LOG_MACRO(async, lvl, flg, ctx, tag, __FUNCTION__, frmt, ##__VA_ARGS__)

#define LOG_TAG_MAYBE(async, lvl, flg, ctx, tag, fnct, frmt, ...) \
do { if(lvl & flg) LOG_MACRO(async, lvl, flg, ctx, tag, fnct, frmt, ##__VA_ARGS__); } while(0)

#define LOG_OBJC_TAG_MAYBE(async, lvl, flg, ctx, tag, frmt, ...) \
LOG_TAG_MAYBE(async, lvl, flg, ctx, tag, sel_getName(_cmd), frmt, ##__VA_ARGS__)

#define LOG_C_TAG_MAYBE(async, lvl, flg, ctx, tag, frmt, ...) \
LOG_TAG_MAYBE(async, lvl, flg, ctx, tag, __FUNCTION__, frmt, ##__VA_ARGS__)

/**
 * Define the standard options.
 *
 * We default to only 4 levels because it makes it easier for beginners
 * to make the transition to a logging framework.
 *
 * More advanced users may choose to completely customize the levels (and level names) to suite their needs.
 * For more information on this see the "Custom Log Levels" page:
 * https://github.com/robbiehanson/CocoaLumberjack/wiki/CustomLogLevels
 *
 * Advanced users may also notice that we're using a bitmask.
 * This is to allow for custom fine grained logging:
 * https://github.com/robbiehanson/CocoaLumberjack/wiki/FineGrainedLogging
 *
 * -- Flags --
 *
 * Typically you will use the LOG_LEVELS (see below), but the flags may be used directly in certain situations.
 * For example, say you have a lot of warning log messages, and you wanted to disable them.
 * However, you still needed to see your error and info log messages.
 * You could accomplish that with the following:
 *
 * static const int ddLogLevel = LOG_FLAG_REPORT | LOG_FLAG_DETAIL;
 *
 * Flags may also be consulted when writing custom log formatters,
 * as the DDLogMessage class captures the individual flag that caused the log message to fire.
 *
 * -- Levels --
 *
 * Log levels are simply the proper bitmask of the flags.
 *
 * -- Booleans --
 *
 * The booleans may be used when your logging code involves more than one line.
 * For example:
 *
 * if (LOG_VERBOSE) {
 *     for (id sprocket in sprockets)
 *         DDLogVerbose(@"sprocket: %@", [sprocket description])
 * }
 *
 * -- Async --
 *
 * Defines the default asynchronous options.
 * The default philosophy for asynchronous logging is very simple:
 *
 * Log messages with errors should be executed synchronously.
 *     After all, an error just occurred. The application could be unstable.
 *
 * All other log messages, such as debug output, are executed asynchronously.
 *     After all, if it wasn't an error, then it was just informational output,
 *     or something the application was easily able to recover from.
 *
 * -- Changes --
 *
 * You are strongly discouraged from modifying this file.
 * If you do, you make it more difficult on yourself to merge future bug fixes and improvements from the project.
 * Instead, create your own MyLogging.h or ApplicationNameLogging.h or CompanyLogging.h
 *
 * For an example of customizing your logging experience, see the "Custom Log Levels" page:
 * https://github.com/robbiehanson/CocoaLumberjack/wiki/CustomLogLevels
 **/

#define LOG_FLAG_REPORT    (1 << 0)   // 0...0001
#define LOG_FLAG_MAJOR     (1 << 1)   // 0...0010
#define LOG_FLAG_DETAIL    (1 << 2)   // 0...0100
#define LOG_FLAG_VERBOSE   (1 << 3)   // 0...1000

#define LOG_LEVEL_OFF      0
#define LOG_LEVEL_REPORT   (LOG_FLAG_REPORT)                                                         // 0...0001
#define LOG_LEVEL_MAJOR    (LOG_FLAG_REPORT | LOG_FLAG_MAJOR)                                        // 0...0011
#define LOG_LEVEL_DETAIL   (LOG_FLAG_REPORT | LOG_FLAG_MAJOR | LOG_FLAG_DETAIL)                      // 0...0111
#define LOG_LEVEL_VERBOSE  (LOG_FLAG_REPORT | LOG_FLAG_MAJOR | LOG_FLAG_DETAIL | LOG_FLAG_VERBOSE)   // 0...1111

#define LOG_REPORT   (ddLogLevel & LOG_FLAG_REPORT)
#define LOG_MAJOR    (ddLogLevel & LOG_FLAG_MAJOR)
#define LOG_DETAIL    (ddLogLevel & LOG_FLAG_DETAIL)
#define LOG_VERBOSE (ddLogLevel & LOG_FLAG_VERBOSE)

#define LOG_ASYNC_ENABLED YES

#define LOG_ASYNC_REPORT   ( NO && LOG_ASYNC_ENABLED)
#define LOG_ASYNC_MAJOR    (YES && LOG_ASYNC_ENABLED)
#define LOG_ASYNC_DETAIL   (YES && LOG_ASYNC_ENABLED)
#define LOG_ASYNC_VERBOSE  (YES && LOG_ASYNC_ENABLED)

#define DDLogReport(frmt, ...)   LOG_OBJC_MAYBE(LOG_ASYNC_REPORT,   ddLogLevel, LOG_FLAG_REPORT,   0, frmt, ##__VA_ARGS__)
#define DDLogMajor(frmt, ...)    LOG_OBJC_MAYBE(LOG_ASYNC_MAJOR,    ddLogLevel, LOG_FLAG_MAJOR,    0, frmt, ##__VA_ARGS__)
#define DDLogDetail(frmt, ...)    LOG_OBJC_MAYBE(LOG_ASYNC_DETAIL,    ddLogLevel, LOG_FLAG_DETAIL,    0, frmt, ##__VA_ARGS__)
#define DDLogVerbose(frmt, ...) LOG_OBJC_MAYBE(LOG_ASYNC_VERBOSE, ddLogLevel, LOG_FLAG_VERBOSE, 0, frmt, ##__VA_ARGS__)

#define DDLogCReport(frmt, ...)   LOG_C_MAYBE(LOG_ASYNC_REPORT,   ddLogLevel, LOG_FLAG_REPORT,   0, frmt, ##__VA_ARGS__)
#define DDLogCMajor(frmt, ...)    LOG_C_MAYBE(LOG_ASYNC_MAJOR,    ddLogLevel, LOG_FLAG_MAJOR,    0, frmt, ##__VA_ARGS__)
#define DDLogCDetail(frmt, ...)    LOG_C_MAYBE(LOG_ASYNC_DETAIL,    ddLogLevel, LOG_FLAG_DETAIL,    0, frmt, ##__VA_ARGS__)
#define DDLogCVerbose(frmt, ...) LOG_C_MAYBE(LOG_ASYNC_VERBOSE, ddLogLevel, LOG_FLAG_VERBOSE, 0, frmt, ##__VA_ARGS__)

/**
 * The THIS_FILE macro gives you an NSString of the file name.
 * For simplicity and clarity, the file name does not include the full path or file extension.
 *
 * For example: DDLogWarn(@"%@: Unable to find thingy", THIS_FILE) -> @"MyViewController: Unable to find thingy"
 **/

NSString *DDExtractFileNameWithoutExtension(const char *filePath, BOOL copy);

#define THIS_FILE (DDExtractFileNameWithoutExtension(__FILE__, NO))

/**
 * The THIS_METHOD macro gives you the name of the current objective-c method.
 *
 * For example: DDLogWarn(@"%@ - Requires non-nil strings", THIS_METHOD) -> @"setMake:model: requires non-nil strings"
 *
 * Note: This does NOT work in straight C functions (non objective-c).
 * Instead you should use the predefined __FUNCTION__ macro.
 **/

#define THIS_METHOD NSStringFromSelector(_cmd)


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface DDLog : NSObject


/**
 * Registered Dynamic Logging
 *
 * These methods allow you to obtain a list of classes that are using registered dynamic logging,
 * and also provides methods to get and set their log level during run time.
 **/

+ (NSArray *)registeredClasses;
+ (NSArray *)registeredClassNames;

+ (int)logLevelForClass:(Class)aClass;
+ (int)logLevelForClassWithName:(NSString *)aClassName;
+ (void)setAllClassesLogLevelFromUserDefaults: (NSString *)defaultsKey;
+(void) writeAllClassesLogLevelToUserDefaults;

+ (void)setLogLevel:(int)logLevel forClass:(Class)aClass;
+ (void)setLogLevel:(int)logLevel forClassWithName:(NSString *)aClassName;

@end



@protocol DDRegisteredDynamicLogging

/**
 * Implement these methods to allow a file's log level to be managed from a central location.
 *
 * This is useful if you'd like to be able to change log levels for various parts
 * of your code from within the running application.
 *
 * Imagine pulling up the settings for your application,
 * and being able to configure the logging level on a per file basis.
 *
 * The implementation can be very straight-forward:
 *
 * + (int)ddLogLevel
 * {
 *     return ddLogLevel;
 * }
 *
 * + (void)ddSetLogLevel:(int)logLevel
 * {
 *     ddLogLevel = logLevel;
 * }
 **/

+ (int)ddLogLevel;
+ (void)ddSetLogLevel:(int)logLevel;

@end
#define __DDLOGHERE__  static int ddLogLevel = LOG_LEVEL_REPORT; + (int)ddLogLevel { return ddLogLevel; }+ (void)ddSetLogLevel:(int)logLevel {ddLogLevel = logLevel;}


//////////////////////////////////////@end
