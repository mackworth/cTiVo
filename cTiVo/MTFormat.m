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

__DDLOGHERE__

+(MTFormat *)formatWithDictionary:(NSDictionary *)format
{
	MTFormat *newFormat = [[[MTFormat alloc] init] autorelease];
	for(NSString *key in format) {
		[newFormat setValue:[format objectForKey:key] forKey:key];
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
		if (validPath) {
			return validPath;
		}
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
		self.comSkipOptions = @"";
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
						 @"edlFlag",
						 @"comSkipOptions",
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


-(NSAttributedString *) attributedFormatStringForFont:(NSFont *) font {
	NSColor * formatColor = [NSColor colorWithDeviceRed:0.0
												  green:0.0
												   blue:([_isFactoryFormat boolValue] ? 0.0: 0.6)
												  alpha:[_isHidden boolValue] ? 0.5: 1.0];
	NSAttributedString *attTitle = [[[NSAttributedString alloc] initWithString: _name
																	attributes: @{NSFontAttributeName : font,
												NSForegroundColorAttributeName: formatColor}] autorelease];
	return attTitle;
}
-(NSAttributedString *)attributedFormatDescription
{
	return [_isFactoryFormat boolValue] ? [[[NSAttributedString alloc] initWithString:_formatDescription attributes:@{NSForegroundColorAttributeName : [NSColor grayColor]}] autorelease] :
	[[[NSAttributedString alloc] initWithString:_formatDescription] autorelease];
}

-(NSDictionary *)toDictionary
{
	NSMutableDictionary *tmpDict = [NSMutableDictionary dictionary];
	for (NSString *key in keys) {
        id val = [self valueForKey:key];
        if (!val) {
            val = @"";
        }
		[tmpDict setObject:val forKey:key];
	}
	DDLogVerbose(@"Format %@ as dict: %@", _name, tmpDict);
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
	new.edlFlag = [[_edlFlag copyWithZone:zone] autorelease];
	new.comSkipOptions = [[_comSkipOptions copyWithZone:zone] autorelease];
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

-(BOOL)canSkip
{
    return [_comSkip boolValue];
}

-(void) setEncoderUsed:(NSString *)encoderUsed {
	if (encoderUsed == _encoderUsed) return;
	[_encoderUsed release];
	_encoderUsed = [encoderUsed retain];
	_pathForExecutable = nil;
}

-(NSString *) description {
	return [NSString stringWithFormat:@" %@(%@) Encoder: %@ =>%@",self.name,self.formatDescription,self.encoderUsed, self.filenameExtension ];
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
	self.comSkipOptions = nil;
	self.inputFileFlag = nil;
	self.outputFileFlag = nil;
	self.edlFlag = nil;
	self.regExProgress = nil;
	self.comSkip = nil;
	self.iTunes = nil;
	self.mustDownloadFirst = nil;
    self.isHidden = nil;
	self.isFactoryFormat = nil;
	[super dealloc];
}

@end
