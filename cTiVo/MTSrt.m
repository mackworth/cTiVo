//
//  MTSrt.m
//  SRT_EDL_TEST
//
//  Created by Scott Buchanan on 3/28/13.
//  Copyright (c) 2013 Fawkesconsulting LLC. All rights reserved.
//

#import "MTSrt.h"
#import "MTEdl.h"
#define MAXLINE 2048

@implementation MTSrt

__DDLOGHERE__

-(NSString *)description
{
    return [NSString stringWithFormat:@"Start = %lf, End = %lf\n%@",self.startTime, self.endTime, self.caption];
}

+(MTSrt *) srtFromString: srtString {
	NSArray *lines = [srtString componentsSeparatedByString:@"\r\n"];
	if (lines.count < 3) {
		DDLogReport(@"Bad SRT: no enough lines: %@",srtString);
		return nil;
	}
	NSArray *times = [lines[1] componentsSeparatedByString:@" --> "];
	if (times.count < 2) {
		DDLogReport(@"Bad SRT: no enough times: %@",srtString);
		return nil;
	}
	NSArray *hmsStart = [times[0] componentsSeparatedByString:@":"];
	if (hmsStart.count < 3) {
		DDLogReport(@"Bad SRT: start time bad: %@",srtString);
		return nil;
	}
	double secondsStart = [[hmsStart[2] stringByReplacingOccurrencesOfString:@"," withString:@"."] doubleValue];
	secondsStart += 60.0 * ([hmsStart[0] doubleValue] * 60.0 + [hmsStart[1] doubleValue]);
	
	NSArray *hmsEnd = [times[1] componentsSeparatedByString:@":"];
	if (hmsEnd.count < 3) {
		DDLogReport(@"Bad SRT: end time bad: %@",srtString);
		return nil;
	}
	double secondsEnd = [[hmsEnd[2] stringByReplacingOccurrencesOfString:@"," withString:@"."] doubleValue];
	secondsEnd += 60.0 * ([hmsEnd[0] doubleValue] * 60.0 + [hmsEnd[1] doubleValue]);
	if (secondsStart >= secondsEnd ) {
		DDLogReport(@"Bad SRT: inaccurate times: %@", srtString);
		return nil;
	}
	
	MTSrt * newSrt =[MTSrt new];
	newSrt.startTime = secondsStart;
	newSrt.endTime = secondsEnd;
	newSrt.caption = @"";

	NSArray * captionArray = [lines subarrayWithRange:NSMakeRange(2,lines.count-2)];
	newSrt.caption = [captionArray componentsJoinedByString:@"\r\n"];

	return newSrt;
}

-(NSString *) secondsToString: (double) seconds {
   int hrs = seconds/3600.0;
    int min = (seconds - hrs * 3600)/60;
    float sec = seconds - hrs * 3600 - min * 60;
    NSString *result = [NSString stringWithFormat:@"%02d:%02d:%06.3f",hrs,min,sec];
    result = [result stringByReplacingOccurrencesOfString:@"." withString:@","];
	return result;
}

-(NSString *)formatedSrt:(int)count
{
    NSString * startString = [self secondsToString:_startTime];
    NSString * endString = [self secondsToString:_endTime];
	
	NSString *output = [NSString stringWithFormat:@"%d\r\n%@ --> %@\r\n%@\r\n\r\n",
													count,
													startString,
													endString,
													_caption];
							

    return output;
    
}

-(void) writeError:(NSString *) errMsg {
	DDLogReport(@"At %0.1f secs, %@ subtitle: %@",
				self.startTime,
				errMsg,
				self.caption);
}

+(NSString *) languageFromFileName:(NSString *) filePath {
	NSString * fileName = [filePath lastPathComponent];
	NSArray * fileComponents = [fileName componentsSeparatedByString:@"."];
	if (fileComponents.count > 3) {
		return fileComponents[2];
	} else {
		return @"eng";
	}
}

inline static void assignWord(uint8* buffer, int word) {
	buffer[0] = word >> 8 & 0xff;
	buffer[1] = word & 0xff;
}

static UInt8* makeStyleRecord(UInt8 * style, int startChar, int endChar, BOOL italics, BOOL bold, BOOL underline, unsigned char red, unsigned char blue, unsigned char green   )
{
    assignWord(&style[0], startChar);
    assignWord(&style[2], endChar);
    assignWord(&style[4], 1);//font ID; only support 1 font now
    style[6] = (underline << 2) | (italics<< 1) | bold;
	style[7] = 24;      // font-size
    style[8] = red;     // r
    style[9] = blue;     // g
    style[10] = green;    // b
    style[11] = 255;    // no alpha in srt font color
	
    return style;
}

-(unsigned int) makeStyleHeader: (UInt8 *) buffer  forNumStyles: (int) styleCount {
    unsigned int styleSize = 10 + (styleCount * 12);
    assignWord(&buffer[0],0);
    assignWord(&buffer[2],styleSize);
    memcpy    (&buffer[4], "styl", 4);
    assignWord(&buffer[8],styleCount);
    return styleSize;
}

-(NSString *) makeStyleData: (UInt8 *) buffer size: (unsigned int *) sizebuffer forString: (NSString*) string {
	NSMutableString * returnString = [NSMutableString stringWithCapacity:string.length];
	NSScanner *scanner = [NSScanner scannerWithString:string];
    int styleCount = 0;
	
    int italic = 0;
    int bold = 0;
    int underlined = 0;
	unsigned char red = 255;  //default white
	unsigned char blue = 255;
	unsigned char green = 255;
	BOOL customColor = NO;
    // Parse the tags in the line, remove them and create a style record for every style change
    
	while (YES) {
		//invariant: startPoint points to beginning of a text range (without <>) and styleAttribs are set properly for the next group of chars
		__autoreleasing NSString * textChars = @"";
		[scanner setCharactersToBeSkipped:nil];
		[scanner scanUpToString:@"<" intoString:&textChars];
		DDLogVerbose(@"subtitleText = %@",textChars);
		if ((italic || bold || underlined || customColor) && textChars.length > 0) {
            makeStyleRecord(&buffer [ 10 + (12 * styleCount)], (int)returnString.length, (int)(returnString.length+textChars.length), italic>0, bold>0, underlined>0, red, blue, green );
            styleCount++;
        }
		[returnString appendString:textChars];
		if ([scanner isAtEnd]) {
			break;
		}
		__autoreleasing NSString * tagChars = @"";
		[scanner scanString:@"<" intoString:nil];
		[scanner scanUpToString:@">" intoString:&tagChars];
		[scanner scanString:@">" intoString:nil];
		tagChars = [tagChars lowercaseString];
		DDLogVerbose(@"subtitleTag = <%@>",tagChars);
		//now work on next one
		
		unichar tagType = ' '; //for end of string case
		
		if (tagChars.length > 0) {
			tagType = [tagChars characterAtIndex: 0];
		}
		NSScanner * tagScanner = [NSScanner scannerWithString:tagChars];
		switch (tagType) {
			case 'i':
				italic++;
				break;
			case 'b':
				bold++;
				break;
			case 'u':
				underlined++;
				break;
			case 'f': {
				//e.g. <font color="#ffff00">
				NSScanner * tagScanner = [NSScanner scannerWithString:tagChars];
				unsigned int hexColor= 0;
				if ([tagScanner scanString: @"font color" intoString: nil]) {
					if ([tagScanner scanString: @"=" intoString: nil]) {
						if ([tagScanner scanString: @"\"#" intoString: nil])  {
							if ([tagScanner scanHexInt:&hexColor]) {
								red = (unsigned char) hexColor >> 16;
								green = (unsigned char) hexColor >> 8;
								blue = (unsigned char) hexColor;
								//DDLogVerbose(@"new color= %d:%d:%d", red, green, blue);
							}
						}
					}
				}
				break;
			}
			case '/': {
				//an end tag
				unichar tagEndType = ' ';  //for end of string case
				if (string.length > 1) { //normal case
					tagEndType = [tagChars characterAtIndex: 1];
				}
				switch (tagEndType) {
					case 'i':
						italic--;
						break;
					case 'b':
						bold--;
						break;
					case 'u':
						underlined--;
						break;
					case 'f': {
						if ([tagScanner scanString: @"/font color" intoString:nil] ) {
							red = 255;  //back to white
							green = 255;
							blue = 255;
						}
						break;
					}
					default:
						//unrecognized end tag; leave it alone
						[returnString appendFormat:@"</%@>", tagChars];
						break;
				}
				break;
			}
			default:
				//unrecognized tag; leave it alone
				[returnString appendFormat:@"<%@>", tagChars];
				break;
				
		};
	}
	
    if (styleCount > 0 )
        *sizebuffer = [self makeStyleHeader:buffer forNumStyles:styleCount];
	//	DDLogVerbose(@"clean string = %@",returnString);
	//	NSMutableString * outStr = [NSMutableString new];
	//	for (int i = 0; i <  *sizebuffer; i++ ) {
	//		[outStr appendFormat: @"%u[%c] ",buffer[i], buffer[i]];
	//	}
	//	DDLogVerbose(@"data[%d] = %@", *sizebuffer, outStr);
    return [NSString stringWithString:returnString];
}

-(unsigned int) subtitleMP4:(UInt8 *)buffer {
	//fill buffer with data needed for MP4 version of this SRT
    UInt8 tempStyleBuffer[MAXLINE];
    unsigned int styleLength = 0;
	char * stringStartLoc = (char *) &buffer[2];
	NSString * caption = [self.caption stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"];
    caption = [caption stringByReplacingOccurrencesOfString:@"\r" withString:@"\n"];
    caption = [self makeStyleData: tempStyleBuffer size: &styleLength forString:caption];
	
	if (![caption getCString:stringStartLoc maxLength:MAXLINE encoding:NSUTF8StringEncoding]) {
	}
	
    unsigned int stringLength = (unsigned int) strlen(stringStartLoc);
    assignWord( &buffer[0], stringLength);
    memcpy(&buffer[2+stringLength], tempStyleBuffer, styleLength);
	return 2 + stringLength + styleLength;
}


@end

@implementation NSArray (MTSrtList)

#pragma mark - SRT handling Captions 


- (void)embedSubtitlesInMP4File: (MP4FileHandle *) encodedFile forLanguage: (NSString *) language {
	//MP4WriteSample expects two bytes of length followed by string followed by style info.
	uint8_t data[MAXLINE*2+2];
	uint8_t blankData[2] = {0,0};
	DDLogVerbose(@"Embedding subtitles");

	
	double last = 0.0;
	if (self.count > 0) {
		
		MP4TrackId textTrack = MP4AddSubtitleTrack(encodedFile,1000,0,0);  //timescale;height;width
		const char * cLanguage = [language cStringUsingEncoding:NSUTF8StringEncoding];
		MP4SetTrackLanguage(
							encodedFile,
							textTrack,
							cLanguage);
		
		
		MP4SetTrackIntegerProperty(encodedFile,textTrack, "tkhd.alternate_group", 2);
		
		MP4SetTrackIntegerProperty(encodedFile,textTrack, "mdia.minf.stbl.stsd.tx3g.horizontalJustification", 1);
		MP4SetTrackIntegerProperty(encodedFile,textTrack, "mdia.minf.stbl.stsd.tx3g.verticalJustification", 0);
		
		MP4SetTrackIntegerProperty(encodedFile,textTrack, "mdia.minf.stbl.stsd.tx3g.bgColorAlpha", 255);
		
		MP4SetTrackIntegerProperty(encodedFile,textTrack, "mdia.minf.stbl.stsd.tx3g.fontID", 1);
		MP4SetTrackIntegerProperty(encodedFile,textTrack, "mdia.minf.stbl.stsd.tx3g.fontSize", 24);
		
		const uint8_t textColor[4] = { 255,255,255,255 };
		MP4SetTrackIntegerProperty(encodedFile,textTrack, "mdia.minf.stbl.stsd.tx3g.fontColorRed", textColor[0]);
		MP4SetTrackIntegerProperty(encodedFile,textTrack, "mdia.minf.stbl.stsd.tx3g.fontColorGreen", textColor[1]);
		MP4SetTrackIntegerProperty(encodedFile,textTrack, "mdia.minf.stbl.stsd.tx3g.fontColorBlue", textColor[2]);
		MP4SetTrackIntegerProperty(encodedFile,textTrack, "mdia.minf.stbl.stsd.tx3g.fontColorAlpha", textColor[3]);
		
		for (MTSrt* srt in self) {
			if (last < srt.startTime) {
				//fill in gap from previous one with an empty caption
				//Write blank
				if (!MP4WriteSample(encodedFile,
									textTrack,
									blankData, 2,
									(srt.startTime-last)*1000, 0, false )) {
					[srt writeError:@"can't write gap before" ];
					break;
				}
			}
			//DDLogVerbose(@"Embedding srt: %@", srt);
			MP4Duration duration = (srt.endTime - srt.startTime)*1000;
			unsigned int len = [srt subtitleMP4:data];
			//Write subtitle
			//			NSMutableString * outStr = [NSMutableString new];
			//			for (int i = 0; i <  len; i++ ) {
			//				[outStr appendFormat: @"%u[%c] ",data[i], data[i]];
			//			}
			//			DDLogVerbose(@"data[%d] = %@", len, outStr);
			if (!MP4WriteSample( encodedFile, textTrack, data, len, duration, 0, false )) {
				[srt writeError:@"can't write" ];
				break;
			}
			last = srt.endTime;
		}
	}
}

+(NSArray *)getFromSRTFile:(NSString *)srtFile
{
	NSArray *rawSrts = [[NSString stringWithContentsOfFile:srtFile encoding:NSUTF8StringEncoding error:nil] componentsSeparatedByString:@"\r\n\r\n"];
    NSMutableArray *srts = [NSMutableArray array];
	MTSrt *lastSrt = nil;
    for (NSString *rawSrt in rawSrts) {
        if (rawSrt.length > kMinSrtLength) {
            MTSrt *newSrt = [MTSrt srtFromString: rawSrt];
			if (newSrt && lastSrt) {
				if (newSrt.startTime <= lastSrt.endTime) {
					DDLogReport(@"SRT file not in correct order");
					newSrt = nil;
				}
			}
            if (newSrt) {
				[srts addObject:newSrt];
			} else {
				DDLogDetail(@"SRTs before bad one: %@",srts);
				return nil;
			}
			lastSrt = newSrt;
        }
    }
    DDLogVerbose(@"srts = %@",srts);
    return [NSArray arrayWithArray:srts];
}

-(void)writeToSRTFilePath:(NSString *)filePath
{
    [[NSFileManager defaultManager] createFileAtPath:filePath contents:[NSData data] attributes:nil];
    NSFileHandle *srtFileHandle = [NSFileHandle fileHandleForWritingAtPath:filePath];
    NSString *output = @"";
    int i =1;
    for (MTSrt *srt in self) {
        output = [output stringByAppendingString:[srt formatedSrt:i]];
        i++;
    }
    [srtFileHandle writeData:[output dataUsingEncoding:NSUTF8StringEncoding allowLossyConversion:YES]];
    [srtFileHandle closeFile];
	
}

#pragma mark - adjust SRT due to commercial cuts
-(NSArray *)processWithEDLs:(NSArray *)edls {
    if (edls.count == 0) return self;
	NSMutableArray *keptSrts = [NSMutableArray array];
	NSUInteger edlIndex = 0;
	MTEdl *currentEDL = edls[edlIndex];
    for (MTSrt *srt in self) {
		while (currentEDL &&  (  (srt.startTime > currentEDL.endTime) || (currentEDL.edlType != 0)  ) ){
			//relies on both edl and srt to be sorted and skips edl that are not cuts (type != 0)
			edlIndex++;
			currentEDL = nil;
			if (edlIndex < edls.count) {
				currentEDL = edls[edlIndex];
			}
			
		};
		//now current edl is either crossed with srt or after it.
		//If crossed, we delete srt;
		if (currentEDL) {
			if (currentEDL.startTime <= srt.endTime ) {
				//The srt is  in a cut so remove
				continue;
			}
		}
		//if after, we use cumulative offset of "just-prior" edl
		if (edlIndex > 0) {  //else no offset required
			MTEdl * prevEdl = (MTEdl *)edls[edlIndex-1];
			srt.startTime -= prevEdl.offset;
			srt.endTime -= prevEdl.offset;
		}
		[keptSrts addObject:srt];
    }
	return [NSArray arrayWithArray:keptSrts];
}


@end
