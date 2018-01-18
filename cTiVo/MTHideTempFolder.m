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
- (id)reverseTransformedValue:(id)value {
	
	NSString *retValue = value;
	if (!value || ([value isKindOfClass:[NSString class]] && ((NSString *)value).length == 0)) {
		retValue = [NSTemporaryDirectory() stringByAppendingPathComponent:@"ctivo"];
	}
//	NSLog(@"Reverseform: %@ -> %@", value, retValue);
	return retValue;
}
- (id)transformedValue:(id)value {
	
	NSString *retValue = value;
	NSString * defDir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"ctivo"];
	if ([value isKindOfClass:[NSString class]] && [(NSString *)value  isEqualToString:defDir]) {
		retValue = @"";
	}
	NSLog(@"Transform: %@ -> %@ (vs %@)", value, retValue, defDir);
	return retValue;
}

@end
