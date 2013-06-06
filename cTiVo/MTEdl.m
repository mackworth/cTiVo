//
//  MTEdl.m
//  SRT_EDL_TEST
//
//  Created by Scott Buchanan on 3/28/13.
//  Copyright (c) 2013 Fawkesconsulting LLC. All rights reserved.
//

#import "MTEdl.h"

@implementation MTEdl

__DDLOGHERE__

-(NSString *)description
{
    return [NSString stringWithFormat:@"Start = %lf, End  = %lf, type=%d, offset = %lf",self.startTime, self.endTime, self.edlType,self.offset];
}

+(MTEdl *)edlFromString:edlString {
	NSArray *items = [edlString componentsSeparatedByString:@"\t"];
	if (items.count < 3) {
		DDLogReport(@"Bad EDL: not enough items: %@", edlString);
		return nil;
	}
	MTEdl *newEdl =  [MTEdl new];
	newEdl.startTime = [items[0] doubleValue];
	newEdl.endTime = [items[1] doubleValue];
	if (newEdl.startTime >= newEdl.endTime ) {
		DDLogReport(@"Bad EDL: inaccurate times: %@", edlString);
		return nil;
	}
	newEdl.edlType = [items[2] intValue];
   return newEdl;
	}


@end

@implementation NSArray (MTEDLList)

+(NSArray *)getFromEDLFile:(NSString *)edlFile {
	NSArray *rawEdls = [[NSString stringWithContentsOfFile:edlFile encoding:NSASCIIStringEncoding error:nil] componentsSeparatedByString:@"\n"];
    NSMutableArray *edls = [NSMutableArray array];
	MTEdl * lastEdl = nil;
    double cumulativeOffset = 0.0;
	for (NSString *rawEdl in rawEdls) {
        if (rawEdl.length > kMinEdlLength) {
            MTEdl *newEdl = [MTEdl edlFromString:rawEdl];
			if (newEdl && lastEdl) {
				if (newEdl.startTime <= lastEdl.endTime) {
					DDLogReport(@"EDL file not in correct order");
					newEdl = nil;
				}
			}
            if (newEdl) {
				if (newEdl.edlType == 0) { //This is for a cut edl.  Other types/action don't cut (such as 1 for mute)
					cumulativeOffset += (newEdl.endTime - newEdl.startTime);
				}
				newEdl.offset = cumulativeOffset;
				[edls addObject:newEdl];
			} else {
				DDLogDetail(@"EDLs before bad one: %@",edls);
				return nil;
			}
        }
    }
    DDLogVerbose(@"edls = %@",edls);
    return [NSArray arrayWithArray:edls];
	
}

-(BOOL)addAsChaptersToMP4File: (MP4FileHandle *) encodedFile forShow:(NSString *) showName withLength:(double) length;{
	if (self.count == 0) return NO;
    //Convert edls to MP4Chapter
    MP4Chapter_t *chapterList = malloc((self.count * 2 + 1) * sizeof(MP4Chapter_t)); //This is the most there could be
    int edlOffset = 0;
    int showOffset = 0;
    int chapterOffset = 0;
    MTEdl *currentEDL = self[edlOffset];
    if (currentEDL.startTime > 0.0) { //We need a first chapter which is the show
        chapterList[chapterOffset].duration = (MP4Duration)((currentEDL.startTime) * 1000.0);
        sprintf(chapterList[chapterOffset].title,"%s %d",[showName cStringUsingEncoding:NSUTF8StringEncoding], showOffset+1);
        chapterOffset++;
        showOffset++;
    }
    for (edlOffset = 0; edlOffset < self.count; edlOffset++) {
        currentEDL = self[edlOffset];
        double endTime = currentEDL.endTime;
        if (endTime > length) {
            endTime = length;
        }
        chapterList[chapterOffset].duration = (MP4Duration)((endTime - currentEDL.startTime) * 1000.0);
        sprintf(chapterList[chapterOffset].title,"%s %d","Commercial", edlOffset+1);
        chapterOffset++;
        if (currentEDL.endTime < length && (edlOffset + 1) < self.count) { //Continuing
            MTEdl *nextEDL = self[edlOffset + 1];
            chapterList[chapterOffset].duration = (MP4Duration)((nextEDL.startTime - currentEDL.endTime) * 1000.0);
            sprintf(chapterList[chapterOffset].title,"%s %d",[showName cStringUsingEncoding:NSUTF8StringEncoding], showOffset+1);
            chapterOffset++;
            showOffset++;
        } else if (currentEDL.endTime < length) { // There's show left but no more commercials so just complete the show chapter
            chapterList[chapterOffset].duration = (MP4Duration)((length - currentEDL.endTime) * 1000.0);
            sprintf(chapterList[chapterOffset].title,"%s %d",[showName cStringUsingEncoding:NSUTF8StringEncoding], showOffset+1);
            chapterOffset++;
            showOffset++;
            
        }
    }
    //Loging fuction for testing
    
    for (int i = 0; i < chapterOffset ; i++) {
        NSLog(@"Chapter %d: duration %llu, title: %s",i+1,chapterList[i].duration, chapterList[i].title);
    }
	if (chapterList && encodedFile) {
		MP4SetChapters(encodedFile, chapterList, chapterOffset, MP4ChapterTypeQt);
        free(chapterList);
		return YES;
	} else {
        free(chapterList);
		return NO;
	}
    
}



@end