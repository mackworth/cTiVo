//
//  MTLog.m
//  cTiVo
//
//  Created by Hugh Mackworth on 7/2/14.
//  Copyright (c) 2014 cTiVo. All rights reserved.
//
#import "MTLog.h"


@implementation DDLog (UserDefaults)

+(void)setAllClassesLogLevelFromUserDefaults: (NSString *)defaultsKey
{
	NSDictionary * levels = [[NSUserDefaults standardUserDefaults] objectForKey:kMTDebugLevelDetail];
	if (levels.count > 0) {
		for (NSString* className in [levels allKeys]) {
			[self setLogLevel:((NSNumber *)levels[className]).intValue forClassWithName:className];
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

+(void)setAllClassesLogLevel:(int) debugLevel {
    for (Class class in [DDLog registeredClasses]) {
        [self setLogLevel:debugLevel forClass:class];
    }

}

@end
