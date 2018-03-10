//
//  MTShowFolder.m
//  cTiVo
//
//  Created by Hugh Mackworth on 12/30/17.
//  Copyright © 2017 cTiVo. All rights reserved.
//

#import "MTShowFolder.h"

@implementation MTShowFolder

-(id)valueForUndefinedKey:(NSString *)key {
	return [self.folder[0] valueForKey:key];
}

-(double) fileSize {
	//Cumulative size on TiVo;
	double size = 0;
	for (MTTiVoShow * show in self.folder) {
		size += show.fileSize;
	}
	return size;
}

-(time_t) showLength {
	//cumulative length of shows in seconds
	time_t length = 0;
	for (MTTiVoShow * show in self.folder) {
		length += show.showLength;
	}
	return length;
}

-(BOOL)isFolder {
	return YES;
}

//lengthString and sizeString formatting copied from MTTiVoShow
-(NSString *) sizeString {
	double size = self.fileSize;
	if (size >= 1000000000) {
		return[NSString stringWithFormat:@"%0.1fGB",size/(1000000000)];
	} else if (size > 0) {
		return[NSString stringWithFormat:@"%ldMB",((NSInteger)size)/(1000000) ];
	} else {
		return @"-";
	}
}

-(NSString *) lengthString {
	time_t length = (self.showLength+30)/60; //round up to nearest minute;
	return [NSString stringWithFormat:@"%ld:%0.2ld",length/60,length % 60];
}

-(NSNumber *) rpcSkipMode { //only for sorting in tables
	int skipMode = 0;
	for (MTTiVoShow * show in self.folder) {
		skipMode = MAX(skipMode, show.rpcSkipMode.intValue);
	}
	return @(skipMode);
}


@end
