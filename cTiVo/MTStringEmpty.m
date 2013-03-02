@interface MTStringEmpty : NSValueTransformer {
	
}

@end

@implementation MTStringEmpty

+ (Class)transformedValueClass { return [NSNumber class]; }
+ (BOOL)allowsReverseTransformation { return NO; }
- (id)transformedValue:(id)value {
	
	return [NSNumber numberWithBool: ((NSString *) value).length  == 0];
}


@end
