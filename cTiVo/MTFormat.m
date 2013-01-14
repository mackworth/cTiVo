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
						 @"isFactoryFormat",
						 nil] retain];
	}
	return self;
}

-(NSAttributedString *)attributedFormatDescription
{
	return [[NSAttributedString alloc] initWithString:_formatDescription];
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
	new.formatDescription = [_formatDescription copyWithZone:zone];
	new.filenameExtension = [_filenameExtension copyWithZone:zone];
	new.encoderUsed = [_encoderUsed copyWithZone:zone];
	new.name = [_name copyWithZone:zone];
	new.encoderVideoOptions = [_encoderVideoOptions copyWithZone:zone];
	new.encoderAudioOptions = [_encoderAudioOptions copyWithZone:zone];
	new.encoderOtherOptions = [_encoderOtherOptions copyWithZone:zone];
	new.inputFileFlag = [_inputFileFlag copyWithZone:zone];
	new.outputFileFlag = [_outputFileFlag copyWithZone:zone];
	new.regExProgress = [_regExProgress copyWithZone:zone];
	new.comSkip = [_comSkip copyWithZone:zone];
	new.iTunes = [_iTunes copyWithZone:zone];
	new.mustDownloadFirst = [_mustDownloadFirst copyWithZone:zone];
	new.isFactoryFormat = [_isFactoryFormat copyWithZone:zone];
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
	self.isFactoryFormat = nil;
	[super dealloc];
}

@end
