//
//  MTFormat.m
//  cTiVo
//
//  Created by Scott Buchanan on 1/12/13.
//  Copyright (c) 2013 Scott Buchanan. All rights reserved.
//

#import "MTFormat.h"
#import "NSString+Helpers.h"

@implementation MTFormat


__DDLOGHERE__

+(MTFormat *)formatWithDictionary:(NSDictionary *)format
{
	MTFormat *newFormat = [[MTFormat alloc] init];
	for(NSString *key in format) {
		@try {
			[newFormat setValue:[format objectForKey:key] forKey:key];
		}
		@catch (NSException *exception) {
			DDLogMajor(@"FormatWithDictionary: exception %@ trying value %@ for key %@",exception,[format objectForKey:key],key);
		}
		@finally {}
	}
	DDLogVerbose(@"New format %@ from %@", newFormat, format);
	return newFormat;
}
+(MTFormat *) formatWithEncFile: (NSString *) filename {

	MTFormat *newFormat = [[MTFormat alloc] init];
	newFormat.name = [@"ENC: " stringByAppendingString:[[filename lastPathComponent] stringByDeletingPathExtension ]];
	newFormat.isHidden = @NO;
	NSString * encodeString =[NSString stringWithContentsOfFile:filename encoding:NSUTF8StringEncoding error:nil];
	
	__block NSString * key = nil;
	[encodeString enumerateLinesUsingBlock:^(NSString *line, BOOL *stop) {
		line = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
		if (line.length == 0) return;
		if ([line hasPrefix:@"#"]) return;  //comment line
		if ([line hasPrefix:@"<"]) {  //found a key 
			key = [[line substringWithRange:NSMakeRange(1, line.length-2)] lowercaseString];
			return;
		}
		//assuming key from previous line, now we have value
		if ([key isEqualToString:@"description"]) {
			newFormat.formatDescription = line;
		} else if ([key isEqualToString:@"command"]) {
			NSUInteger location = [line rangeOfString:@" "].location;
			NSString *encoder = line;
			NSString *parameters = nil;
			if (location != NSNotFound) {
				encoder = [[line substringToIndex:location] lowercaseString];
				parameters = [line substringFromIndex:location+1];
			}
			NSUInteger encodeIndex = [@[@"ffmpeg",@"mencoder",@"handbrake",@"perl"] indexOfObject:encoder];
			if (encodeIndex != NSNotFound) {
				
				switch (encodeIndex) {
					case 0: //ffmpeg
						newFormat.comSkip = @NO;
						newFormat.edlFlag = @"-edl";
						newFormat.comSkipOptions = @"";
						newFormat.mustDownloadFirst = @NO;
						newFormat.outputFileFlag= @"";
						newFormat.inputFileFlag = @"-i";
						newFormat.regExProgress =  @"" ;
						newFormat.encoderUsed = @"ffmpeg";
						break;
					case 1: //mencoder
						newFormat.comSkip = @YES; 
						newFormat.edlFlag = @"-edl";
						newFormat.comSkipOptions = @"";
						newFormat.mustDownloadFirst = @NO;
						newFormat.outputFileFlag= @"-o";
						newFormat.inputFileFlag = @"";
						newFormat.regExProgress = @"";
						newFormat.encoderUsed = @"mencoder";
						break;
					case 2: //handbrake
						newFormat.comSkip = @NO;
						newFormat.edlFlag = @"";
						newFormat.comSkipOptions = @"";
						newFormat.mustDownloadFirst = @YES;
						newFormat.outputFileFlag= @"-o";
						newFormat.inputFileFlag = @"-i";
						newFormat.regExProgress =  @"([\\d.]*?) \\%" ;
						newFormat.encoderUsed = @"HandBrakeCLI";
						break;
					case 3: //perl
							//Not supported
						newFormat.name = nil;
						*stop = YES;
						DDLogReport(@"Perl ENC files not supported");
						break;
					default:
						break;
				}
				parameters = [parameters stringByReplacingOccurrencesOfString:@"CPU_CORES" withString:@"0"];
				if ([parameters rangeOfString:@"PWD"].location != NSNotFound) {
					newFormat.formatDescription = [newFormat.formatDescription stringByAppendingFormat:@"\nWarning: PWD keyword not supported: %@", parameters];
				}
				if ([parameters rangeOfString:@"SRTFILE"].location != NSNotFound) {
					newFormat.formatDescription = [newFormat.formatDescription stringByAppendingFormat:@"\nWarning: SRTFILE keyword not supported:%@", parameters];
				}
                if ([parameters rangeOfString:@"HEIGHT"].location != NSNotFound) {
                    newFormat.formatDescription = [newFormat.formatDescription stringByAppendingFormat:@"\nWarning: HEIGHT keyword not supported: %@", parameters];
                }
                if ([parameters rangeOfString:@"WIDTH"].location != NSNotFound) {
                    newFormat.formatDescription = [newFormat.formatDescription stringByAppendingFormat:@"\nWarning: WIDTH keyword not supported: %@", parameters];
                }
				if (newFormat.outputFileFlag.length > 0) {
					parameters = [parameters stringByReplacingOccurrencesOfString:[NSString stringWithFormat:@" %@ ",newFormat.outputFileFlag] withString:@""];
				} else if (![parameters hasSuffix:@"OUTPUT"]) {
					//output must be at end
					newFormat.formatDescription = [newFormat.formatDescription stringByAppendingFormat:@"\nWarning: with no output flag, OUTPUT must be at end:%@", parameters];
				}
				parameters = [parameters stringByReplacingOccurrencesOfString:@"OUTPUT" withString:@""];
				parameters = [parameters stringByReplacingOccurrencesOfString:@"INPUT" withString:kMTInputLocationToken];
				if (newFormat.inputFileFlag.length > 0) {
					parameters = [parameters stringByReplacingOccurrencesOfString:[NSString stringWithFormat:@"%@ ",newFormat.inputFileFlag] withString:@""];
				}
				newFormat.encoderOtherOptions = parameters;
			}
		} else if ([key isEqualToString:@"extension"]) {
			newFormat.filenameExtension = [@"." stringByAppendingString:line];
			newFormat.iTunes = [@[@"mpg", @"mp4", @"mov", @"m4v"] indexOfObject:[line lowercaseString]]!= NSNotFound ? @YES : @NO;
		}
	}];
	if (newFormat.name && newFormat.encoderVideoOptions && newFormat.filenameExtension) {
		DDLogReport (@"Loaded new Format from ENC file. \n Was: %@ \nIs:%@", encodeString, [newFormat toDictionary]);
		return newFormat;
	} else {
		return nil;
	}
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
		
#ifdef SANDBOX
		NSArray *searchPaths = [NSArray arrayWithObjects:@"/usr/bin/%1$@",@"%1$@", nil];
#else
		NSArray *searchPaths = [NSArray arrayWithObjects:@"/usr/local/bin/%1$@",@"/opt/local/bin/%1$@",@"/usr/local/%1$@/bin/%1$@",@"/opt/local/%1$@/bin/%1$@",@"/usr/bin/%1$@",@"%1$@", nil];
#endif
		NSFileManager *fm = [NSFileManager defaultManager];
        NSString *validPath = [[NSBundle mainBundle] pathForAuxiliaryExecutable:self.encoderUsed ];
        if (!validPath) validPath = [[NSBundle mainBundle] pathForResource:self.encoderUsed ofType:@""];
		if (!validPath) {
			for (NSString *searchPath in searchPaths) {
				NSString * filePath = [[NSString stringWithFormat:searchPath,self.encoderUsed] stringByResolvingSymlinksInPath];
				if ([fm fileExistsAtPath:filePath]){ //Its there now check that its executable
                    DDLogVerbose(@"Found %@ in %@ (format %@)", self.encoderUsed, searchPath, self.name);
                    validPath = filePath;
                    break;
				}
			}
		}
        if (validPath && ![fm isExecutableFileAtPath:validPath]) {
            DDLogReport(@"For %@ Format, %@ is not marked as executable ", self.name, validPath);
            self.isHidden = @YES;
            validPath = nil;
        } else if (!validPath) {
            DDLogMajor(@"For %@ Format, couldn't find %@ in %@ ", self.name, self.encoderUsed, searchPaths);
            self.isHidden = @YES;
        }
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
	NSColor * formatColor = nil;
	if (@available(macOS 10.10, *)) {
		if (_isHidden.boolValue) {
			if (_isFactoryFormat.boolValue) {
				formatColor = [NSColor secondaryLabelColor ];
			} else {
				formatColor = [NSColor systemGrayColor];
			}
		} else {
			if (_isFactoryFormat.boolValue) {
				formatColor = [NSColor labelColor];
			} else {
				formatColor = [NSColor systemBlueColor];
			}
		}
	} else {
		formatColor = [NSColor colorWithDeviceRed: 0.0
											green: 0.0
											 blue: _isFactoryFormat.boolValue ? 0.0: 0.6
											alpha: _isHidden.boolValue ? 0.5: 1.0];
	}
	NSAttributedString *attTitle = [[NSAttributedString alloc] initWithString: _name
																	attributes: @{NSFontAttributeName : font,
												NSForegroundColorAttributeName: formatColor}];
	return attTitle;
}

-(NSAttributedString *)attributedFormatDescription {
    if (!_formatDescription) return nil;
	return 	[[NSAttributedString alloc] initWithString:_formatDescription
											attributes: @{NSFontAttributeName : [NSFont systemFontOfSize:11 ],
														  NSForegroundColorAttributeName: [NSColor textColor]}];
}

-(void) setAttributedFormatDescription:(NSAttributedString *)attributedFormatDescription {
    //necessary due to cocoa bindings for description of format
    NSString * newString = [attributedFormatDescription string];
    if (newString.length > 0) {
        self.formatDescription = newString;
    }
}
+ (NSSet *)keyPathsForValuesAffectingAttributedFormatDescription {
    return [NSSet setWithObjects:@"formatDescription", nil];
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

-(BOOL) canAcceptMetaData {
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
	if (self.isTestPS) return NO;
	NSArray * allowedExtensions = @[@".mp4", @".m4v"];
	NSString * extension = [self.filenameExtension lowercaseString];
	return [allowedExtensions containsObject: extension];
}

-(BOOL)canSkip
{
    return [_comSkip boolValue];
}

-(BOOL)isTestPS {
    return [self.name isEqualToString:@"Test PS"];
}

-(BOOL) isEncryptedDownload {
	return [self.name isEqualToString:@"Encrypted TiVo Show"];
}

-(NSString *)transportStreamExtension {
    if ( [self.encoderUsed isEqualToString:@"catToFile"] && !self.isEncryptedDownload) {
        return @".ts";
    } else {
        return self.filenameExtension;
    }
}

-(BOOL) canDuplicate {
	return !self.isTestPS && !self.isEncryptedDownload;
}

-(BOOL) testsForAudioOnly {
    return !([self.encoderUsed isEqualToString: @"catToFile"] || [self.encoderVideoOptions contains:@"copy"]);
}

-(void) setEncoderUsed:(NSString *)encoderUsed {
	if (encoderUsed == _encoderUsed) return;
	_encoderUsed = encoderUsed;
	_pathForExecutable = nil;
}

-(NSString *) description {
	return [NSString stringWithFormat:@" %@(%@) Encoder: %@ =>%@",self.name,self.formatDescription,self.encoderUsed, self.filenameExtension ];
}

-(BOOL) isDeprecated {
    return ([self.encoderUsed isEqualToString:@"mencoder"] && !self.isTestPS);
}

-(void)dealloc
{
	self.encoderUsed = nil;
	self.encoderVideoOptions = nil;
	self.encoderAudioOptions = nil;
	self.encoderOtherOptions = nil;
}

@end
