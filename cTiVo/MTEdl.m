//
//  MTEdl.m
//  SRT_EDL_TEST
//
//  Created by Scott Buchanan on 3/28/13.
//  Copyright (c) 2013 Fawkesconsulting LLC. All rights reserved.
//

#import "MTEdl.h"
static NSString * kStartTime  = @"imageURL";
static NSString * kEndTime  = @"endTime";
static NSString * kEDLType  = @"edlType";
static NSString * kOffset  = @"offset";

@implementation MTEdl

__DDLOGHERE__

- (instancetype)initWithCoder:(NSCoder *)coder {
	self = [self init];
	if (self) {
		_startTime = [coder decodeDoubleForKey: kStartTime];
		_endTime =   [coder decodeDoubleForKey: kEndTime];
		_edlType =   [coder decodeIntForKey:kEDLType];
		_offset =    [coder decodeDoubleForKey: kOffset];
	}
	return self;
}

+(BOOL) supportsSecureCoding {
	return YES;
}

- (void)encodeWithCoder:(NSCoder *)coder {
	[coder encodeDouble:  _startTime forKey:kStartTime];
	[coder encodeDouble:  _endTime forKey:kEndTime];
	[coder encodeInteger: _edlType forKey:kEDLType];
	[coder encodeDouble:  _offset  forKey:kOffset];
}

-(NSString *)description {
	int startMinutes = (int)self.startTime / 60;
	int endMinutes = (int)self.endTime / 60;
	int offsetMinutes = (int)self.offset / 60;
	double startSeconds = self.startTime - startMinutes *60;
	double endSeconds = self.endTime - endMinutes * 60;
	double offsetSeconds = self.offset - offsetMinutes * 60;
	return [NSString stringWithFormat:@"Start = %2d:%05.2f, End = %2d:%05.2f, type=%d, offset = %2d:%05.2f; length = %0.2f",
			startMinutes , startSeconds,
			endMinutes, endSeconds, self.edlType,
			offsetMinutes, offsetSeconds, self.endTime-self.startTime];
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

+(NSArray <MTEdl *> *)edlListFromSegments:(NSArray <NSNumber *> *) lengthPoints andStartPoints:(NSArray <NSNumber *> *) startPoints {
	//last startPoint should be end of show, so should be one less length than startPoint
	double showLength = startPoints.lastObject.doubleValue/1000;
	lengthPoints = [lengthPoints arrayByAddingObject:@0];
	NSMutableArray <MTEdl *> * edls = [NSMutableArray arrayWithCapacity:lengthPoints.count];
	NSUInteger startIndex = 0;
	double cutPartStart = 0.0;
	double cumulativeOffset = 0.0;
	for (NSNumber * lengthPoint in lengthPoints) {
		double segmentLength = lengthPoint.doubleValue/1000.0;
		if (startIndex >= startPoints.count) {
			if (cutPartStart <= showLength || segmentLength != 0.0) {
				DDLogReport (@"Not enough Start points found: %@ v Lengths: %@ ==> EDL so far %@", startPoints, lengthPoints, edls);
				return nil;
			} else {
				//we're beyond end and this is the fake 0.0 length segment.
				break;
			}
		}
		double segmentStart  = startPoints[startIndex].doubleValue/1000.0;
		//now create the cut that goes BEFORE the segment
		double cutPartLength = segmentStart - cutPartStart;
		if (cutPartLength <= 0) {
			//problem, unless we're at the end of file
			if (cutPartStart < showLength-5.0) {
				DDLogReport (@"In building EDL list, invalid segment: segments: %@ startPoints: %@ ==> edl %@", lengthPoints, startPoints, edls);
				return nil;
			}
			break;
		} else if (cutPartLength > 1.0){ //don't cut less than 1 second
			MTEdl * edl = [[MTEdl alloc] init];
			edl.startTime = cutPartStart;
			edl.endTime = segmentStart;
			edl.edlType = 0;
			cumulativeOffset += segmentStart-cutPartStart;
			edl.offset = cumulativeOffset;
			[edls addObject:edl];
			cutPartStart = segmentStart + segmentLength;
		}
		startIndex++;
	}
	DDLogReport (@"XXX segments: %@ startPoints: %@ ==> edl %@", lengthPoints, startPoints, edls);

	return [edls copy];
}

-(BOOL)addAsChaptersToMP4File: (MP4FileHandle *) encodedFile forShow:(NSString *) showName withLength:(double) length {
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
    for (edlOffset = 0; edlOffset < (int)self.count; edlOffset++) {
        currentEDL = self[edlOffset];
        double endTime = currentEDL.endTime;
        if (endTime > length) {
            endTime = length;
        }
        chapterList[chapterOffset].duration = (MP4Duration)((endTime - currentEDL.startTime) * 1000.0);
        sprintf(chapterList[chapterOffset].title,"%s %d","Commercial", edlOffset+1);
        chapterOffset++;
        if (currentEDL.endTime < length && (edlOffset + 1) < (int) self.count) { //Continuing
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
        DDLogDetail(@"Chapter %d: duration %llu, title: %s",i+1,chapterList[i].duration, chapterList[i].title);
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
