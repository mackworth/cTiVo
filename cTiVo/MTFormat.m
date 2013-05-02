//
//  MTFormat.m
//  cTiVo
//
//  Created by Scott Buchanan on 1/12/13.
//  Copyright (c) 2013 Scott Buchanan. All rights reserved.
//

#import "MTFormat.h"

@implementation MTFormat

@synthesize pathForExecutable = _pathForExecutable;
@synthesize attributedFormatDescription = _attributedFormatDescription;

__DDLOGHERE__

+(MTFormat *)formatWithDictionary:(NSDictionary *)format
{
	MTFormat *newFormat = [[MTFormat alloc] init];
	for(NSString *key in format) {
		@try {
			[newFormat setValue:[format objectForKey:key] forKey:key];
		}
		@catch (NSException *exception) {
			DDLogVerbose(@"FormatWithDictionary: exception %@ trying value %@ for key %@",exception,[format objectForKey:key],key);
		}
		@finally {}
	}
	DDLogVerbose(@"New format %@ from %@", newFormat, format);
	return newFormat;
}

-(void)checkAndUpdateFormatName:(NSArray *)formatList
{
	//Make sure the title isn't the same and if it is add a -1 modifier
    for (MTFormat *f in formatList) {
		if ([_name caseInsensitiveCompare:f.name] == NSOrderedSame) {
			DDLogVerbose(@"Format  %@ same name as existing %@", self, f);
			NSRegularExpression *ending = [NSRegularExpression regularExpressionWithPattern:@"(.*)-([0-9]+)$" options:NSRegularExpressionCaseInsensitive error:nil];
            NSTextCheckingResult *result = [ending firstMatchInString:_name options:NSMatchingWithoutAnchoringBounds range:NSMakeRange(0, _name.length)];
            if (result) {
                int n = [[f.name substringWithRange:[result rangeAtIndex:2]] intValue];
                self.name = [[_name substringWithRange:[result rangeAtIndex:1]] stringByAppendingFormat:@"-%d",n+1];
            } else {
                self.name = [_name stringByAppendingString:@"-1"];
            }
            [self checkAndUpdateFormatName:formatList];
        }
    }
}

-(NSString *)pathForExecutable
{
	if (!_pathForExecutable) {
		
		NSArray *searchPaths = [NSArray arrayWithObjects:@"/usr/local/bin/%1$@",@"/opt/local/bin/%1$@",@"/usr/local/%1$@/bin/%1$@",@"/opt/local/%1$@/bin/%1$@",@"/usr/bin/%1$@",@"%1$@", nil];
		NSFileManager *fm = [NSFileManager defaultManager];
		NSString *validPath = [[NSBundle mainBundle] pathForResource:self.encoderUsed ofType:@""];
		if (!validPath) {
			for (NSString *searchPath in searchPaths) {
				NSString * filePath = [[NSString stringWithFormat:searchPath,self.encoderUsed] stringByResolvingSymlinksInPath];
				if ([fm fileExistsAtPath:filePath]){ //Its there now check that its executable
					int permissions = [[fm attributesOfItemAtPath:filePath error:nil][NSFilePosixPermissions] shortValue];
					if (permissions && 01) { //We have an executable file
						DDLogVerbose(@"Found %@ in %@ (format %@)", self.encoderUsed, searchPath, self);
						validPath = filePath;
						break;
					}
				}
			}
		}
		if (!validPath) DDLogMajor(@"For format %@, couldn't find %@ in %@ ", self, self.encoderUsed, searchPaths);
		_pathForExecutable = validPath;
	}
	return _pathForExecutable;
}



-(id)init
{
	self = [super init];
	if (self) {
		self.formatDescription = @"";
		self.filenameExtension = @"";
		self.encoderUsed = @"";
		self.name = @"";
		self.regExProgress = @"";
		self.encoderVideoOptions = @"";
		self.encoderAudioOptions = @"";
		self.encoderOtherOptions = @"";
		self.encoderLateVideoOptions = @"";
		self.encoderLateAudioOptions = @"";
		self.encoderLateOtherOptions = @"";
		self.encoderEarlyVideoOptions = @"";
		self.encoderEarlyAudioOptions = @"";
		self.encoderEarlyOtherOptions = @"";
		self.comSkipOptions = @"";
		self.captionOptions = @"";
		self.inputFileFlag = @"";
		self.outputFileFlag = @"";
		self.comSkip = @(NO);
		self.iTunes = @(NO);
		self.mustDownloadFirst = @(YES);
		self.isFactoryFormat = @(NO);
        self.isHidden = @(NO);
		
		keys = [NSArray arrayWithObjects:
						 @"formatDescription",
						 @"filenameExtension",
						 @"encoderUsed",
						 @"name",
						 @"encoderVideoOptions",
						 @"encoderAudioOptions",
						 @"encoderOtherOptions",
						 @"inputFileFlag",
						 @"outputFileFlag",
						 @"edlFlag",
						 @"comSkipOptions",
						 @"captionOptions",
						 @"regExProgress",
						 @"comSkip",
						 @"iTunes",
						 @"mustDownloadFirst",
                         @"isHidden",
						 @"isFactoryFormat",
						 nil];
	}
	return self;
}

-(void)setValue:(id)value forKey:(NSString *)key
{
    [super setValue:value forKey:key];
    [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationFormatChanged object:self];
}

-(id) valueForKey:(NSString *)key {
	id val = [super valueForKey:key];
	if (!val) {
		val = @"";
	}
	return val;
}

-(void)setEncoderVideoOptions:(NSString *)encoderVideoOptions
{
    if (encoderVideoOptions != _encoderVideoOptions) {
        _encoderVideoOptions = encoderVideoOptions;
        if (_encoderVideoOptions) {
            NSArray *earlyLateOptions = [_encoderVideoOptions componentsSeparatedByString:kMTInputLocationToken];
            if (earlyLateOptions && earlyLateOptions.count > 0) {
                self.encoderEarlyVideoOptions = earlyLateOptions[0];
                self.encoderLateVideoOptions = @"";
                if (earlyLateOptions.count > 1) {
                    self.encoderLateVideoOptions = earlyLateOptions[1];
                }
            }
        }
    }
}

-(void)setEncoderAudioOptions:(NSString *)encoderAudioOptions
{
    if (encoderAudioOptions != _encoderAudioOptions) {
        _encoderAudioOptions = encoderAudioOptions;
        if (_encoderAudioOptions) {
            NSArray *earlyLateOptions = [_encoderAudioOptions componentsSeparatedByString:kMTInputLocationToken];
            if (earlyLateOptions && earlyLateOptions.count > 0) {
                self.encoderEarlyAudioOptions = earlyLateOptions[0];
                self.encoderLateAudioOptions = @"";
                if (earlyLateOptions.count > 1) {
                    self.encoderLateAudioOptions = earlyLateOptions[1];
                }
            }
        }
    }
}

-(void)setEncoderOtherOptions:(NSString *)encoderOtherOptions
{
    if (encoderOtherOptions != _encoderOtherOptions) {
        _encoderOtherOptions = encoderOtherOptions;
        if (_encoderOtherOptions) {
            NSArray *earlyLateOptions = [_encoderOtherOptions componentsSeparatedByString:kMTInputLocationToken];
            if (earlyLateOptions && earlyLateOptions.count > 0) {
                self.encoderEarlyOtherOptions = earlyLateOptions[0];
                self.encoderLateOtherOptions = @"";
                if (earlyLateOptions.count > 1) {
                    self.encoderLateOtherOptions = earlyLateOptions[1];
                }
            }
        }
    }
}

-(NSAttributedString *) attributedFormatStringForFont:(NSFont *) font {
	NSColor * formatColor = [NSColor colorWithDeviceRed:0.0
												  green:0.0
												   blue:([_isFactoryFormat boolValue] ? 0.0: 0.6)
												  alpha:[_isHidden boolValue] ? 0.5: 1.0];
	NSAttributedString *attTitle = [[NSAttributedString alloc] initWithString: _name
																	attributes: @{NSFontAttributeName : font,
												NSForegroundColorAttributeName: formatColor}];
	return attTitle;
}

-(NSAttributedString *)attributedFormatDescription
{
	return [_isFactoryFormat boolValue] ? [[NSAttributedString alloc] initWithString:_formatDescription attributes:@{NSForegroundColorAttributeName : [NSColor grayColor]}] :
	[[NSAttributedString alloc] initWithString:_formatDescription];
}

-(void)setAttributedFormatDescription:(NSAttributedString *)attributedFormatDescription
{
	if (_attributedFormatDescription != attributedFormatDescription) {
		_attributedFormatDescription = attributedFormatDescription;
		self.formatDescription = [_attributedFormatDescription string];
	}
}

-(NSDictionary *)toDictionary
{
	NSMutableDictionary *tmpDict = [NSMutableDictionary dictionary];
	for (NSString *key in keys) {
        id val = [self valueForKey:key];
		[tmpDict setObject:val forKey:key];
	}
	DDLogVerbose(@"Format %@ as dict: %@", _name, tmpDict);
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
	new.edlFlag = [_edlFlag copyWithZone:zone];
	new.comSkipOptions = [_comSkipOptions copyWithZone:zone];
	new.captionOptions = [_captionOptions copyWithZone:zone];
	new.regExProgress = [_regExProgress copyWithZone:zone];
	new.comSkip = [_comSkip copyWithZone:zone];
	new.iTunes = [_iTunes copyWithZone:zone];
	new.mustDownloadFirst = [_mustDownloadFirst copyWithZone:zone];
	new.isHidden = [_isHidden copyWithZone:zone];
	new.isFactoryFormat = [_isFactoryFormat copyWithZone:zone];
	new.formerName = [_formerName copyWithZone:zone];
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

-(BOOL) canAtomicParsley {
	NSArray * allowedExtensions = @[@".mp4", @".m4v", @".mov", @".3gp"];
	NSString * extension = [self.filenameExtension lowercaseString];
	return [allowedExtensions containsObject: extension];
}

-(BOOL)canSimulEncode
{
    return ![_mustDownloadFirst boolValue];
}

-(BOOL)canMarkCommercials
{
	NSArray * allowedExtensions = @[@".mp4", @".m4v"];
	NSString * extension = [self.filenameExtension lowercaseString];
	return [allowedExtensions containsObject: extension];
}

-(BOOL)canSkip
{
    return [_comSkip boolValue];
}

-(void) setEncoderUsed:(NSString *)encoderUsed {
	if (encoderUsed == _encoderUsed) return;
	_encoderUsed = encoderUsed;
	_pathForExecutable = nil;
}

-(NSString *) description {
	return [NSString stringWithFormat:@" %@(%@) Encoder: %@ =>%@",self.name,self.formatDescription,self.encoderUsed, self.filenameExtension ];
}

-(void)dealloc
{
	self.encoderUsed = nil;
	self.encoderVideoOptions = nil;
	self.encoderAudioOptions = nil;
	self.encoderOtherOptions = nil;
}

@end
