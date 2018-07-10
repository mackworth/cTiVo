//
//  MTLog.m
//  cTiVo
//
//  Created by Hugh Mackworth on 7/2/14.
//  Copyright (c) 2014 cTiVo. All rights reserved.
//
#import "MTLog.h"


@implementation MTLogWatcher

+ (instancetype)sharedInstance {
	static id sharedInstance = nil;
	
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		sharedInstance = [[self alloc] init];
	});
	
	return sharedInstance;
}

-(instancetype) init {
	if ((self = [super init])) {
		[[NSUserDefaults standardUserDefaults] addObserver:self forKeyPath:kMTDebugLevel options:NSKeyValueObservingOptionInitial context:nil];
	}
	return self;
}

 -(void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
	 if ([keyPath isEqualToString:kMTDebugLevel]) {
		 if ([ [NSUserDefaults standardUserDefaults] integerForKey:kMTDebugLevel] > 0 ) {
			 [[NSUserDefaults standardUserDefaults] removeObjectForKey:kMTDebugLevelDetail ];
		 }
		[MTLogWatcher setAllClassesLogLevelFromUserDefaults];
	 } else {
		 [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
	 }
 }

+ (void)setDebugLevel:(DDLogLevel)level forClassWithName:(NSString *)aClassName {
	[DDLog setLevel:level forClassWithName: aClassName];
	[self writeAllClassesLogLevelToUserDefaults];
}

+(void)setAllClassesLogLevelFromUserDefaults {
	NSDictionary * levels = [[NSUserDefaults standardUserDefaults] objectForKey:kMTDebugLevelDetail];
	if (levels.count > 0) {
		for (NSString* className in [levels allKeys]) {
			[DDLog setLevel:((NSNumber *)levels[className]).intValue forClassWithName:className];
		}
	} else {
		int debugLevel = (int)[[NSUserDefaults standardUserDefaults] integerForKey:kMTDebugLevel];
		for (Class class in [DDLog registeredClasses]) {
			[DDLog setLevel:debugLevel forClass:class];
		}
	}
}

+(void) writeAllClassesLogLevelToUserDefaults {
	NSArray * classes = [DDLog registeredClasses];
	NSInteger currentLevel = [[NSUserDefaults standardUserDefaults] integerForKey:kMTDebugLevel];
	NSDictionary * currentLevels = [[NSUserDefaults standardUserDefaults] objectForKey:kMTDebugLevelDetail];
	NSMutableDictionary * levels = [NSMutableDictionary dictionaryWithCapacity: classes.count];
	BOOL allSame = YES;
	NSInteger lastLevel = -1;
	for (Class class in classes) {
		NSInteger level = (NSInteger) [DDLog levelForClass:class];
        if (lastLevel != level) {
			if (lastLevel != -1) allSame = NO;
			lastLevel =level;
		}
		[levels setValue:@(level) forKey:NSStringFromClass(class)];
	}
	if (allSame){
		if (lastLevel != currentLevel || currentLevels.count > 0) {
			[[NSUserDefaults standardUserDefaults] setInteger:lastLevel forKey:kMTDebugLevel];
		}
	} else {
		//update only if there's a change
		BOOL update = currentLevels.count != levels.count;
		if (!update) {
			for (NSString * key in currentLevels.allKeys) {
				if (![currentLevels[key] isEqual: levels[key]]) {
					update = YES;
					break;
				}
			}
		}
		if (update) {
			[[NSUserDefaults standardUserDefaults] setObject:levels forKey: kMTDebugLevelDetail ];
			[[NSUserDefaults standardUserDefaults] setInteger:-1 forKey:kMTDebugLevel];
		}
	}
}

@end
