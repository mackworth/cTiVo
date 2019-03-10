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
-(BOOL) isOnDisk {
	for (MTTiVoShow * show in self.folder) {
		if ([show isOnDisk]) return YES;
	}
	return NO;
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


- (NSArray<NSPasteboardType> *)writableTypesForPasteboard:(NSPasteboard *)pasteboard {
	if (self.isOnDisk) {
		return @[kMTTiVoShowArrayPasteBoardType, (NSString *)kUTTypeFileURL, NSPasteboardTypeString];
	} else {
		return @[kMTTiVoShowArrayPasteBoardType, NSPasteboardTypeString];
	}
}
	
- (NSPasteboardWritingOptions)writingOptionsForType:(NSPasteboardType)type pasteboard:(NSPasteboard *)pasteboard {
	return 0;
}
	
- (id)pasteboardPropertyListForType:(NSPasteboardType)type {
	if ([type isEqualToString:kMTTiVoShowArrayPasteBoardType]) {
		return  [NSKeyedArchiver archivedDataWithRootObject:self];
	} else if ( [type isEqualToString:(NSString *)kUTTypeFileURL]) {
		for (MTTiVoShow * show in self.folder) {
			NSArray * files = [show copiesOnDisk];
			if (files.count > 0) {
				NSURL *URL = [NSURL fileURLWithPath:files[0] isDirectory:NO];
				id temp =  [URL pasteboardPropertyListForType:(id)kUTTypeFileURL];
				return temp;
			}
		}
		return nil;
	} else if ( [type isEqualToString:NSPasteboardTypeString]) {
		NSMutableString * result = [@"" mutableCopy];
		for (MTTiVoShow * show in self.folder) {
			NSString * episodePart = show.seasonEpisode.length >0 ?
				[NSString stringWithFormat:@"\t(%@)",show.seasonEpisode] :
				@""; //skip empty episode info
			NSString * protected = show.protectedShow.boolValue ? @"-CP":@"";
			[result appendString: [NSString stringWithFormat:@"%@\t%@%@%@\n" ,show.showDateString, show.showTitle, protected, episodePart]] ;
		}
		return [result copy];
	} else {
		return nil;
	}
}

+ (NSArray *)readableTypesForPasteboard:(NSPasteboard *)pasteboard {
	return @[kMTTiVoShowArrayPasteBoardType];
	
}
+ (NSPasteboardReadingOptions)readingOptionsForType:(NSString *)type pasteboard:(NSPasteboard *)pasteboard {
	if ([type compare:kMTTiVoShowArrayPasteBoardType] ==NSOrderedSame)
		return NSPasteboardReadingAsKeyedArchive;
	return 0;
}

-(void) encodeWithCoder:(NSCoder *)aCoder {
	[aCoder encodeObject:self.folder forKey:@"Folder"];
}

-(id)initWithCoder:(NSCoder *)aDecoder {
	if ((self = [self init])) {
		self.folder = [aDecoder  decodeObjectOfClasses:[NSSet setWithObjects:[MTTiVoShow class], [NSArray class], nil] forKey: @"Folder"] ;
	}
	return self;
}

+(BOOL) supportsSecureCoding {
	return YES;
}
@end

@implementation NSArray (FlattenShows)

-(NSArray < MTTiVoShow *> *) flattenShows {
	BOOL quickreturn = YES;
	for (id obj in self) {
		if (![ obj isKindOfClass:[MTTiVoShow class]]){
			quickreturn = NO;
			break;
		}
	}
	if (quickreturn) return self;
	NSMutableArray *result = [NSMutableArray arrayWithCapacity:[self count]];
	[self enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
		if ([ obj isKindOfClass:[MTShowFolder class]]){
			[result addObjectsFromArray:[(MTShowFolder*) obj folder]];
		} else if ([ obj isKindOfClass:[MTTiVoShow class]]){
			[result addObject: obj ];
		} //else delete other kinds of objects
	}];
	return [result copy];
}

@end
