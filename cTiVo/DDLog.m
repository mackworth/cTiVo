#import "DDLog.h"

#import <pthread.h>
#import <objc/runtime.h>
#import <mach/mach_host.h>
#import <mach/host_info.h>
#import <libkern/OSAtomic.h>


/**
 * Welcome to Cocoa Lumberjack!
 * 
 * The project page has a wealth of documentation if you have any questions.
 * https://github.com/robbiehanson/CocoaLumberjack
 * 
 * If you're new to the project you may wish to read the "Getting Started" wiki.
 * https://github.com/robbiehanson/CocoaLumberjack/wiki/GettingStarted
 * 
**/


// Does ARC support support GCD objects?
// It does if the minimum deployment target is iOS 6+ or Mac OS X 10.8+


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation DDLog

/**
 * The runtime sends initialize to each class in a program exactly one time just before the class,
 * or any class that inherits from it, is sent its first message from within the program. (Thus the
 * method may never be invoked if the class is not used.) The runtime sends the initialize message to
 * classes in a thread-safe manner. Superclasses receive this message before their subclasses.
 *
 * This method may also be called directly (assumably by accident), hence the safety mechanism.
**/

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Registered Dynamic Logging
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

+ (BOOL)isRegisteredClass:(Class)class
{
	SEL getterSel = @selector(ddLogLevel);
	SEL setterSel = @selector(ddSetLogLevel:);
	
#if TARGET_OS_IPHONE && !TARGET_IPHONE_SIMULATOR
	
	// Issue #6 (GoogleCode) - Crashes on iOS 4.2.1 and iPhone 4
	// 
	// Crash caused by class_getClassMethod(2).
	// 
	//     "It's a bug with UIAccessibilitySafeCategory__NSObject so it didn't pop up until
	//      users had VoiceOver enabled [...]. I was able to work around it by searching the
	//      result of class_copyMethodList() instead of calling class_getClassMethod()"
	
	BOOL result = NO;
	
	unsigned int methodCount, i;
	Method *methodList = class_copyMethodList(object_getClass(class), &methodCount);
	
	if (methodList != NULL)
	{
		BOOL getterFound = NO;
		BOOL setterFound = NO;
		
		for (i = 0; i < methodCount; ++i)
		{
			SEL currentSel = method_getName(methodList[i]);
			
			if (currentSel == getterSel)
			{
				getterFound = YES;
			}
			else if (currentSel == setterSel)
			{
				setterFound = YES;
			}
			
			if (getterFound && setterFound)
			{
				result = YES;
				break;
			}
		}
		
		free(methodList);
	}
	
	return result;
	
#else
	
	// Issue #24 (GitHub) - Crashing in in ARC+Simulator
	// 
	// The method +[DDLog isRegisteredClass] will crash a project when using it with ARC + Simulator.
	// For running in the Simulator, it needs to execute the non-iOS code.
	
	Method getter = class_getClassMethod(class, getterSel);
	Method setter = class_getClassMethod(class, setterSel);
	
	if ((getter != NULL) && (setter != NULL))
	{
		return YES;
	}
	
	return NO;
	
#endif
}

+ (NSArray *)registeredClasses
{
	int numClasses, i;
	
	// We're going to get the list of all registered classes.
	// The Objective-C runtime library automatically registers all the classes defined in your source code.
	// 
	// To do this we use the following method (documented in the Objective-C Runtime Reference):
	// 
	// int objc_getClassList(Class *buffer, int bufferLen)
	// 
	// We can pass (NULL, 0) to obtain the total number of
	// registered class definitions without actually retrieving any class definitions.
	// This allows us to allocate the minimum amount of memory needed for the application.
	
	numClasses = objc_getClassList(NULL, 0);
	
	// The numClasses method now tells us how many classes we have.
	// So we can allocate our buffer, and get pointers to all the class definitions.
	
	Class *classes = (Class *)malloc(sizeof(Class) * numClasses);
	
	numClasses = objc_getClassList(classes, numClasses);
	
	// We can now loop through the classes, and test each one to see if it is a DDLogging class.
	
	NSMutableArray *result = [NSMutableArray arrayWithCapacity:numClasses];
	
	for (i = 0; i < numClasses; i++)
	{
		Class class = classes[i];
		
		if ([self isRegisteredClass:class])
		{
			if (![NSStringFromClass(class) hasPrefix:@"NSKVO"] ) {
				[result addObject:class];
			}
		}
	}
	
	free(classes);
	
	return result;
}

+ (NSArray *)registeredClassNames
{
	NSArray *registeredClasses = [self registeredClasses];
	NSMutableArray *result = [NSMutableArray arrayWithCapacity:[registeredClasses count]];
	
	for (Class class in registeredClasses)
	{
		[result addObject:NSStringFromClass(class)];
	}
	
	return result;
}

+ (int)logLevelForClass:(Class)aClass
{
	if ([self isRegisteredClass:aClass])
	{
		return [aClass ddLogLevel];
	}
	
	return -1;
}

+ (int)logLevelForClassWithName:(NSString *)aClassName
{
	Class aClass = NSClassFromString(aClassName);
	
	return [self logLevelForClass:aClass];
}

+ (void)setLogLevel:(int)logLevel forClass:(Class)aClass
{
	if ([self isRegisteredClass:aClass])
	{
		[aClass ddSetLogLevel:logLevel];
	}
}

+ (void)setLogLevel:(int)logLevel forClassWithName:(NSString *)aClassName
{
	Class aClass = NSClassFromString(aClassName);
	
	[self setLogLevel:logLevel forClass:aClass];
}

+(void)setAllClassesLogLevelFromUserDefaults: (NSString *)defaultsKey
{
	NSDictionary * levels = [[NSUserDefaults standardUserDefaults] objectForKey:kMTDebugLevelDetail];
	if (levels.count > 0) {
		for (NSString* className in [levels allKeys]) {
			[self setLogLevel:levels[className] forClassWithName:className];
		}
	} else {
		int debugLevel = (int)[[NSUserDefaults standardUserDefaults] integerForKey:kMTDebugLevel];
		for (Class class in [DDLog registeredClasses]) {
			[self setLogLevel:debugLevel forClass:class];
		}
	}
}

+(void) writeAllClassesLogLevelToUserDefaults {
	NSArray * classes = [DDLog registeredClasses];
	NSMutableDictionary * levels = [NSMutableDictionary dictionaryWithCapacity: classes.count];
	BOOL allSame = YES;
	int lastLevel = -1;
	for (Class class in classes) {
		int level = [self logLevelForClass:class];
		NSLog(@"class%@: %d", NSStringFromClass(class), level);
		if (lastLevel != -1 && lastLevel != level) {
			allSame = NO;
		}
		lastLevel =level;
		[levels setValue:[NSNumber numberWithInt:level] forKey:NSStringFromClass(class)];
	}
	if (allSame){
		[[NSUserDefaults standardUserDefaults] removeObjectForKey:kMTDebugLevelDetail ];
		[[NSUserDefaults standardUserDefaults] setInteger:lastLevel forKey:kMTDebugLevel];
	} else {
		[[NSUserDefaults standardUserDefaults] setObject:levels forKey: kMTDebugLevelDetail ];
		[[NSUserDefaults standardUserDefaults] removeObjectForKey:kMTDebugLevel];

	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Utilities
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

NSString *DDExtractFileNameWithoutExtension(const char *filePath, BOOL copy)
{
	if (filePath == NULL) return nil;
	
	char *lastSlash = NULL;
	char *lastDot = NULL;
	
	char *p = (char *)filePath;
	
	while (*p != '\0')
	{
		if (*p == '/')
			lastSlash = p;
		else if (*p == '.')
			lastDot = p;
		
		p++;
	}
	
	char *subStr;
	NSUInteger subLen;
	
	if (lastSlash)
	{
		if (lastDot)
		{
			// lastSlash -> lastDot
			subStr = lastSlash + 1;
			subLen = lastDot - subStr;
		}
		else
		{
			// lastSlash -> endOfString
			subStr = lastSlash + 1;
			subLen = p - subStr;
		}
	}
	else
	{
		if (lastDot)
		{
			// startOfString -> lastDot
			subStr = (char *)filePath;
			subLen = lastDot - subStr;
		}
		else
		{
			// startOfString -> endOfString
			subStr = (char *)filePath;
			subLen = p - subStr;
		}
	}
	
	if (copy)
	{
		return [[[NSString alloc] initWithBytes:subStr
		                                length:subLen
		                              encoding:NSUTF8StringEncoding] autorelease];
	}
	else
	{
		// We can take advantage of the fact that __FILE__ is a string literal.
		// Specifically, we don't need to waste time copying the string.
		// We can just tell NSString to point to a range within the string literal.
		
		return [[[NSString alloc] initWithBytesNoCopy:subStr
		                                      length:subLen
		                                    encoding:NSUTF8StringEncoding
		                                freeWhenDone:NO] autorelease];
	}
}

@end


