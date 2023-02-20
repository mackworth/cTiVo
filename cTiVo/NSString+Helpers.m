//
//  NSString+Helpers.m
//  cTiVo
//
//  Created by Scott Buchanan on 6/1/13.
//  Copyright (c) 2013 cTiVo. All rights reserved.
//

#import "NSString+Helpers.h"
#include <sys/xattr.h>
#include "MTLog.h"

@implementation NSString (Helpers)

-(BOOL)contains:(NSString *)string
{
    BOOL retValue = NO;
    NSRange r = [self rangeOfString:string];
    if (r.location != NSNotFound) {
        retValue = YES;
    }
    return retValue;    
}

+ (NSString *)stringFromTimeInterval:(NSTimeInterval)interval {
    NSInteger ti = (NSInteger)interval;
    NSInteger seconds = ti % 60;
    NSInteger minutes = (ti / 60) % 60;
    NSInteger hours = (ti / 3600);
    if (hours > 0 || minutes >= 10) {
        return [NSString stringWithFormat:@"%02ld:%02ld", (long)hours, (long)minutes];
    } else {
        return [NSString stringWithFormat:@"%02ld:%02ld:%02ld", (long)hours, (long)minutes, (long)seconds];
    }
}

+ (NSString *)stringFromBytesPerSecond: (double) speed {
    if (speed >= 1000000000) {
        return[NSString stringWithFormat:@"%0.1f GBps",speed/(1000000000.0)];
    } else if (speed >= 10000000) {
        return[NSString stringWithFormat:@"%0.0f MBps",speed/(1000000.0)];
    } else if (speed >= 1000000) {
        return[NSString stringWithFormat:@"%0.1f MBps",speed/(1000000.0)];
    } else if (speed >= 10000) {
        return[NSString stringWithFormat:@"%0.0f KBps",speed/(1000.0)];
    } else if (speed >= 1000) {
        return[NSString stringWithFormat:@"%0.1f KBps",speed/(1000.0)];
    } else if (speed > 0) {
        return[NSString stringWithFormat:@"%0.0f Bps",(speed) ];
    } else {
        return @"-";
    }
}


- (BOOL) isEquivalentToPath: (NSString *) path {
    if (!path.length) return NO;

    if ([self isEqualToString:path] ) {
        return YES;
    }
    NSURL * urlA = [NSURL fileURLWithPath:self];
    NSURL * urlB = [NSURL fileURLWithPath:path];

    // Standarized path. Valid for ~ . and ..
    // Does not resolv real paths, though.
    NSString * myPathA = [[urlA path] stringByStandardizingPath];
    NSString * myPathB = [[urlB path] stringByStandardizingPath];
    if ([myPathA isEqualToString:myPathB]) return YES;

    // If everything else fails, test if both files point to the same resource (symbolic links, shared files...)
    myPathA = [myPathA stringByResolvingSymlinksInPath];
    myPathB = [myPathB stringByResolvingSymlinksInPath];
    if ([myPathA isEqualToString:myPathB]) return YES; // both files must exist

    return NO;
}

+(NSString *) stringWithEndofFileHandle:(NSFileHandle *) logHandle numBytes:(NSUInteger) numBytes {
    unsigned long long logFileSize = [logHandle seekToEndOfFile];
    if (logFileSize == 0)  return @"";
    if (logFileSize <  (unsigned long long) numBytes) numBytes = (NSUInteger)logFileSize;
    [logHandle seekToFileOffset:(logFileSize-numBytes)];
    NSData *tailOfFile = [logHandle readDataOfLength:numBytes];
    if (tailOfFile.length == 0) return @"";
    NSString * logString = [[NSString alloc] initWithData:tailOfFile encoding:NSASCIIStringEncoding]; //NSUTF8StringEncoding fails due to reporting junk
    return  logString;

}

+(NSString *) stringWithEndOfFile:(NSString *) path  {
    NSUInteger backup = 5000;
    NSFileHandle *logHandle = [NSFileHandle fileHandleForReadingAtPath:path];
    return [NSString stringWithEndofFileHandle:logHandle numBytes:backup];
}

-(BOOL) hasCaseInsensitivePrefix: (NSString *) prefix {
    NSRange prefixRange = [self rangeOfString:prefix
                                      options:(NSAnchoredSearch | NSCaseInsensitiveSearch)];
    return prefixRange.location == 0 ;
}

-(NSString *) removeParenthetical {
    NSUInteger locOpen = [self rangeOfString:@"("].location;
    NSUInteger locClose = [self rangeOfString:@")"].location;

    if (locOpen != NSNotFound &&
        locClose != NSNotFound &&
        locOpen < locClose) {
        return [self stringByReplacingCharactersInRange:NSMakeRange(locOpen, locClose-locOpen+1) withString:@""];
    } else {
        return self;
    }


}

-(NSString *) escapedQueryString {
    //do not use with whole URL, only with parts that are "quoted" within the query part of URL

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated"
    NSString * testString =  (NSString *) CFBridgingRelease (
    CFURLCreateStringByAddingPercentEscapes(NULL,
                                            (CFStringRef)self,
                                            NULL,
                                            CFSTR("￼=,$&+;@?\n\"<>#\t :/"),
                                            kCFStringEncodingUTF8)) ;
#pragma clang diagnostic pop

//	NSString * test2String = [self stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
//	if ([testString isEqual:test2String]) {
//		NSLog(@"TestString GOOD");
//	} else {
//		NSLog(@"TestString BAD: \nOriginal:%@\nOld:%@\nNew:%@\n",self, testString, test2String);
//	}
	return testString;
	
}

-(NSString *) pathForParentDirectoryWithName: (NSString *) parent {
    NSString * searchParent = self;
    //if we're doing
    while (searchParent.length > 1 && ![parent isEqualToString: [searchParent lastPathComponent]]) {
        searchParent = [searchParent stringByDeletingLastPathComponent];
    }
    if ([parent isEqualToString: [searchParent lastPathComponent]]) {
        return searchParent;
    } else {
        return self;
    }
}

-(NSString *) getXAttr:(NSString *) key  {
	if (!key) return nil;
    NSData *buffer = [NSData dataWithData:[[NSMutableData alloc] initWithLength:256]];
	const char * filePath = [self fileSystemRepresentation];
	if (!filePath) return nil;
    ssize_t len = getxattr(filePath, [key UTF8String], (void *)[buffer bytes], 256, 0, 0);
    if (len > 0) {
        NSData *idData = [NSData dataWithBytes:[buffer bytes] length:(NSUInteger)len];
        NSString  *result = [[NSString alloc] initWithData:idData encoding:NSUTF8StringEncoding];
        return result;
    }
    return nil;
}


-(void) setXAttr:(NSString *) key toValue:(NSString *) value  {
    NSData * data = [value dataUsingEncoding:NSUTF8StringEncoding];
    if ( setxattr([self fileSystemRepresentation],
             [key UTF8String],
             [data bytes],
             data.length,
				   0, 0)) {
		DDLogAlways(@"XAttr error %d for setting %@ to %@ for file %@", errno, key, value, self);
	}
}

-(NSString *) maskSerialNumber: (NSString *) TSN  {
	if (TSN.length > 4 && [self contains:TSN]) {
		NSString * maskedTSN = [NSString  stringWithFormat: @"%@XXXXXXXXX%@", [TSN substringToIndex:2], [TSN substringFromIndex:(TSN.length-4)]];
		return [self stringByReplacingOccurrencesOfString:TSN withString:maskedTSN ];
	} else {
		return self;
	}
}

@end
