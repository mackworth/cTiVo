//
//  MTSrt.h
//  SRT_EDL_TEST
//
//  Created by Scott Buchanan on 3/28/13.
//  Copyright (c) 2013 Fawkesconsulting LLC. All rights reserved.
//

#import <Foundation/Foundation.h>
#include "mp4v2.h"

@interface MTSrt : NSObject

#define kMinSrtLength 20
@property (nonatomic) double startTime, endTime;
@property (nonatomic, strong) NSString * caption;

+(MTSrt *) srtFromString: srtString;
-(NSString *)formatedSrt:(int)count;
-(void) writeError:(NSString *) errMsg;

+(NSString *) languageFromFileName:(NSString *) filePath;

-(unsigned int) subtitleMP4:(UInt8 *)buffer;

@end



@interface NSArray (MTSrtList)


+(NSArray *)getFromSRTFile:(NSString *)srtFile;

-(NSArray *)processWithEDLs:(NSArray *)edls;

-(void)writeToSRTFilePath:(NSString *)filePath;

-(void)embedSubtitlesInMP4File: (MP4FileHandle *) encodedFile forLanguage: (NSString *) language;

@end
