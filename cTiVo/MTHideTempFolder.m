//
//  MTHideTempFolder.m
//  cTiVo
//
//  Created by Hugh Mackworth on 1/17/18.
//  Copyright © 2018 cTiVo. All rights reserved.
//

#import "MTHideTempFolder.h"

@implementation MTHideTempFolder


+ (Class)transformedValueClass { return [NSString class]; }
+ (BOOL)allowsReverseTransformation { return YES; }

- (id)reverseTransformedValue: (NSString *)value {
	if (!value || ([value isKindOfClass:[NSString class]] && value.length == 0)) {
		return [NSTemporaryDirectory() stringByAppendingPathComponent:@"ctivo"];
	} else {
		return value;
	}
}

- (id)transformedValue:(NSString *)value {
	NSString * defDir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"ctivo"];
	if ([value isKindOfClass:[NSString class]] && [value  isEqualToString:defDir]) {
		return @"";
	} else {
		return value;
	}
}

@end

@implementation MTHideHomeFolder

+ (Class)transformedValueClass { return [NSString class]; }
+ (BOOL)allowsReverseTransformation { return YES; }

-(id) reverseTransformedValue: (NSString *)value {
	if (!value || ([value isKindOfClass:[NSString class]] && [value hasPrefix:@"~/"])) {
		return [value stringByExpandingTildeInPath];
	} else {
		return value;
	}
}

-(id) transformedValue: (NSString *)value {
	NSString * defDir = NSHomeDirectory();
	if ([value isKindOfClass:[NSString class]] && [value hasPrefix:defDir]) {
		return [value stringByAbbreviatingWithTildeInPath];
	} else {
		return value;
	}
}

@end
