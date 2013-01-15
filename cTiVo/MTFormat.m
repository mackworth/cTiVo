//
//  MTFormat.m
//  cTiVo
//
//  Created by Scott Buchanan on 1/12/13.
//  Copyright (c) 2013 Scott Buchanan. All rights reserved.
//

#import "MTFormat.h"

@implementation MTFormat

@synthesize attributedFormatDescription = _attributedFormatDescription;

+(MTFormat *)formatWithDictionary:(NSDictionary *)format
{
	MTFormat *newFormat = [[[MTFormat alloc] init] autorelease];
	for(NSString *key in format) {
		[newFormat setValue:[format objectForKey:key] forKey:key];
	}
	return newFormat;
}

-(id)init
{
	self = [super init];
	if (self) {
		self.formatDescription = @"";
		self.filenameExtension = @"";
		self.encoderUsed = @"";
		self.name = @"";
		self.encoderVideoOptions = @"";
		self.encoderAudioOptions = @"";
		self.encoderOtherOptions = @"";
		self.inputFileFlag = @"";
		self.outputFileFlag = @"";
		self.comSkip = [NSNumber numberWithBool:NO];
		self.iTunes = [NSNumber numberWithBool:NO];
		self.mustDownloadFirst = [NSNumber numberWithBool:YES];
		self.isFactoryFormat = [NSNumber numberWithBool:NO];
        self.isHidden = [NSNumber numberWithBool:NO];
		
		keys = [[NSArray arrayWithObjects:
						 @"formatDescription",
						 @"filenameExtension",
						 @"encoderUsed",
						 @"name",
						 @"encoderVideoOptions",
						 @"encoderAudioOptions",
						 @"encoderOtherOptions",
						 @"inputFileFlag",
						 @"outputFileFlag",
						 @"regExProgress",
						 @"comSkip",
						 @"iTunes",
						 @"mustDownloadFirst",
                         @"isHidden",
						 @"isFactoryFormat",
						 nil] retain];
	}
	return self;
}

-(void)setValue:(id)value forKey:(NSString *)key
{
    [super setValue:value forKey:key];
    [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationFormatChanged object:self];
}

-(NSAttributedString *)attributedFormatDescription
{
	return [_isFactoryFormat boolValue] ? [[[NSAttributedString alloc] initWithString:_formatDescription attributes:@{NSForegroundColorAttributeName : [NSColor grayColor]}] autorelease] :
                                [[[NSAttributedString alloc] initWithString:_formatDescription] autorelease];
}

-(void)setAttributedFormatDescription:(NSAttributedString *)attributedFormatDescription
{
	if (attributedFormatDescription == _attributedFormatDescription) {
		return;
	}
	[_attributedFormatDescription release];
	_attributedFormatDescription = [attributedFormatDescription retain];
	self.formatDescription = [_attributedFormatDescription string];
}

-(NSDictionary *)toDictionary
{
	NSMutableDictionary *tmpDict = [NSMutableDictionary dictionary];
	for (NSString *key in keys) {
		[tmpDict setObject:[self valueForKey:key] forKey:key];
	}
	return tmpDict;
}

-(id)copyWithZone:(NSZone *)zone
{
	MTFormat *new = [MTFormat new];
	new.formatDescription = [[_formatDescription copyWithZone:zone] autorelease];
	new.filenameExtension = [[_filenameExtension copyWithZone:zone] autorelease];
	new.encoderUsed = [[_encoderUsed copyWithZone:zone] autorelease];
	new.name = [[_name copyWithZone:zone] autorelease];
	new.encoderVideoOptions = [[_encoderVideoOptions copyWithZone:zone] autorelease];
	new.encoderAudioOptions = [[_encoderAudioOptions copyWithZone:zone] autorelease];
	new.encoderOtherOptions = [[_encoderOtherOptions copyWithZone:zone] autorelease];
	new.inputFileFlag = [[_inputFileFlag copyWithZone:zone] autorelease];
	new.outputFileFlag = [[_outputFileFlag copyWithZone:zone] autorelease];
	new.regExProgress = [[_regExProgress copyWithZone:zone] autorelease];
	new.comSkip = [[_comSkip copyWithZone:zone] autorelease];
	new.iTunes = [[_iTunes copyWithZone:zone] autorelease];
	new.mustDownloadFirst = [[_mustDownloadFirst copyWithZone:zone] autorelease];
	new.isHidden = [[_isHidden copyWithZone:zone] autorelease];
	new.isFactoryFormat = [[_isFactoryFormat copyWithZone:zone] autorelease];
	return new;
}

-(BOOL)isSame:(MTFormat *)testFormat
{
	BOOL ret = YES;
	for (NSString *key in keys) {
		if ([[self valueForKey:key] compare:[testFormat valueForKey:key]] != NSOrderedSame) {
			ret = NO;
			break;
		}
	}
	return ret;
}

#pragma mark - Convenience Methods

-(BOOL)canAddToiTunes
{
    return [_iTunes boolValue];
}

-(BOOL)canSimulEncode
{
    return ![_mustDownloadFirst boolValue];
}

-(void)dealloc
{
	[keys release];
	self.formatDescription = nil;
	self.filenameExtension = nil;
	self.encoderUsed = nil;
	self.name = nil;
	self.encoderVideoOptions = nil;
	self.encoderAudioOptions = nil;
	self.encoderOtherOptions = nil;
	self.inputFileFlag = nil;
	self.outputFileFlag = nil;
	self.regExProgress = nil;
	self.comSkip = nil;
	self.iTunes = nil;
	self.mustDownloadFirst = nil;
    self.isHidden = nil;
	self.isFactoryFormat = nil;
	[super dealloc];
}

@end
