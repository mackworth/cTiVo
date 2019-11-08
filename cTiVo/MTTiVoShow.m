//
//  MTTiVoShow.m
//  cTiVo
//
//  Created by Scott Buchanan on 12/18/12.
//  Copyright (c) 2012 Scott Buchanan. All rights reserved.
//
// Class for handling individual TiVo Shows

#import "MTTiVoShow.h"
#import "MTProgramTableView.h"
#import "MTTVDB.h"
#import "MTiTunes.h"
#import "MTTiVoManager.h"
#import "NSString+RFC3339Date.h"
#import "mp4v2.h"
#import "NSString+Helpers.h"
#import "NSNotificationCenter+Threads.h"
#import "NSString+Helpers.h"
#import "NSURL+MTURLExtensions.h"
#import "NSArray+Map.h"

typedef NS_ENUM(NSUInteger, MTImageSource) {
    //note this enum is referred to in Preference XIB and AppDelegate defaults
    MTSearchingSource = 0, //When we haven't found one yet, or waiting for rpc or tvdb
    MTTiVoSource,  //must be before all TVDB ones
    MTTVDBEpisode, //but if this fails, we delete old info and try for TVDBSeries instead
    MTTVDBSeason,  //ditto
    MTTVDBSeries,  //also movieDB
    MTNoSource, // no source is possible
};

@interface MTTiVoShow () {
	
	NSMutableString *elementString;
	NSMutableArray *elementArray;
	NSArray *arrayHolder;
	NSDictionary *parseTermMapping;

}
//rewrite external readonly properties (from detail XML) to allow internal readwrite
@property (atomic, strong, readwrite) NSString
                                *movieYear,
                                *originalAirDate,
                                *showTime,
                                *episodeGenre,
                                *colorCode,
                                *starRating,
                                *showingBits;
@property (strong, nonatomic, readwrite) NSAttributedString
                                *actors,
                                *guestStars,
                                *writers,
                                *directors,
                                *producers;

@property (nonatomic, strong) NSString *userSpecifiedArtworkFile;

@property (nonatomic, assign) BOOL ignoreSection; //are we skipping this section in XML (esp vActualShowing)

@property (atomic, assign) BOOL tvdbInProgress, imageInProgress;  //true if we're downloading info OR artwork.

@property (nonatomic, assign) MTImageSource lastImageSource;

@property (nonatomic, strong) NSString * clipMetaDataId;

#ifdef DEBUG
@property (nonatomic, strong) NSArray < MTEdl *> * previousEDL;
#endif
@end

@implementation MTTiVoShow

@synthesize seriesTitle		 = _seriesTitle,
			episodeTitle	 = _episodeTitle,
			episodeID    	 = _episodeID,
			imageString		 = _imageString,
			tempTiVoName     = _tempTiVoName ;

__DDLOGHERE__

-(id)init
{
    self = [super init];
    if (self) {
        _showID = 0;
		_gotDetails = NO;
		elementString = nil;
		self.inProgress = @(NO); //This is the default
		_season = 0;
		_episode = 0;
		_episodeNumber = @"";
        _isQueued = NO;
		_episodeTitle = @"";
		_seriesTitle = @"";
//		_originalAirDate = @"";
		_imageInProgress = NO;
		_tvdbInProgress = NO;
        _lastImageSource = MTSearchingSource;

		self.protectedShow = @(NO); //This is the default
		parseTermMapping = @{
					   @"description" : @"",  //mark to not load these values as they come from main XML, not detail
					   @"time"        : @"showTime",  //maybe this one also
					   @"seriesTitle" : @"",
					   @"episodeTitle": @"",
                       @"tvRating"    : @"",
                       @"mpaaRating"  : @"",
                       @"showingBits" : @"",  //and these two come from attributes, not surrounded text
                       @"colorCode"   : @"",
                       @"starRating"  : @""
		};
        [self addObserver:self forKeyPath:@"showTime" options:NSKeyValueObservingOptionNew context:showTimeContext];
        [self addObserver:self forKeyPath:@"episodeNumber" options:NSKeyValueObservingOptionNew context:episodeNumberContext];
        [self addObserver:self forKeyPath:@"movieYear" options:NSKeyValueObservingOptionNew context:movieYearContext];
        [self addObserver:self forKeyPath:@"originalAirDate" options:NSKeyValueObservingOptionNew context:originalAirDateContext];
    }
    return self;
}

#pragma mark - Queue encoding/decoding methods for persistent queue, copy/paste, and drag/drop

- (void) encodeWithCoder:(NSCoder *)encoder {
	//necessary for cut/paste drag/drop. 
	DDLogVerbose(@"encoding %@",self);
	[encoder encodeObject:[NSNumber numberWithInteger: _showID] forKey: kMTQueueID];
	[encoder encodeObject:_showTitle forKey: kMTQueueTitle];
	[encoder encodeObject:self.tiVoName forKey: kMTQueueTivo];
}

-(BOOL) isEqual:(id)object {
    MTTiVoShow * show = (MTTiVoShow *) object;
    if (show == self) return YES;
	if (![object isKindOfClass:[self class]]) return NO;
	return (self.showID == show.showID) &&
            [self.showTitle isEqualToString: show.showTitle] &&
            [self.tiVoName isEqualToString: show.tiVoName];
}

-(NSUInteger) hash {
    return [self.showTitle hash] ^
            self.showID ^
             [self.tiVoName hash];
}

-(void) setShowSeriesAndEpisodeFrom:(NSString *) newTitle {
	if (newTitle) {
		self.showTitle = newTitle;

		NSRange pos = [newTitle rangeOfString: @": "];
		//Normally this is built from episode/series; but if we got showtitle from
		//"old" queue, we'd like to temporarily display eps/series
		if (pos.location == NSNotFound) {
			if (_seriesTitle.length == 0) {
				self.seriesTitle = newTitle;
			}
		} else {
			if (_seriesTitle.length == 0) {
				self.seriesTitle = [newTitle substringToIndex:pos.location];
			}
			if (_episodeTitle.length == 0) {
				self.episodeTitle = [newTitle substringFromIndex:pos.location+pos.length];
			}
		}
	}
}


- (id)initWithCoder:(NSCoder *)decoder {
	//keep parallel with updateFromDecodedShow
	if ((self = [self init])) {
		//NSString *title = [decoder decodeObjectOfClass:[NSString class] forKey:kTitleKey];
		//float rating = [decoder decodeFloatForKey:kRatingKey];
        self.showID   =                  [[decoder decodeObjectOfClass:[NSNumber class] forKey: kMTQueueID] intValue];
		[self setShowSeriesAndEpisodeFrom:[decoder decodeObjectOfClass:[NSString class] forKey: kMTQueueTitle] ] ;
		NSString * tivoName =             [decoder decodeObjectOfClass:[NSString class] forKey: kMTQueueTivo] ;
		for (MTTiVo * tiVo in [tiVoManager tiVoList]) {
			if ([tiVo.tiVo.name compare: tivoName] == NSOrderedSame) {
				_tiVo = tiVo;
				break;
			}
		}
		if (!_tiVo) {
			self.tempTiVoName = tivoName;
		}
	}
	DDLogDetail(@"initWithCoder for %@",self);
	return self;
}

+(BOOL) supportsSecureCoding {
    return YES;
}

- (id)pasteboardPropertyListForType:(NSString *)type {
//	NSLog(@"QQQ:pboard Type: %@",type);
	if ([type isEqualToString:kMTTivoShowPasteBoardType]) {
		return  [NSKeyedArchiver archivedDataWithRootObject:self];
    } else if ( [type isEqualToString:(NSString *)kUTTypeFileURL]) {
        NSArray * files = [self copiesOnDisk];
        if (files.count > 0) {
            NSURL *URL = [NSURL fileURLWithPath:files[0] isDirectory:NO];
            id temp =  [URL pasteboardPropertyListForType:(id)kUTTypeFileURL];
            return temp;
        } else {
           return nil;
        }
    } else if ( [type isEqualToString:NSPasteboardTypeString]) {
        NSString * episodePart = self.seasonEpisode.length >0 ?
                                        [NSString stringWithFormat:@"\t(%@)",self.seasonEpisode] :
                                        @""; //skip empty episode info
        NSString * protected = self.protectedShow.boolValue ? @"-CP":@"";
        return [NSString stringWithFormat:@"%@\t%@%@%@" ,self.showDateString, self.showTitle, protected, episodePart] ;
    } else {
        return nil;
    }
}

-(NSArray *)writableTypesForPasteboard:(NSPasteboard *)pasteboard {
    if (self.isOnDisk) {
        return @[kMTTivoShowPasteBoardType, (NSString *)kUTTypeFileURL, NSPasteboardTypeString];
    } else {
        return @[kMTTivoShowPasteBoardType, NSPasteboardTypeString];
    }
}

- (NSPasteboardWritingOptions)writingOptionsForType:(NSString *)type pasteboard:(NSPasteboard *)pasteboard {
	return 0;
}

+ (NSArray *)readableTypesForPasteboard:(NSPasteboard *)pasteboard {
	return @[kMTTivoShowPasteBoardType];

}
+ (NSPasteboardReadingOptions)readingOptionsForType:(NSString *)type pasteboard:(NSPasteboard *)pasteboard {
	if ([type compare:kMTTivoShowPasteBoardType] ==NSOrderedSame)
		return NSPasteboardReadingAsKeyedArchive;
	return 0;
}

#pragma mark - GetDetails from Tivo and parse

-(NSURL *) detailFileURL {
    NSString *detailFilePath = [NSString stringWithFormat:@"%@_%d_Details.xml",self.tiVoName,self.showID]; //keep in sync with parseDetails
    if (@available (macOS 10.11, *)) {
        return [NSURL fileURLWithPath:detailFilePath isDirectory:NO relativeToURL:[tiVoManager detailsTempDirectory]];
    } else {
        return [[tiVoManager detailsTempDirectory] URLByAppendingPathComponent:detailFilePath];
    }
}

-(void)getShowDetail {
    //run on background queue to only allow a couple at a time running, so must be threadsafe
    //self.tivo, self.detailURL, and self.showID are read, but set long ago.

    @synchronized(self) {
        if (self.gotDetails) {
            return;
        }
        self.gotDetails = YES;
    }
    NSAssert(![NSThread isMainThread],@"getShowDetail NOT on background");
    NSURL * detailFileURL = [self detailFileURL];
    NSData *xml = nil;
    if ([detailFileURL fileExists]) {
        DDLogDetail(@"getting details for %@ from file %@", self, detailFileURL);
        xml = [NSData dataWithContentsOfURL:detailFileURL];
        //use fileModDate to know when to delete old detail files
        [detailFileURL setResourceValue:[NSDate date] forKey:NSFileModificationDate error:nil];
    } else {
        DDLogDetail(@"downloading details %@ from path %@", self, self.detailURL);
        NSURLResponse *detailResponse = nil;
        NSURLRequest *detailRequest = [NSURLRequest requestWithURL:self.detailURL];
        xml = [NSURLConnection sendSynchronousRequest:detailRequest returningResponse:&detailResponse error:nil];
        if (![_inProgress boolValue]) {
            [xml writeToURL:detailFileURL atomically:YES];
        }
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        [self parseDetails:xml firstTime:YES];
    });


}
-(void) parseDetails:(NSData *) xml  firstTime:(BOOL) firstTime {
    //parsing itself occurs on main thread to avoid multiaccess problems. measured < 1/1000 second
    DDLogVerbose(@"Got Details for %@: %@", self, [[NSString alloc] initWithData:xml encoding:NSUTF8StringEncoding	]);

    NSXMLParser * parser = [[NSXMLParser alloc] initWithData:xml];
    parser.delegate = self;
    self.ignoreSection = NO;
    [parser parse];
    if (!self.gotDetails) {
        //Tivo sometimes puts "&&amp" for "&amp"; if so, fix it and try again

        NSURL * detailURL = [self detailURL];
        NSString *xmlString =  [[NSString alloc] initWithData:xml encoding:NSUTF8StringEncoding	];
        if (firstTime && [xmlString contains:@"&&amp"]) {
            self.gotDetails = YES;
            DDLogMajor(@"Fixing TiVo &&amp bug for %@",_showTitle);
            xmlString = [xmlString stringByReplacingOccurrencesOfString:@"&&amp" withString:@"&amp"];
            NSData * revisedXML = [xmlString dataUsingEncoding:NSUTF8StringEncoding];
            [revisedXML writeToURL: detailURL atomically:YES];
            [self parseDetails:revisedXML firstTime:NO];
            return;
        } else {
            DDLogMajor(@"GetDetails %@fails for %@", firstTime? @"":@"really ",_showTitle);
            DDLogMajor(@"Returned XML is %@",xmlString);
            [[NSFileManager defaultManager] removeItemAtURL: detailURL error:nil];
        }
    }
    if (!self.tvdbData) {
        if (self.isMovie) {
            [tiVoManager.tvdb getTheMovieDBDetails:self ];
        } else {
            [tiVoManager.tvdb getTheTVDBDetails:self ];
        }
    }
    DDLogDetail(@"GetDetails parsing Finished: %@", self.showTitle);
    self.rpcData = [self.tiVo registerRPCforShow: self];
}

-(void) setClipMetaDataId:(NSString *)clipMetaDataId {
	//note we have to notify even if clipMetaData is nil, as this is the signal when we've completed one last check at timer expiry
	if ((_clipMetaDataId == nil) && (clipMetaDataId != nil)) {
		//newly arrived (although maybe from cache at startup)
		NSTimeInterval timeLeft = self.timeLeftTillRPCInfoWontCome;
		if (timeLeft > -24*60*60) {
			//don't report beyond a day
			NSTimeInterval timeSinceShow = -[self.showDate timeIntervalSinceNow] - self.showLength;
			int hrs = (timeSinceShow) / 60 / 60;
			CGFloat min = (timeSinceShow / 60.0) - hrs * 60.0;
			DDLogMajor(@"SkipMode MetaData arrived %@for %@; %d:%04.1f (hr:min) after show ended", (timeLeft < 0) ? @"late " : @"", self, hrs, min);
		}
	}
	if (_clipMetaDataId != clipMetaDataId) {
		_clipMetaDataId = clipMetaDataId;
		DDLogDetail(@"Notifying skipMode from %@", self);
		[[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationFoundSkipModeInfo object:self];
	} else {
		DDLogDetail(@"Not Notifying skipMode from %@", self);
	}
}

-(void) setEdlList:(NSArray<MTEdl *> *)edlList {
	if (_edlList != edlList) {
		_edlList = edlList;
		if (edlList != nil) {
			DDLogDetail(@"Got EDL for %@: %@", self, edlList);
			[[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationFoundSkipModeInfo object:self];
		}
	}
}

-(void) setMpegFormat:(MPEGFormat)mpegFormat {
	BOOL changed = (mpegFormat != self.rpcData.format);
	if (!self.rpcData) {
		_rpcData = [MTRPCData new];
	}
	self.rpcData.format = mpegFormat;
	if (changed) {
		[[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationDetailsLoaded object:self];
	}
}

-(void) setRpcData:(MTRPCData *)rpcData {
	if (rpcData) {
		if (_rpcData.format != MPEGFormatUnknown) {
			rpcData.format = _rpcData.format;
		}
		_rpcData = rpcData;
		self.episodeGenre = rpcData.genre;  //no conflict with TVDB
		if (rpcData.edlList != nil) self.edlList = rpcData.edlList;
		self.clipMetaDataId = rpcData.clipMetaDataId;  //notifies downloads
		[self checkAllInfoSources];
	}
}

-(void) setTvdbData:(NSDictionary<NSString *,id> *) tvdbData {
    if (tvdbData == _tvdbData ) return;
    _tvdbData = tvdbData;
    self.tvdbInProgress = NO;
    [self checkAllInfoSources];
}

-(NSTimeInterval) timeLeftTillRPCInfoWontCome {
	return [self timeLeftTillRPCInfoWontCome:1];
}

-(NSTimeInterval) timeLeftTillRPCInfoWontCome:(NSInteger) multiplier {
	NSTimeInterval longestAfterShow = [[NSUserDefaults standardUserDefaults ] integerForKey:kMTWaitForSkipModeInfoTime]*60;
	if (longestAfterShow ==0) longestAfterShow = kMTDefaultDelayForSkipModeInfo*60;
	longestAfterShow *= multiplier;
	NSTimeInterval timeToWait = longestAfterShow + [self.showDate timeIntervalSinceNow] + self.showLength;
	return timeToWait;
}

-(BOOL) mightHaveSkipModeInfoLongest {
	return [self mightHaveSkipModeInfo:[self timeLeftTillRPCInfoWontCome:3]];
}

-(BOOL) mightHaveSkipModeInfo {
	return [self mightHaveSkipModeInfo:[self timeLeftTillRPCInfoWontCome:1]];
}

-(BOOL) mightHaveSkipModeInfo:(NSTimeInterval) timeLeft {
//	NSInteger hour = 6;  //doesn't seem to be an actual limitation.
//	NSInteger minute = 45;
//	[[NSCalendar currentCalendar] getHour:&hour minute:NULL second:NULL nanosecond:NULL fromDate: self.showDate];
//	if (hour < 16 && !(hour == 0 && minute <=30)) return NO;
	if (!self.tiVo.supportsRPC) return NO;
	if (self.hasSkipModeInfo || self.hasSkipModeList) return YES;
	if (self.skipModeFailed) return NO;
	if (self.isSuggestion) return NO;
	if ([self.imageString isEqualToString:@"deleted"]) return NO;
	if (self.stationCallsign) {
		if ([tiVoManager skipModeForChannel:self.stationCallsign] != NSOnState) return NO;
		if ([tiVoManager commercialsForChannel:self.stationCallsign] != NSOnState) return NO;
	}
	NSString * genre = self.episodeGenre.lowercaseString;
	if (genre) {
		if ([genre isEqualToString:@"news"] ) return NO; //allow news magazine
		if ([genre isEqualToString:@"sports"] ) return NO;
	}
	if (!self.inProgress.boolValue && timeLeft < 0) {
		DDLogVerbose(@"No SkipMode for %@; Past deadline for SkipInfo to arrive by %0.1f", self, -timeLeft);
		return NO;
	} else {
		DDLogVerbose(@"Looks like we might still have SkipMode for %@", self);
		return YES;
	}
}

-(void) checkAllInfoSources {
    //assuming one of our info sources (Tivo XML, Tivo RPC, Manual, or TVDB) has changed, update our variables appropriately.
    if (self.isEpisodicShow) {
        // Doesn't even bother checking Tivo XML for episodes as it's not there anymore.

        MTRPCData * rpcData = self.rpcData;
        int episodeTVDB = ((NSString *)self.tvdbData [kTVDBEpisodeKey]).intValue;
        int seasonTVDB  = ((NSString *)self.tvdbData [kTVDBSeasonKey]) .intValue;
        int episodeRPC  = (int)rpcData.episodeNum;
        int seasonRPC   = (int)rpcData.seasonNum;

        if (rpcData.episodeNum == 0) {
            //if no TiVo RPC, then  use the Tivo XML, which only provides combo episodeNumber
            NSInteger len = _episodeNumber.length;
            if (len > 0)  {
               if (len > 2 && len < 6) {
                    //3,4,5 ok: 3 = SEE 4= SSEE 5 = SSEEE
                    //4 might be corrected by tvdb to SEEE
                    int epDigits = (len > 4) ? 3:2;
                    self.episode = [[_episodeNumber substringFromIndex:len-epDigits] intValue];
                    self.season = [[_episodeNumber substringToIndex:len-epDigits] intValue];
                   if (len == 4) {
                       //check with TVDB on parsing SSEE or SEEE
                       if (self.season/10 == seasonTVDB  && episodeTVDB == self.episode + (self.season % 10)*10) {
                           //must have mis-parsed
                           self.episode = episodeTVDB;
                           self.season = seasonTVDB;
                       }
                   }
                } else {
                    self.episode = [_episodeNumber intValue];
                }
            }
        }
        BOOL useTiVoData = ![[NSUserDefaults standardUserDefaults] integerForKey:kMTTrustTVDBEpisodes];

        //check if tivo and TVDB disagree on season
        if (episodeRPC > 0 && episodeTVDB >0 && (episodeTVDB!= episodeRPC || seasonTVDB != seasonRPC)) {
            NSString * details = [NSString stringWithFormat:@"TVDB has %d/%d v TiVo %d/%d; %@ aired %@; %@ ",seasonTVDB, episodeTVDB, seasonRPC, episodeRPC, self.seriesId, self.originalAirDateNoTime,  self.tvdbData[kTVDBURLsKey]];
            DDLogDetail(@"TheTVDB has different Sea/Eps info for %@: %@ %@", self.showTitle, details, useTiVoData ? @"leaving": @"updating" );
        }

        if ((useTiVoData && episodeRPC > 0) ||
            (episodeTVDB == 0)) {
            self.episode = episodeRPC;
            self.season  = seasonRPC;
        } else if (episodeTVDB > 0) {
            self.episode = episodeTVDB;
            self.season  = seasonTVDB;
        }
        //finally check for user override
        NSDictionary * manualInfo = [tiVoManager getManualInfo:self];
        if (manualInfo[@"episode"]) self.episode =  ((NSNumber *)manualInfo[@"episode"]).intValue;
        if (manualInfo[@"season"]) self.season =  ((NSNumber *)manualInfo[@"season"]).intValue;
    }
    //now handle artwork
    self.thumbnailFile = nil;
    self.thumbnailImage = nil;
    [[ NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationDetailsLoaded object:self];
}

#pragma  mark - parser methods


-(void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName attributes:(NSDictionary *)attributeDict
{
    if (self.ignoreSection) return;
    
    if ([elementName isEqualToString:@"vActualShowing"]) {
       self.ignoreSection = YES;
       return;
   }

   elementString = [NSMutableString new];
   if (![elementName isEqualToString:@"element"]) {
       elementArray = [NSMutableArray new];

       if (attributeDict.count > 0) {
           NSString * value = [attributeDict objectForKey:@"value"];
           if (value.length == 0) return;
           if ([elementName isEqualToString:@"showingBits"]) {  //ignore spurious zero entries
               if (self.showingBits.integerValue > 0 && [value isEqualToString:@"0"])  return;
               self.showingBits = value;
           } else if ([elementName isEqualToString:@"colorCode"]) {
               self.colorCode = value;
           } else if ([elementName isEqualToString:@"starRating"]) {
               self.starRating = value;
           }
       }
   }
}

-(void)parser:(NSXMLParser *)parser foundCharacters:(NSString *)string
{
    if (self.ignoreSection) return;
    [elementString appendString:string];
}

- (void)setValue:(id)value forUndefinedKey:(NSString *)key{
    //nothing to see here; just move along
    DDLogVerbose(@"Unrecognized key %@", key);
}

-(void) endElement:(NSString *)elementName item:(id) item {
    DDLogVerbose(@"%@: %@",elementName, item);

}

-(void)parser:(NSXMLParser *)parser didEndElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName
{
    if ([elementName isEqualToString:@"vActualShowing"]) {
        self.ignoreSection = NO;
        return;
    }
    if (self.ignoreSection) return;
    if (parseTermMapping[elementName]) {
		elementName = parseTermMapping[elementName];
	}
	if ([elementName compare:@"element"] == NSOrderedSame) {
        if (elementName.length > 0) {
            [elementArray addObject:elementString];
        }
	} else if (elementName.length != 0) {
		id item;
		if (elementArray.count) {
			item = [NSArray arrayWithArray:elementArray];
		} else {
			item = elementString;
		}
		@try {
            [self setValue:item forKeyPath:elementName];
            [self endElement: elementName item: item];
		}
		@catch (NSException *exception) {
		}
		@finally {
		}
	}
}

-(void)parser:(NSXMLParser *)parser parseErrorOccurred:(NSError *)parseError
{
	self.gotDetails = NO;
    DDLogMajor(@"Show: %@ Parser Error %@",self.showTitle, parseError);

}

#pragma mark - Custom Getters

-(NSString *) seasonEpisode {
    NSString *returnString = @"";
    if (self.episode > 0) {
			returnString = [NSString stringWithFormat:@"S%0.2dE%0.2d",self.season,self.episode ];
    } else if (self.isEpisodicShow) {
        returnString = self.episodeNumber;
    } else {
        return @"";  //non-episodic shows don't have episodes
    }
    return returnString;
}

-(NSString *) seriesFromProgram:(NSString *) name {
    NSArray * nameParts = [name componentsSeparatedByString: @":"];
    if (nameParts.count == 0) return name;
    return [nameParts objectAtIndex:0];
}

-(NSString * ) seriesTitle {
    if (!_seriesTitle) {
        self.seriesTitle = [self seriesFromProgram:self.showTitle];
    }
    return _seriesTitle;
}

-(BOOL) isMovie {
	return [self.episodeID hasPrefix:@"MV"];
}

-(BOOL) isEpisodicShow {
    return [self.episodeID hasPrefix:@"EP"];
}

-(NSAttributedString *) attributedString: (NSString *) text {
	return [[NSAttributedString alloc] initWithString: text
										   attributes:@{NSFontAttributeName :           [NSFont systemFontOfSize:11],
														NSForegroundColorAttributeName: [NSColor textColor] }];
}

-(NSAttributedString *)attrStringFromDictionaries:(NSArray *)nameList {
	NSString * returnValue = @"";
	if ([nameList isKindOfClass:[NSArray class]]) {
		NSArray <NSString *> * names = [nameList mapObjectsUsingBlock:^id(NSDictionary * name, NSUInteger idx) {
			return [self nameString:name];
		} ];
		returnValue = [names componentsJoinedByString:@"\n"];
	}
	return [self attributedString:returnValue];
}

-(NSAttributedString *)attribDescription {
	return [self attributedString: self.showDescription ?: @""];
}

-(NSString *)seasonString
{
	NSString *returnString = @"";
	if (self.season > 0) {
		returnString = [NSString stringWithFormat:@"%d",self.season];
	}
    return returnString;
}


-(MTTiVo *) tiVo {
	if (!_tiVo) {
		for (MTTiVo * possibleTiVo in tiVoManager.tiVoList) {
			if ([possibleTiVo.tiVo.name isEqualToString:self.tempTiVoName]) {
				self.tiVo = possibleTiVo;
				break;
			}
		}
	}
	return _tiVo;
}

- (NSArray *) dictArrayFromString:(NSAttributedString *) string {
    NSArray * data = [string.string componentsSeparatedByString: @"\n" ];
    NSMutableArray *dictElements = [NSMutableArray array];
    for (NSString *name in data) {
        if (name.length == 0) continue;
        //tivo likes it LastName|First Names
        NSArray * names = [name componentsSeparatedByString:@" "];
        NSString * lastName = [names lastObject]; //e.g. Maggie Smith  12char total  5last 6first
        NSInteger length = name.length-lastName.length -1;
        NSString * firstNames = (length > 0) ? [name substringToIndex:length] : @"";
        NSString * tivoName = [NSString stringWithFormat:@"%@|%@", lastName, firstNames];

        [dictElements addObject:[NSDictionary dictionaryWithObject:tivoName forKey:@"name"]];
    }
    return dictElements;
}

-(NSString *) iTunesCode {
    NSUInteger index;
    NSArray *codeArray;
    if (self.isMovie) {
       codeArray =@[
             @"" ,  //mpaa|NR|000?
             @"mpaa|G|100",
             @"mpaa|PG|200",
             @"mpaa|PG-13|300",
             @"mpaa|R|400",
             @"mpaa|NC-17|500",
             @"mpaa|Unrated|???"];
        index = self.mpaaRating > 0 ? self.mpaaRating: 0 ;
    } else {
        codeArray = @[
             @"",
             @"us-tv|TV-Y|100",
             @"us-tv|TV-Y7|200",
             @"us-tv|TV-G|300",
             @"us-tv|TV-PG|400",
             @"us-tv|TV-14|500",
             @"us-tv|TV-MA|600"];
        index = self.tvRating > 0 ? self.tvRating: 0;
    }
    if (index < codeArray.count) {
        return codeArray[index];
    } else {
        return codeArray[0];
    }
}

-(NSString *) starRatingString {
    if  (self.starRating.intValue == 0) return @"";
    int numHalfStars = self.starRating.intValue + 1;
    NSString * stars = [@"★★★★★" substringToIndex: numHalfStars/2];
    if (numHalfStars & 1) {
        stars = [stars stringByAppendingString:@"½"];
    }
    return stars;
}

-(NSString *)showDateString
{
	static NSDateFormatter *dateFormat;
	if(!dateFormat) {
		dateFormat = [[NSDateFormatter alloc] init] ;
		[dateFormat setDateStyle:NSDateFormatterShortStyle];
		[dateFormat setTimeStyle:NSDateFormatterShortStyle] ;
	}
//	[dateFormat setTimeStyle:NSDateFormatterNoStyle];
	return [dateFormat stringFromDate:_showDate];
}
-(NSString *) showTitlePlusAirDate {
    return [NSString stringWithFormat: @"%@%@",self.showTitle, self.originalAirDateNoTime];
}

-(NSString *)showMediumDateString
{
	static NSDateFormatter *dateFormat;
	if(!dateFormat) {
		dateFormat = [[NSDateFormatter alloc] init] ;
		[dateFormat setDateStyle:NSDateFormatterMediumStyle];
		[dateFormat setTimeStyle:NSDateFormatterShortStyle] ;
	}
	//	[dateFormat setTimeStyle:NSDateFormatterNoStyle];
	return [dateFormat stringFromDate:_showDate];
}

-(NSString *)showDateRFCString {
    NSDateComponents *components = [[NSCalendar currentCalendar]
                                    components:NSCalendarUnitDay | NSCalendarUnitMonth | NSCalendarUnitYear |NSCalendarUnitWeekday  |
                                    NSCalendarUnitMinute | NSCalendarUnitHour
                                    fromDate:self.showDate];

    return [NSString stringWithFormat:@"%04ld-%02ld-%02ld",
                    [components year] ,
                    [components month],
                    [components day]];

}

-(BOOL) isOnDisk {
    return [tiVoManager copiesOnDiskForShow: self] != nil;
}

-(BOOL) isFolder {
	return NO;
}

-(NSArray <NSString *> *) copiesOnDisk {
    return [tiVoManager copiesOnDiskForShow: self];
}

-(NSString *) isOnDiskString {
    return [self checkString: self.isOnDisk];
}

-(NSString *) h264String {
	if (self.rpcData.format != MPEGFormatUnknown) {
		if (self.rpcData.format == MPEGFormatH264) {
			return @"✔";
		} else {
			return @"--";
		}
	} else {
		NSCellStateValue state = [tiVoManager failedPSForChannel:self.stationCallsign];
		switch (state) {
			case NSOffState: {
				return @"-";
			}
			case NSOnState: {
				return @"√";
			}
			default: {
				return @"";
			}
		}
	}
}

-(NSString *)checkString:(BOOL) test {
  return test ? @"✔" : @"";
}

-(NSString*) lengthString {
	NSInteger length = (_showLength+30)/60; //round up to nearest minute;
	return [NSString stringWithFormat:@"%ld:%0.2ld",length/60,length % 60];
}
												  
-(NSString*) isQueuedString {
  return [self checkString: _isQueued];
}
												  
-(NSString*) isHDString {
	return [self checkString:_isHD.boolValue];
}

-(NSString*) imageString {
	if (self.protectedShow.boolValue && !self.inProgress.boolValue) {
		if (self.fileSize > 0) {
			return @"copyright";
		} else {
			//not loaded yet
			return @"status-unknown";
		}
	}
	if (_imageString.length) {
		return _imageString;
	} else {
		return @"recent-recording";
	}
}

-(NSString*) idString {
    return[NSString stringWithFormat:@"%d", _showID ];
}

-(NSNumber*) idNumber {
    return @(_showID);
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-property-ivar"
-(NSString *) ageRatingString {
    NSUInteger index;
    NSArray * ratingArray;
    if  (self.mpaaRating > self.tvRating) {
        index  = self.mpaaRating > 0 ? self.mpaaRating : 0;
        ratingArray = @[ @"", @"G", @"PG", @"PG-13",  @"R", @"NC-17"];
    } else {
        index = self.tvRating > 0 ? self.tvRating : 0;
        ratingArray = @[ @"", @"TV-Y", @"TV-Y7", @"TV-G",  @"TV-PG", @"TV-14", @"TV-MA"];
    }
    if ( index < ratingArray.count ) {
        return ratingArray[index];
    } else {
        return @"";
    }
}

-(NSNumber *) ageRatingValue {
    return @(MAX(self.mpaaRating , self.tvRating));
}


-(NSString*) sizeString {
  
  if (_fileSize >= 1000000000) {
	  return[NSString stringWithFormat:@"%0.1fGB",_fileSize/(1000000000)];
  } else if (_fileSize > 0) {
	  return[NSString stringWithFormat:@"%ldMB",((NSInteger)_fileSize)/(1000000) ];
  } else {
	  return @"-";
  }
}

-(NSString *) combinedChannelString {
	if (!self.channelString) return @"";
	return  [NSString stringWithFormat:@"%@-%@ %@",
			 self.stationCallsign,
			 self.channelString,
			 self.isHD.boolValue? @"HD": @""];
}

-(NSNumber *) channelNumber {
    NSInteger channel = self.channelString.integerValue;
    if (!channel) return @(NSIntegerMax);
    return @(channel);

}

-(NSString *) tiVoName {
	if (_tiVo) {
		return _tiVo.tiVo.name;
	} else {
		return self.tempTiVoName;
	}
}

-(NSString *) episodeID {
    if (!_episodeID) {
		_episodeID = _programId;
		if (_programId && _episodeID.length < 14) {
            NSUInteger numtoInsert = 14-_episodeID.length;
			_episodeID = [NSString stringWithFormat:@"%@%@%@",[_episodeID substringToIndex:2],[@"00000000000000" substringToIndex:numtoInsert],[_episodeID substringFromIndex:2]];
		}
//		if (![_episodeID hasPrefix:@"MV"] && [_episodeID hasSuffix:@"0000"] ) {
//                NSDateFormatter *dateFormat = [[NSDateFormatter alloc] init] ;
//                [dateFormat setDateStyle:NSDateFormatterShortStyle];
//                [dateFormat setTimeStyle:NSDateFormatterNoStyle] ;
//			_episodeID = [NSString stringWithFormat: @"%@-%@",_episodeID, [dateFormat stringFromDate: _showDate] ];
//		}
	}
    return _episodeID;
}

-(NSString *) uniqueID {
    if (self.isEpisodicShow) {
        return self.episodeID;
    } else {
        return [self.episodeID stringByAppendingFormat:@"-%@", self.showDateRFCString];
    }
}

- (BOOL) hasSkipModeList {
	return self.rpcData.edlList.count > 0;
}

- (BOOL) hasSkipModeInfo {
	return self.rpcData.clipMetaDataId != nil && !self.rpcData.skipModeFailed;
}

- (BOOL) skipModeFailed {
	return self.rpcData.skipModeFailed;
}

-(NSNumber *) rpcSkipMode { //only for sorting in tables
	if ([self hasSkipModeList]) return @3;
	if (self.edlList.count > 0) return @5;
	if ([self skipModeFailed]) return @2;
	if ([self hasSkipModeInfo]) return @1;
	if (self.protectedShow.boolValue) return @0;
	if ([self mightHaveSkipModeInfo ]) return @4;
	return @0;
}

-(MPEGFormat) mpegFormat {
	return self.rpcData.format;
}

#pragma mark - Custom Setters; many for parsing
#define kMTFirstName @"MTFirstName"
#define kMTLastName @"MTLastName"

-(NSString *)nameString:(NSDictionary *)nameDictionary
{
    return [NSString stringWithFormat:@"%@ %@",nameDictionary[kMTFirstName] ? nameDictionary[kMTFirstName] : @"" ,nameDictionary[kMTLastName] ? nameDictionary[kMTLastName] : @"" ];
}


-(void) setProgramId:(NSString *)programId {
    if (programId != _programId) {
        _programId = programId;
        _episodeID = nil;
    }
}

-(void)setShowLengthString:(NSString *)showLengthString
{
    if (showLengthString != _showLengthString) {
        _showLengthString = showLengthString;
        _showLength = [_showLengthString longLongValue]/1000;
    }
}
static void * showTimeContext = &showTimeContext;
static void * episodeNumberContext = &episodeNumberContext;
static void * movieYearContext = &movieYearContext;
static void * originalAirDateContext = &originalAirDateContext;

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context {
    if (context == showTimeContext) {
        NSDate *newDate =[_showTime dateForRFC3339DateTimeString];
        if (newDate) {
            self.showDate = newDate;
        }

    } else if (context == episodeNumberContext) {
        if (_episodeNumber.length) {
            [self checkAllInfoSources];
        }
    } else if (context == movieYearContext) {
        if (self.originalAirDateNoTime.length == 0) {
            _originalAirDateNoTime = self.movieYear;
        }
    } else if (context == originalAirDateContext) {

        if (!self.isEpisodicShow && self.showDate) {
            _originalAirDateNoTime = [self showDateRFCString];
        } else if (_originalAirDate.length >= 10) {
            _originalAirDateNoTime = [_originalAirDate substringToIndex:10];
        } else if (_originalAirDate.length > 0) {
            _originalAirDateNoTime = _originalAirDate;
        } else if (_movieYear.length > 0){
            _originalAirDateNoTime = _movieYear;
        }
    } else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

-(void) setImageString:(NSString *)imageString {
	if (imageString != _imageString) {
		_imageString = imageString;
		_isSuggestion = [@"suggestion-recording" isEqualToString:imageString];
	}
}

-(BOOL) playVideo {
	NSArray <NSString *> * paths = [self copiesOnDisk];
	if (paths.count == 0) return NO;
	NSString *path = paths[0];
	DDLogMajor(@"Playing video %@ ", path);
    [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:path]];
	return YES;
}

-(void) playOnTiVo {
	[self.tiVo playShow:self];
}

-(void) setShowDate:(NSDate *)showDate {
    if (showDate != _showDate) {
        _showDate = showDate;
        if (_originalAirDateNoTime.length == 0 && showDate) {
            _originalAirDateNoTime = [self showDateRFCString];
        }
    }
}

-(void)setInProgress:(NSNumber *)inProgress
{
  if (_inProgress != inProgress) {
	  _inProgress = inProgress;
	  if ([_inProgress boolValue]) {
		  self.protectedShow = @(YES);
	  }
  }
}


-(void)setSeriesTitle:(NSString *)seriesTitle
{
	if (_seriesTitle != seriesTitle) {
        _seriesTitle =seriesTitle;
		if (_episodeTitle.length > 0 ) {
			self.showTitle =[NSString stringWithFormat:@"%@: %@",_seriesTitle, _episodeTitle];
		} else {
            if ([_episodeID hasPrefix:@"EP"] &&
                [seriesTitle contains:@": "]) {
                NSArray * splitTitle = [seriesTitle componentsSeparatedByString:@": "];
                if (splitTitle.count > 0) {
                    _seriesTitle = splitTitle[0];
                    _episodeTitle = splitTitle[1];
                }
            }
			self.showTitle =seriesTitle;
		}
	}
}

-(void)setEpisodeTitle:(NSString *)episodeTitle
{
	if (_episodeTitle != episodeTitle) {
		_episodeTitle = episodeTitle;
		if (_episodeTitle.length > 0 ) {
			self.showTitle =[NSString stringWithFormat:@"%@: %@",_seriesTitle, _episodeTitle];
		} else {
			self.showTitle =_seriesTitle;
		}
	}
}

-(void)setShowDescription:(NSString *)showDescription
{
	if (_showDescription == showDescription) {
		return;
	}
    NSString * roviCopyright = @" Copyright Rovi, Inc.";
     if ([showDescription hasSuffix: roviCopyright]){
        NSInteger lengthTokeep = showDescription.length -roviCopyright.length;
        if (lengthTokeep > 0 && [showDescription characterAtIndex:lengthTokeep-1 ] == '*' ) lengthTokeep--;
        _showDescription = [showDescription substringToIndex:lengthTokeep];
    } else {
        NSString * tribuneCopyright = @" Copyright Tribune Media Services, Inc.";
        if ([showDescription hasSuffix: tribuneCopyright]){
            _showDescription = [showDescription substringToIndex:showDescription.length -tribuneCopyright.length];
        } else {
            _showDescription = showDescription;
        }
    }
}

-(NSAttributedString *)parseNames:(NSArray *)nameSet
{
    if (!nameSet || ![nameSet respondsToSelector:@selector(count)] || nameSet.count == 0 ) { //|| [nameSet[0] isKindOfClass:[NSString class]]) {
        return [[NSAttributedString alloc] initWithString:@""] ;
    }
    NSRegularExpression *nameParse = [NSRegularExpression regularExpressionWithPattern:@"([^|]*)\\|([^|]*)" options:NSRegularExpressionCaseInsensitive error:nil];
    NSMutableArray *newNames = [NSMutableArray array];
    for (NSString *name in nameSet) {
        NSTextCheckingResult *match = [nameParse firstMatchInString:name options:NSMatchingWithoutAnchoringBounds range:NSMakeRange(0, name.length)];
        NSString *lastName = [name substringWithRange:[match rangeAtIndex:1]];
        NSString *firstName = [name substringWithRange:[match rangeAtIndex:2]];
        [newNames addObject:@{kMTLastName : lastName, kMTFirstName : firstName}];
    }
    return [self attrStringFromDictionaries:newNames];
}

-(NSAttributedString *) appendNames: (NSArray *) names to: (NSAttributedString *) stringA {
	NSAttributedString * temp = [self parseNames:names];
	
	if (stringA.string.length == 0) {
		return temp;
	} else {
		return [self attributedString: [NSString stringWithFormat: @"%@\n%@",stringA.string, temp.string]];
	}
}

-(void)setVActor:(NSArray *)vActor {
    self.actors = [self parseNames: vActor ]  ;
}

-(void)setVGuestStar:(NSArray *)vGuestStar {
	self.guestStars = [self parseNames: vGuestStar ];
}

-(void)setVDirector:(NSArray *)vDirector {
	self.directors = [self parseNames: vDirector ];
}

-(void)setVWriter:(NSArray*) vWriter {
    self.writers = [self parseNames: vWriter ];
}

-(void)setVExecProducer:(NSArray *)vExecProducer {  //we just merge producers and exec producers together
    self.producers = [self appendNames:vExecProducer to:self.producers];
}

-(void)setVProducer:(NSArray *)vProducer {
	[self setVExecProducer:vProducer];
}

-(void) setSeasonEpisode:(NSString *)seasonEpisode {
    DDLogDetail(@"Setting seasonEpisode of %@ to %@", self, seasonEpisode);
    static NSRegularExpression *seRegex;
    if (!seRegex) {
        seRegex = [NSRegularExpression regularExpressionWithPattern:@"S([0-9]+)\\s*E([0-9]+)" options:NSRegularExpressionCaseInsensitive error:nil];
    }
    NSTextCheckingResult *result = seasonEpisode ? [seRegex firstMatchInString:seasonEpisode options:NSMatchingWithoutAnchoringBounds range:NSMakeRange(0, seasonEpisode.length)] : nil;
    if (result) {
        NSInteger season  = [[seasonEpisode substringWithRange:[result rangeAtIndex:1]] intValue];
        NSInteger episode = [[seasonEpisode substringWithRange:[result rangeAtIndex:2]] intValue];
        NSDictionary * info = @{@"season": @(season),
                                @"episode": @(episode)};
        [tiVoManager updateManualInfo:info forShow:self];
    } else {
        [tiVoManager updateManualInfo:nil forShow:self];
    }
    [self checkAllInfoSources];
}

#pragma clang diagnostic pop

-(void)setVProgramGenre:(NSArray *)vProgramGenre
{
	if (![vProgramGenre isKindOfClass:[NSArray class]] ||
        vProgramGenre.count == 0) {
		return;
	}
    self.episodeGenre = [vProgramGenre[0] stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"\""]];

}

-(void)setVSeriesGenre:(NSArray *)vSeriesGenre{
    if (![vSeriesGenre isKindOfClass:[NSArray class]] ||
        vSeriesGenre.count == 0) {
        return;
    }
    self.episodeGenre = [vSeriesGenre[0] stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"\""]];
    
}


#pragma mark - Keyword Processing:
/*
 From KMTTG:
 [title] = The Big Bang Theory – The Loobenfeld Decay
 [mainTitle] = The Big Bang Theory
 [episodeTitle] = The Loobenfeld Decay
 [channelNum] = 702
 [channel] = KCBSDT
 [min] = 00
 [hour] = 20
 [wday] = Mon
 [mday] = 24
 [month] = Mar
 [monthNum] = 03
 [year] = 2008
 [originalAirDate] = 2007-11-20
 [EpisodeNumber] = 302
 [tivoName]
 [/]


 By request some more advanced keyword processing was introduced to allow for conditional text.

 You can define multiple space-separated fields within square brackets.
 Fields surrounded by quotes are treated as literal text.
 A single field with no quotes should be supplied which represents a conditional keyword
 If that keyword is available for the show in question then the keyword value along with any literal text surrounding it will be included in file name.
 If the keyword evaluates to null then the entire advanced keyword becomes null.
 For example:
 [mainTitle]["_Ep#" EpisodeNumber]_[wday]_[month]_[mday]
 The advanced keyword is highlighted in bold and signifies only include “_Ep#xxx” if EpisodeNumber exists for the show in question. “_Ep#” is literal string to which the evaluated contents of EpisodeNumber keyword are appended. If EpisodeNumber does not exist then the whole advanced keyword evaluates to empty string.

 Added to KMTTG:
 startTime
 seriesEpNumber
 TivoName
 TVDBSeriesID
 plexID
	OR (|) option, uses second keyword if first is empty
	Embedded optional values [ this option [with this embedded option] ]


 */

//test routines moved to Advanced Preferences

- (NSString *) replacementForKeyword:(NSString *) key usingDictionary: (NSDictionary*) keys {
    NSMutableString * outStr = [NSMutableString string];

    NSScanner *scanner = [NSScanner scannerWithString:key];
    [scanner setCharactersToBeSkipped:nil];
    NSCharacterSet * whitespaceSet = [NSCharacterSet whitespaceCharacterSet];
    NSCharacterSet * brackets = [NSCharacterSet characterSetWithCharactersInString:@"[]"];
    BOOL skipOne = NO;  //have we found a good alternative, so skip the rest?
    NSString * foundKey;

    while (![scanner isAtEnd]) {
        [scanner scanCharactersFromSet:whitespaceSet intoString:nil];
        //get any literal characters
        if ([scanner scanString:@"\"" intoString:nil]) {
            NSString * tempString;
            if ([scanner scanUpToString: @"\"" intoString:&tempString]) {
                if (skipOne) {
                    skipOne = NO;
                } else {
                    [outStr appendString:tempString];
                }
            } //else no chars scanned before quote (or end of line), so ignore this quote
            [scanner scanString:@"\"" intoString:nil];
            [scanner scanCharactersFromSet:whitespaceSet intoString:nil];
        } else if ([scanner scanString:@"[" intoString:nil]) {
            //get any recursive fields
            NSString * tempString;
            int numBrackets = 1;
            NSMutableString *bracketedString = [NSMutableString string];
            tempString = @"";
            while (numBrackets > 0) {
                [bracketedString appendString:tempString];  //get recursive [ if any
                if ([scanner scanUpToCharactersFromSet:brackets intoString:&tempString]) {
                    [bracketedString appendString:tempString];
                }
                if ([scanner scanString:@"[" intoString:&tempString]) {
                    numBrackets++;
                } else if ([scanner scanString:@"]" intoString:&tempString]) {
                    numBrackets--;
                }
            }
            [scanner scanCharactersFromSet:whitespaceSet intoString:nil];
            if (skipOne) {
                skipOne = NO;
            } else {
                [outStr appendString: [self replacementForKeyword:bracketedString usingDictionary:keys]];
            }
        } else if ([scanner scanString:@"|" intoString:nil]) {
            //got an alternative, but previous one must have been good (or we'd have eaten this)
            skipOne = YES;
        } else  {
            //not space, quote, alternative or recursive, so get keyword and replace with value from Dictionary
            if ([scanner scanUpToString:@" " intoString:&foundKey]) {
                if (skipOne) {
                    skipOne = NO;
                } else {
					NSString * foundValue = keys[foundKey.lowercaseString];
					if (!foundValue) {
                        DDLogReport(@"Unknown template key: %@",foundKey);
                        [outStr appendFormat:@"(UNKNOWN KEYWORD-'%@')",foundKey];
					} else if (foundValue.length == 0) {
                        DDLogVerbose(@"Empty key: %@",foundKey);
                        //found empty key so entire conditional fails and should be empty; ignore everything else, unless there's an OR (vertical bar)
                        [scanner scanCharactersFromSet:whitespaceSet intoString:nil];
                        if ([scanner scanString:@"|" intoString:nil]) {
                            //ah, we've got an alternative, so let's keep going
                        } else {
                            return @"";
                        }
                    } else {
                        DDLogVerbose(@"Swapping key %@ with %@",foundKey, foundValue);
                        [outStr appendString:foundValue];
                    }
                }
            }
        } //else no chars scanned before ] (or end of line) so ignore this
    }
    return [NSString stringWithString:outStr];
}

NSString * twoChar(long n, BOOL allowZero) {
    if (!allowZero && n == 0) return @"";
    return [NSString stringWithFormat:@"%02ld", n];
}
NSString * fourChar(long n, BOOL allowZero) {
    if (!allowZero && n == 0) return @"";
    return [NSString stringWithFormat:@"%04ld", n];
}

#define NULLT(x) (x ?: @"")

-(NSString *) swapKeywordsInString: (NSString *) str withFormat:(NSString *) format andOptions:(NSString *) options{
    NSDateComponents *components;
    if (self.showDate) {
        components = [[NSCalendar currentCalendar]
                      components:NSCalendarUnitDay | NSCalendarUnitMonth | NSCalendarUnitYear |NSCalendarUnitWeekday  |
                      NSCalendarUnitMinute | NSCalendarUnitHour
                      fromDate:self.showDate];
    } else {
        components = [[NSDateComponents alloc] init];
    }
    NSString * originalAirDate =self.originalAirDateNoTime;
    if (!originalAirDate && [components year] > 0) {
        originalAirDate = [NSString stringWithFormat:@"%@-%@-%@",
                           fourChar([components year], NO),
                           twoChar([components month], YES),
                           twoChar([components day], YES)];
    }
    NSString * monthName = ([components month]> 0 && [components month] != NSUndefinedDateComponent) ?
    [[[[NSDateFormatter alloc] init] shortMonthSymbols]
     objectAtIndex:[components month]-1] :
    @"";

    NSString *TVDBseriesID = [[tiVoManager.tvdb seriesIDsForShow:self] componentsJoinedByString:@","];
    NSString * guests = [[self.guestStars.string componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]] componentsJoinedByString:@","];
    NSString * extraEpisode = @"";
    if (self.episode && self.season &&   //if we have an SxxExx AND either a 2 hr show OR a semicolon in episode title, then it might be a double episode
        ((self.showLength > 115*60 && self.showLength < 125*60) ||
         ([self.episodeTitle contains:@";"]))) {
            extraEpisode = [NSString stringWithFormat:@"E%02d",self.episode+1];
        }
    NSDictionary * keywords = @{  //lowercase so we can just lowercase keyword when found
                                @"/":				@"|||",						//allows [/] for subdirs
                                @"title":			NULLT(self.showTitle) ,
                                @"maintitle":		NULLT(self.seriesTitle),
                                @"episodetitle":	NULLT(self.episodeTitle),
                                @"channelnum":		NULLT(self.channelString),
                                @"channel":		    NULLT(self.stationCallsign),
                                @"starttime":		NULLT(self.showTime),
                                @"min":			    twoChar([components minute], YES),
                                @"hour":			twoChar([components hour], YES),
                                @"wday":			twoChar([components weekday], NO),
                                @"mday":			twoChar([components day], NO),
                                @"month":			monthName,
                                @"monthnum":		twoChar([components month], NO),
                                @"year": 			self.isMovie ? @"" : fourChar([components year], NO),
                                @"originalairdate": originalAirDate,
                                @"episode":		    twoChar(self.episode, NO),
                                @"extraepisode":    NULLT(extraEpisode),
                                @"season":			twoChar(self.season, NO),
                                @"episodenumber":	NULLT(self.episodeNumber),
                                @"StartTime":       NULLT(self.startTime),
                                @"seriesepnumber":  NULLT(self.seasonEpisode),
                                @"guests":          NULLT(guests),
                                @"tivoname":		NULLT(self.tiVoName),
                                @"movieyear":		NULLT(self.movieYear),
                                @"tvdbseriesid":	NULLT(TVDBseriesID),
                                @"format":          NULLT(format),
                                @"options":         NULLT(options)
                                //         @"plexid":        [self ifString: self.show.seasonEpisode
                                //                                elseString: originalAirDate],
                                //         @"plexseason":    [self ifString: twoChar(self.show.season, NO)
                                //                                 elseString: fourChar([components year], NO) ]
                                };
    NSMutableString * outStr = [NSMutableString string];

    NSScanner *scanner = [NSScanner scannerWithString:str];
    [scanner setCharactersToBeSkipped:nil];
    NSCharacterSet * brackets = [NSCharacterSet characterSetWithCharactersInString:@"[]"];
    while (![scanner isAtEnd]) {
        NSString * tempString;
        //get any literal characters
        if ([scanner scanUpToString: @"[" intoString:&tempString]) {
            [outStr appendString:tempString];
        }
        //get keyword and replace with values
        if ([scanner scanString:@"[" intoString:nil]) {
            
            int numBrackets = 1;
            NSMutableString *bracketedString = [NSMutableString string];
            tempString = @"";
            while (numBrackets > 0 && !scanner.atEnd ) {
                [bracketedString appendString:tempString];  //get recursive [ if any
                if ([scanner scanUpToCharactersFromSet:brackets intoString:&tempString]) {
                    [bracketedString appendString:tempString];
                }
                if ([scanner scanString:@"[" intoString:&tempString]) {
                    numBrackets++;
                } else if ([scanner scanString:@"]" intoString:&tempString]) {
                    numBrackets--;
                }
            }
            [outStr appendString: [self replacementForKeyword:bracketedString usingDictionary:keywords]];
            if (numBrackets > 0) {
            	[outStr appendString:@" <<Error: Missing Bracket>>"];
			}
        }
    }
    NSString * finalStr = [outStr stringByReplacingOccurrencesOfString:@"/" withString:@"-"]; //remove accidental directory markers
    finalStr = [finalStr stringByReplacingOccurrencesOfString:@"|||" withString:@"/"];  ///insert intentional ones
    return finalStr;
}
#undef Null

-(NSString *) directoryForShowInDirectory:(NSString*) tryDirectory createIfMissing:(BOOL) create {
    //Check that download directory (including show directory) exists.  If create it.  If unsuccessful return nil
    if (![[NSFileManager defaultManager] fileExistsAtPath: tryDirectory]) {
		if (create) { 		// try to create it
			DDLogDetail(@"Creating folder %@",tryDirectory);
        	if (![[NSFileManager defaultManager] createDirectoryAtPath:tryDirectory withIntermediateDirectories:YES attributes:nil error:nil]) {
            	DDLogReport(@"Couldn't create folder %@",tryDirectory);
            	return nil;
        	}
		} else {
			return nil;
		}
    }
	return tryDirectory;
}

-(NSString *) downloadFileNameWithFormat:(NSString *)formatName andOptions: (NSString *) options createIfNecessary:(BOOL) create {
    NSString *baseTitle  = nil;
    NSString *keyPathPart = nil;

    NSString *filenamePattern = [[NSUserDefaults standardUserDefaults] objectForKey:kMTFileNameFormat];
	if (filenamePattern.length == 0) filenamePattern = kMTcTiVoDefault; //shouldn't happen.
	
	//we should always have a pattern, so generate a name that way
	NSString *keyBaseTitle = [self swapKeywordsInString:filenamePattern withFormat:formatName andOptions:options ];
	DDLogVerbose(@"With file pattern %@ for show %@, got %@", filenamePattern, self, keyBaseTitle);
	NSString * candidateBaseTitle = [keyBaseTitle lastPathComponent];
	if (candidateBaseTitle.length > 0) {
		baseTitle = candidateBaseTitle;
		keyPathPart = [keyBaseTitle stringByDeletingLastPathComponent];
	}

	if (baseTitle.length > 245) baseTitle = [baseTitle substringToIndex:245];
    baseTitle = [self cleanBaseFileName: baseTitle];
    if ([baseTitle compare: self.showTitle ]  != NSOrderedSame) {
        DDLogVerbose(@"changed filename %@ to %@",self.showTitle, baseTitle);
    }
	if (baseTitle.length == 0) {
		DDLogReport(@"No base name; with file pattern %@ for show %@, got %@", filenamePattern, self, keyBaseTitle);
		baseTitle = self.showTitle;
	}

    NSString *ddir = [self directoryForShowInDirectory: [[tiVoManager downloadDirectory] stringByAppendingPathComponent:keyPathPart ] createIfMissing:create];
	if (ddir.length == 0) {
		if (create) {
			DDLogReport(@"No directory for show %@. Invalid filename pattern %@? (=> %@)", self, filenamePattern, keyBaseTitle);
			ddir = tiVoManager.downloadDirectory;
		}
	}
    return [ddir stringByAppendingPathComponent:baseTitle];
}

-(NSString *) downloadDirCreateIfNecessary: (BOOL) create {
    NSString * filename = [self downloadFileNameWithFormat:nil andOptions: nil createIfNecessary:create];
    return [filename stringByDeletingLastPathComponent];
}

#pragma mark - Metadata

-(const MP4Tags * ) metaDataTagsWithImage: (NSImage* ) image andResolution:(HDTypes) hdType {
    //maintain source code parallel with MTiTunes.m>importIntoiTunes
    const MP4Tags *tags = MP4TagsAlloc();
    uint8_t mediaType = 10;  //MP4 can't be audio only?
    if (self.isMovie) {
        mediaType = 9;
        MP4TagsSetMediaType(tags, &mediaType);
        MP4TagsSetName(tags,[self.showTitle cStringUsingEncoding:NSUTF8StringEncoding]) ;
        MP4TagsSetArtist(tags,[self.directors.string cStringUsingEncoding:NSUTF8StringEncoding]);
    } else {
        mediaType = 10;
        MP4TagsSetMediaType(tags, &mediaType);
        if (self.seriesTitle.length>0) {
            MP4TagsSetTVShow(tags,[self.seriesTitle cStringUsingEncoding:NSUTF8StringEncoding]);
            MP4TagsSetArtist(tags,[self.seriesTitle cStringUsingEncoding:NSUTF8StringEncoding]);
            MP4TagsSetAlbumArtist(tags,[self.seriesTitle cStringUsingEncoding:NSUTF8StringEncoding]);
        }
        if (self.season > 0 ) {
            uint32_t showSeason =  self.season;
            MP4TagsSetTVSeason(tags, &showSeason);
            MP4TagsSetAlbum(tags,[[NSString stringWithFormat: @"%@, Season %d",self.seriesTitle, self.season] cStringUsingEncoding:NSUTF8StringEncoding]) ;
        } else {
            MP4TagsSetAlbum(tags,[self.seriesTitle cStringUsingEncoding:NSUTF8StringEncoding]);
        }

        if (self.episodeTitle.length==0) {
            NSString * dateString = self.originalAirDateNoTime;
            if (dateString.length == 0) {
                NSDateFormatter *dateFormat = [[NSDateFormatter alloc] init];
                [dateFormat setDateStyle:NSDateFormatterShortStyle];
                [dateFormat setTimeStyle:NSDateFormatterNoStyle];
                dateString =  [dateFormat stringFromDate: self.showDate ];
            }
            MP4TagsSetName(tags,[[NSString stringWithFormat:@"%@ - %@",self.showTitle, dateString] cStringUsingEncoding:NSUTF8StringEncoding]);
        } else {
            MP4TagsSetName(tags,[self.episodeTitle cStringUsingEncoding:NSUTF8StringEncoding]);
        }
        uint32_t episodeNum = (uint32_t) self.episode;
        if (episodeNum == 0) {
            episodeNum = (uint32_t) [self.episodeNumber integerValue];
        }
        if ( episodeNum> 0) {
            MP4TagsSetTVEpisode(tags, &episodeNum);
            MP4TagTrack track;
            track.index = (uint16)episodeNum;
            track.total = 0;
            MP4TagsSetTrack(tags, &track);
        }
    }
    if (self.episodeID.length >0) {
        MP4TagsSetTVEpisodeID(tags, [self.episodeID cStringUsingEncoding:NSUTF8StringEncoding]);
    }

    if (self.showDescription.length > 0) {
        if (self.showDescription.length < 255) {
            MP4TagsSetDescription(tags,[self.showDescription cStringUsingEncoding:NSUTF8StringEncoding]);
            MP4TagsSetComments(tags,[self.showDescription cStringUsingEncoding:NSUTF8StringEncoding]);
        } else {
            MP4TagsSetDescription(tags,[[self.showDescription  substringToIndex:255] cStringUsingEncoding:NSUTF8StringEncoding]);
            MP4TagsSetLongDescription(tags,[self.showDescription cStringUsingEncoding:NSUTF8StringEncoding]);
            MP4TagsSetComments(tags,[self.showDescription cStringUsingEncoding:NSUTF8StringEncoding]);
        }
    }
    if (self.seriesTitle.length>0) {
        MP4TagsSetTVShow(tags, [self.seriesTitle cStringUsingEncoding:NSUTF8StringEncoding]);
    }
    //no year equivalent?
    NSString * releaseDate = self.isMovie ? self.movieYear : self.originalAirDate;
    if (releaseDate.length == 0) {
        releaseDate = self.isMovie ? self.originalAirDate : self.movieYear ;
    }
    if (releaseDate.length>0) {
        MP4TagsSetReleaseDate(tags,[releaseDate cStringUsingEncoding:NSUTF8StringEncoding]);
    } else {
        DDLogMajor(@"No release date? for %@", self);
    }
    if (self.stationCallsign) {
        MP4TagsSetTVNetwork(tags, [self.stationCallsign cStringUsingEncoding:NSUTF8StringEncoding]);
    }
    if (self.episodeGenre.length>0) {
        MP4TagsSetGenre(tags,[self.episodeGenre cStringUsingEncoding:NSUTF8StringEncoding]);
    }

    if (image) {
        NSData *PNGData  = [NSBitmapImageRep representationOfImageRepsInArray: [image representations]
                                                                    usingType:NSPNGFileType properties:@{NSImageInterlaced: @NO}];
        MP4TagArtwork artwork;

        artwork.data = (void *)[PNGData bytes];
        artwork.size = (uint32_t)[PNGData length];
        artwork.type = MP4_ART_PNG;
        
        MP4TagsAddArtwork(tags, &artwork);
    }
    
    if (hdType != HDTypeNotAvailable ) {
        uint8_t myHDType = (uint8_t) hdType;
        MP4TagsSetHDVideo(tags, &myHDType);
    }
    return tags;
}

-(HDTypes) hdTypeForMP4File:(MP4FileHandle *) fileHandle {
    uint32_t tracksCount = MP4GetNumberOfTracks(fileHandle, 0, 0);

    for (uint16_t i=0; i< tracksCount; i++) {
        MP4TrackId trackId = MP4FindTrackId(fileHandle, i, 0, 0);
        const char* type = MP4GetTrackType(fileHandle, trackId);

        if (MP4_IS_VIDEO_TRACK_TYPE(type)) {
            uint16 height = MP4GetTrackVideoHeight(fileHandle, trackId);
            if (height == 0) {
                return HDTypeNotAvailable;
            } else  if (height <=  480) {
                return HDTypeStandard;
            } else if (height <= 720 ) {
                return HDType720p;
            } else if (height <= 10000) {
                return HDType1080p;
            } else {
                return HDTypeNotAvailable;
            }
        }
    }
    return HDTypeNotAvailable;
}

-(void) writeTextMetaData:(NSString*) value forKey: (NSString *) key toFile: (NSFileHandle *) handle {
    if ( key.length > 0 && value.length > 0) {

        [handle writeData:[[NSString stringWithFormat:@"%@ : %@\n",key, value] dataUsingEncoding:NSUTF8StringEncoding]];
    }
}

-(void) createTestMP4 {
    //test routine to create dummy MP4 with all metadata stored
    //sample call code: add to MainWindowController 
    // and add to right-click menu in mainWindowController
    //    } else if ([menu.title caseInsensitiveCompare:@"Test Metadata"] == NSOrderedSame) {
    //		for (MTTiVoShow * show in [tiVoShowTable.sortedShows objectsAtIndexes:[tiVoShowTable selectedRowIndexes]]) {
    //            [show createTestMP4];
    //        }

    NSFileManager *fm = [NSFileManager defaultManager];
    NSString * baseTitle  = [self.showTitle stringByReplacingOccurrencesOfString:@"/" withString:@"-"];
    if (baseTitle.length > 245) baseTitle = [baseTitle substringToIndex:245];
    baseTitle = [baseTitle stringByReplacingOccurrencesOfString:@":" withString:@"-"];
    NSString * filePath = [NSString stringWithFormat:@"%@/ZTEST%@.mp4", [tiVoManager downloadDirectory], baseTitle];
    NSString * testPath =[NSString stringWithFormat:@"%@/test.mp4", [tiVoManager downloadDirectory]];
    NSString * textMetaPath = [filePath stringByAppendingPathExtension:@"txt"];
    NSString * textFromMP4Path =[[filePath stringByAppendingString:@"2" ] stringByAppendingPathExtension:@"txt"];
    NSString * diffPath =[[filePath stringByAppendingString:@".diff" ] stringByAppendingPathExtension:@"txt"];
    NSError * error = nil;
    if (![fm copyItemAtPath:testPath toPath:filePath error:&error]) {
        DDLogMajor(@"couldn't copy file %@ to %@; Error %@", testPath, filePath, error.localizedDescription);
        return;
    };


    MP4FileHandle *encodedFile = MP4Modify([filePath cStringUsingEncoding:NSUTF8StringEncoding],0);

    [self addExtendedMetaDataToFile:encodedFile withImage:nil];
    MP4Close(encodedFile,MP4_CLOSE_DO_NOT_COMPUTE_BITRATE);

    NSData * xml = [NSData dataWithContentsOfURL:[self detailURL]];
    NSXMLDocument *xmldoc = [[NSXMLDocument alloc] initWithData:xml options:0 error:nil];
    NSString * xltTemplate = [[NSBundle mainBundle] pathForResource:@"pytivo_txt" ofType:@"xslt"];
    NSData * returnxml = [xmldoc objectByApplyingXSLTAtURL:[NSURL fileURLWithPath:xltTemplate] arguments:nil error:nil	];
    NSString *returnString = [[NSString alloc] initWithData:returnxml encoding:NSUTF8StringEncoding];
    if (![returnString writeToFile:textMetaPath atomically:NO encoding:NSUTF8StringEncoding error:nil]) {
        DDLogReport(@"Couldn't write pyTiVo Data to file %@", textMetaPath);
    } else {
        NSFileHandle *textMetaHandle = [NSFileHandle fileHandleForWritingAtPath:textMetaPath];
        [textMetaHandle seekToEndOfFile];
        [self writeTextMetaData:self.seriesId		  forKey:@"seriesId"			toFile:textMetaHandle];
        [self writeTextMetaData:self.channelString   forKey:@"displayMajorNumber"	toFile:textMetaHandle];
        [self writeTextMetaData:self.stationCallsign forKey:@"callsign"		    toFile:textMetaHandle];
        [self writeTextMetaData:self.programId       forKey:@"programId"       toFile:textMetaHandle];
        [textMetaHandle closeFile];
    }

    NSTask * pythonTask = [[NSTask alloc] init];
    [pythonTask setLaunchPath:[@"~/Documents/develop/pytivo/metadata.py" stringByExpandingTildeInPath]];
    [pythonTask setArguments:@[ [filePath stringByExpandingTildeInPath]]];
    [fm createFileAtPath:textFromMP4Path contents:nil attributes:nil];
    NSFileHandle * textHandle = [NSFileHandle fileHandleForWritingAtPath:textFromMP4Path];
    [pythonTask setStandardOutput:textHandle];
    [pythonTask launch];
    [pythonTask  waitUntilExit];
    [textHandle closeFile];

    if ([pythonTask terminationStatus] == 0) {
        NSString * bashCmd = [NSString stringWithFormat:@"diff -u <(sort \"%@\") <(sort \"%@\") >\"%@\"",textMetaPath, textFromMP4Path, diffPath ];
        NSTask * proc = [[NSTask alloc] init];
        [proc setLaunchPath:@"/bin/bash"];
        [proc setArguments:@[ @"-c", bashCmd]];
        [proc launch];
        [proc  waitUntilExit];

        if ([proc terminationStatus] != 0) {
            DDLogMajor(@"Diff metadata failed for %@", self);
        }
    } else {
        DDLogMajor(@"Python metadata failed for %@", self);
    }


}
-(void) addExtendedMetaDataToFile:(MP4FileHandle *)fileHandle withImage:(NSImage *) artwork {

    HDTypes hdType = [self hdTypeForMP4File:fileHandle ];
    const MP4Tags* tags = [self metaDataTagsWithImage: artwork andResolution:hdType];
    MP4TagsStore(tags, fileHandle );
    MP4TagsFree(tags);



    //   for (NSString * key in [@'vActor', 'directors': 'vDirector',  'producers': 'vProducer', 'screenwriters': 'vWriter']);

    NSMutableDictionary * iTunMovi = [NSMutableDictionary dictionary];
    if (self.directors.string.length) {
        [iTunMovi setObject:[self dictArrayFromString:self.directors] forKey:@"directors"];
    }
    if (self.actors.string.length > 0 ||
        self.guestStars.string.length > 0){
        NSArray * castArray = [[self dictArrayFromString: self.actors    ]  arrayByAddingObjectsFromArray:
                               [self dictArrayFromString: self.guestStars]];
        [iTunMovi setObject:castArray forKey:@"cast"];
    }
    if (self.producers.string.length) {
        [iTunMovi setObject:[self dictArrayFromString:self.producers] forKey:@"producers"];
    }
    if (self.writers.string.length) {
        [iTunMovi setObject:[self dictArrayFromString:self.writers] forKey:@"screenwriters"];
    }

    if (iTunMovi.count) {
        NSData *serializedPlist = [NSPropertyListSerialization
                                   dataFromPropertyList:iTunMovi
                                   format:NSPropertyListXMLFormat_v1_0
                                   errorDescription:nil];
        MP4ItmfItem* newItem = MP4ItmfItemAlloc( "----", 1 );
        newItem->mean = strdup( "com.apple.iTunes" );
        newItem->name = strdup( "iTunMOVI" );

        MP4ItmfData* data = &newItem->dataList.elements[0];
        data->typeCode = MP4_ITMF_BT_UTF8;
        data->valueSize = (unsigned int) [serializedPlist length];
        data->value = (uint8_t*)malloc( data->valueSize );
        memcpy( data->value, [serializedPlist bytes], data->valueSize );

        MP4ItmfAddItem(fileHandle, newItem);
        MP4ItmfItemFree(newItem);
    }

    NSMutableDictionary * tiVoInfo = [NSMutableDictionary dictionary];
    if (self.channelString.length >0) {
        [tiVoInfo setObject:self.channelString forKey:@"displayMajorNumber"];
    }
    if (self.showTime.length >0){
        [tiVoInfo setObject:self.showTime forKey:@"time"];
    }
    if (self.colorCode.length >0){
        [tiVoInfo setObject:self.colorCode forKey:@"colorCode"];
    }
    if (self.showingBits.length >0){
        [tiVoInfo setObject:self.showingBits forKey:@"showingBits"];
    }
    if (self.starRating.length >0){
        [tiVoInfo setObject:self.starRating forKey:@"starRating"];
    }
    if (self.startTime.length >0){
        [tiVoInfo setObject:self.startTime forKey:@"startTime"];
    }
    if (self.stopTime.length >0){
        [tiVoInfo setObject:self.stopTime forKey:@"stopTime"];
    }
    if (self.programId.length >0){
        [tiVoInfo setObject:self.programId forKey:@"programId"];
    }
    if (self.seriesId.length >0){
        [tiVoInfo setObject:self.seriesId forKey:@"seriesId"];
    }
    if (tiVoInfo.count) {
        NSData *serializedPlist = [NSPropertyListSerialization
                                   dataFromPropertyList:tiVoInfo
                                   format:NSPropertyListXMLFormat_v1_0
                                   errorDescription:nil];
        MP4ItmfItem* newItem = MP4ItmfItemAlloc( "----", 1 );
        newItem->mean = strdup( "com.pyTivo.pyTivo" );
        newItem->name = strdup( "tiVoINFO" );

        MP4ItmfData* data = &newItem->dataList.elements[0];
        data->typeCode = MP4_ITMF_BT_UTF8;
        data->valueSize = (unsigned int) [serializedPlist length];
        data->value = (uint8_t*)malloc( data->valueSize );
        memcpy( data->value, [serializedPlist bytes], data->valueSize );

        MP4ItmfAddItem(fileHandle, newItem);
        MP4ItmfItemFree(newItem);
    }

    //Now for ratings

    NSString * itunesRating = [self iTunesCode];
    if (itunesRating.length >0) {
        MP4ItmfItem *newItem = MP4ItmfItemAlloc("----", 1);
        newItem->mean = strdup("com.apple.iTunes");
        newItem->name = strdup("iTunEXTC");

        MP4ItmfData *data = &newItem->dataList.elements[0];
        data->typeCode = MP4_ITMF_BT_UTF8;
        data->valueSize = (unsigned int) strlen([itunesRating UTF8String]);
        data->value = (uint8_t*)malloc( data->valueSize );
        memcpy( data->value, [itunesRating UTF8String], data->valueSize );
        
        MP4ItmfAddItem(fileHandle, newItem);
    }
}

-(void) addArtwork:(NSImage *) image toMP4File: (NSString *) fileName {

    MP4FileHandle *fileOnDisk = MP4Modify([fileName cStringUsingEncoding:NSUTF8StringEncoding],0);
    if (fileOnDisk) {
        const MP4Tags *tags = MP4TagsAlloc();
        if (MP4TagsFetch( tags, fileOnDisk )) {

            if (image) {
                NSData *PNGData  = [NSBitmapImageRep representationOfImageRepsInArray: [image representations]
                                                                        usingType:NSPNGFileType properties:@{NSImageInterlaced: @NO}];
                MP4TagArtwork artwork;

                artwork.data = (void *)[PNGData bytes];
                artwork.size = (uint32_t)[PNGData length];
                artwork.type = MP4_ART_PNG;
                if (tags->artworkCount == 0) {
                    MP4TagsAddArtwork(tags, &artwork);
                } else {
                    MP4TagsSetArtwork(tags, 0, &artwork);
                }
           } else {
                MP4TagsRemoveArtwork(tags, 0);
            }
            if (!MP4TagsStore(tags, fileOnDisk )) {
                DDLogReport (@"could not write MP4 tags tp file %@", fileName);
            }
            [[NSWorkspace sharedWorkspace] setIcon:image forFile:fileName options:NSExcludeQuickDrawElementsIconCreationOption];
        } else {
            DDLogReport (@"could not read MP4 tags from file %@", fileName);
        }
        MP4TagsFree(tags);
    } else {
        DDLogReport (@"could not open MP4 file %@", fileName);
    }
    MP4Close(fileOnDisk,MP4_CLOSE_DO_NOT_COMPUTE_BITRATE);
}

#pragma mark - Artwork
-(void) resetSourceInfo:(BOOL) all {
    //all means go all the way back to source
    //not all means just reload images, maybe based on new prefernces
    if (all) {
        NSURL * localURL = [self localURLForSource: self.lastImageSource thumbVersion:YES];
        NSURL * artURL = [self localURLForSource: self.lastImageSource thumbVersion:NO];
        if (localURL) [[NSFileManager defaultManager] removeItemAtURL: localURL error:nil];
        if (artURL) [[NSFileManager defaultManager] removeItemAtURL: artURL error:nil];
    }
    _userSpecifiedArtworkFile = nil;
    _artworkFile = nil;
    _thumbnailFile = nil;
    _thumbnailImage = nil;
    _tvdbData = nil;
    _rpcData = nil;
	_imageInProgress = NO;
	_tvdbInProgress = NO;
    _lastImageSource = MTSearchingSource;
	_clipMetaDataId = nil;
	_edlList = nil;
	
    if (all) {
        [self.tiVo reloadShowInfoForShows:@[self]];
        [tiVoManager.tvdb resetTVDBInfo:self];
    }
    if (self.isMovie) {
        [tiVoManager.tvdb getTheMovieDBDetails:self ];
    } else {
        [tiVoManager.tvdb getTheTVDBDetails:self ];
    }
    self.rpcData = [self.tiVo registerRPCforShow:self];
}

- (NSString *) artworkFileWithPrefix: (NSString *) prefix andSuffix: (NSString *) suffix InPath: (NSString *) directory {
    prefix = [prefix lowercaseString];
    suffix = [suffix lowercaseString];
    if (directory.length == 0) return nil;
    NSString * realDirectory = [directory stringByStandardizingPath];
    DDLogVerbose(@"Checking for %@_%@ artwork in %@", prefix, suffix ?:@"", realDirectory);
    NSArray *dirContents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:realDirectory error:nil];
    for (NSString *filename in dirContents) {
        NSString *lowerCaseFilename = [filename lowercaseString];
        if (!prefix || [lowerCaseFilename hasPrefix:prefix]) {
            NSString * extension = [lowerCaseFilename pathExtension];
            if ([[NSImage imageFileTypes] indexOfObject:extension] != NSNotFound) {
                NSString * base = [lowerCaseFilename stringByDeletingPathExtension];
                if (!suffix || [base hasSuffix:suffix]){
                    if (!suffix) {
                        //if no suffix, then need to validate it does NOT have season/episode info.
                        static NSRegularExpression * seasonRegex, *episodeRegex;
                        if (!seasonRegex) {
                            seasonRegex = [NSRegularExpression regularExpressionWithPattern:@"S[0-9]+$" options:NSRegularExpressionCaseInsensitive error:nil];
                            episodeRegex = [NSRegularExpression regularExpressionWithPattern:@"S[0-9]+\\s*E([0-9]+)$" options:NSRegularExpressionCaseInsensitive error:nil];
                        }
                        if ([episodeRegex firstMatchInString:base options:NSMatchingWithoutAnchoringBounds range:NSMakeRange(0, base.length)] ||
                             [seasonRegex firstMatchInString:base options:NSMatchingWithoutAnchoringBounds range:NSMakeRange(0, base.length)]) {
                            continue;
                        }
                    }
                    NSString * path = [realDirectory stringByAppendingPathComponent: filename];
                    DDLogDetail(@"found artwork for %@ in %@",prefix, path);
                    return path;
                }
            }
        }
    }
    return nil;
}

-(NSURL *) filenameForUserArtwork {
    //keep parallel with UserSpecificArtworkFile

    NSString * directory = nil;
    NSString * legalSeriesName = [self cleanBaseFileName: self.seriesTitle];

    NSString *currentDir   = [[self downloadFileNameWithFormat:nil andOptions: nil createIfNecessary:YES] stringByDeletingLastPathComponent];
    currentDir = [currentDir pathForParentDirectoryWithName:legalSeriesName];
    directory = [currentDir stringByAppendingPathComponent:@"thumbnails"];

    NSError * error = nil;
    [[NSFileManager defaultManager] createDirectoryAtPath:directory
                              withIntermediateDirectories:YES
                                               attributes:NULL
                                                    error: &error];
    NSString * fileName = [[directory stringByAppendingPathComponent: self.seasonEpisode.length > 0 ? [NSString stringWithFormat: @"%@ %@", legalSeriesName, self.seasonEpisode ] : legalSeriesName ]
                                     stringByAppendingPathExtension:@"jpg"];
    return [NSURL fileURLWithPath:fileName isDirectory:NO];
}

-(void) dropComplete:(NSImage *)artwork {

    self.thumbnailImage = nil;
    self.artWorkImage = nil;
    if (!artwork) {
        if (self.thumbnailFile) {
            [self invalidateCurrentThumbnail:nil];
        }
        if (self.artworkFile) {
            NSError * error = nil;
            if (![[NSFileManager defaultManager] trashItemAtURL:self.artworkFile resultingItemURL:nil error: &error]) {
                DDLogReport(@"Could not delete artwork file %@. Error: %@", self.artworkFile, error.localizedDescription);
            }
            self.artworkFile = nil;
        }
        artwork = self.artWorkImage;
    } else {
       if (![artwork isKindOfClass:[NSImage class]]) {
            DDLogReport(@"Invalid image format %@?", artwork);
            return;
        }
        NSBitmapImageRep *imageRep = [NSBitmapImageRep imageRepWithData: [artwork TIFFRepresentation]];
        NSData * imageData = [imageRep representationUsingType:NSJPEGFileType properties:@{NSImageCompressionFactor: @(1.0)}];

        NSURL * fileName = [self filenameForUserArtwork];
        if ([imageData writeToURL:fileName atomically:YES]) {
            self.thumbnailFile = fileName;
            self.artworkFile = fileName;
       } else {
            DDLogReport(@"could not write image file to %@. ", fileName);
       }
    }
    for (NSString * fileOnDisk in self.copiesOnDisk) {
        [self addArtwork:self.artWorkImage toMP4File:fileOnDisk];
    }

    [NSNotificationCenter postNotificationNameOnMainThread: kMTNotificationPictureLoaded object:self ];
    //now update other shows in same series (only if nonEpisodic OR deleting artwork from episodes, which could be series-wide)
    if (!self.isMovie  && (!artwork || !self.isEpisodicShow)) {
        for (MTTiVoShow * show in [tiVoManager tiVoShows ]) {
            if ([show.seriesTitle isEqualToString:self.seriesTitle]) {
                if (show != self) {
                    show.artWorkImage = nil;
                    show.thumbnailImage = nil;
                    show.thumbnailFile = nil;
                    show.artworkFile = nil;
                    show.userSpecifiedArtworkFile = nil;
                    [NSNotificationCenter postNotificationNameOnMainThread:kMTNotificationDetailsLoaded object:show ];
                }
            }
        }
    }
}

-(NSString *) cleanBaseFileName: (NSString *) base {
    NSString * newBase = [base stringByReplacingOccurrencesOfString:@"/" withString:@"-"];
    newBase = [newBase stringByReplacingOccurrencesOfString:@": " withString:@"-"] ;
    newBase = [newBase stringByReplacingOccurrencesOfString:@":" withString:@"-"] ;
    newBase = [newBase stringByReplacingOccurrencesOfString:@":" withString:@"-"] ;
    return newBase;
}

-(NSString *) userSpecifiedArtworkFile {
    if (!_userSpecifiedArtworkFile) {
        NSString * legalSeriesName =  [self cleanBaseFileName:self.seriesTitle];

        NSMutableArray * directories = [NSMutableArray array];
        NSString * topDirectory = [[tiVoManager downloadDirectory] stringByAppendingPathComponent:@"thumbnails"];
        NSString *currentDir   = [self downloadDirCreateIfNecessary:NO];
        NSString *parentDir = [currentDir stringByDeletingLastPathComponent];
        parentDir = [parentDir pathForParentDirectoryWithName:legalSeriesName];

        NSString * userThumbnailDir = [[NSUserDefaults standardUserDefaults] stringForKey:kMTThumbnailsDirectory];
       if (userThumbnailDir) {
            [directories addObject:userThumbnailDir];
        } else if (currentDir) {
            [directories addObject: currentDir];
            [directories addObject: [currentDir stringByAppendingPathComponent:@"thumbnails"]];
            [directories addObject: parentDir];
            [directories addObject:  [parentDir stringByAppendingPathComponent:@"thumbnails"]];
        }
        if (topDirectory) [directories addObject: topDirectory]; //should always be!

        if (self.isMovie) {
            for (NSString * dir in directories) {
                _userSpecifiedArtworkFile = [self artworkFileWithPrefix:legalSeriesName andSuffix:self.movieYear  InPath:dir ];
                if ( _userSpecifiedArtworkFile ) break;
            }
            if ( !_userSpecifiedArtworkFile) for (NSString * dir in directories) {
                _userSpecifiedArtworkFile = [self artworkFileWithPrefix:legalSeriesName andSuffix:nil InPath:dir ];
                if ( _userSpecifiedArtworkFile ) break;
            }

        } else {
            if (self.episode > 0) {
                //first check for user-specified, episode-specific art
                if (self.seasonEpisode.length > 0) {
                    for (NSString * dir in directories) {
                        _userSpecifiedArtworkFile = [self artworkFileWithPrefix:legalSeriesName andSuffix:self.seasonEpisode  InPath:dir ];
                        if ( _userSpecifiedArtworkFile ) break;
                    }
                }
            }
            //then for season-specific art
            NSString * season = [NSString stringWithFormat:@"S%0.2d",self.season];
            if ( !_userSpecifiedArtworkFile ) for (NSString * dir in directories) {
                _userSpecifiedArtworkFile = [self artworkFileWithPrefix:legalSeriesName andSuffix:season InPath:dir ];
                if ( _userSpecifiedArtworkFile ) break;
            }
        }
        //finally for series-level art
        if ( !_userSpecifiedArtworkFile  ) {
            for (NSString * dir in directories) {
                _userSpecifiedArtworkFile = [self artworkFileWithPrefix:legalSeriesName andSuffix:nil InPath:dir ];
                if ( _userSpecifiedArtworkFile ) break;
            }
        }
        if (!_userSpecifiedArtworkFile) {
            _userSpecifiedArtworkFile = @""; //mark that we've looked but not available; could add filesystem observer to downloadDir to discover user adding photos
        }
    }
    return _userSpecifiedArtworkFile.length > 0 ? _userSpecifiedArtworkFile : nil;
}

- (void) failureHandlerForSource: (MTImageSource) source thumbnail: (BOOL) thumbnail {
    self.thumbnailFile = nil;
   if (source == MTTiVoSource) {
        self.artworkFile = nil;
        self.rpcData.imageURL = @"";
       [[ NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationPictureLoaded object:self];
   } else  {
        NSString * tvdbkey = [self mapTVDBKeyFromSource:source];
        if (tvdbkey) {
            self.tvdbData = [tiVoManager.tvdb cacheArtWork:@"" forKey:tvdbkey forShow:self];
        }
    }
}
-(NSURL *) localURLForSource: (MTImageSource) source thumbVersion: (BOOL) thumbnail {
    if (source == MTNoSource) return nil;
    NSString * baseName = [self cleanBaseFileName: self.seriesTitle];
    NSURL * directory =  (source == MTTiVoSource) ? [tiVoManager tivoTempDirectory] : [tiVoManager tvdbTempDirectory];
    if (self.isMovie) {
        baseName = [NSString stringWithFormat:@"%@_%@", baseName, self.movieYear];
    } else if (self.isEpisodicShow && (source == MTTVDBEpisode  || source == MTTVDBSeason)) {
        NSString * seasonEp = self.seasonEpisode;
        int season = self.season;
        if (![[NSUserDefaults standardUserDefaults] boolForKey:kMTTrustTVDBEpisodes]) {
            //then we need to use tvdb episodes anyways for filenames
            NSNumber * tvdbEpsNum = self.tvdbData[kTVDBEpisodeKey];
            NSNumber * tvdbSeaNum = self.tvdbData[kTVDBSeasonKey];
            if (tvdbEpsNum && tvdbSeaNum) {
                season =      tvdbSeaNum.intValue;
                int episode = tvdbEpsNum.intValue;
                seasonEp = [NSString stringWithFormat:@"S%0.2dE%0.2d",season, episode ];
            }
        }
        if (source == MTTVDBEpisode) {
            baseName = [NSString stringWithFormat:@"%@_%@", baseName, seasonEp];
        } else { //MTTVDBSeason
            baseName = [NSString stringWithFormat:@"%@_S%0.2d", baseName, season];
        }
    }
    if (!thumbnail && source != MTTiVoSource) {
        baseName = [baseName stringByAppendingString:@"_Large"];
    }
    baseName = [baseName stringByAppendingPathExtension:@"jpg"];
    if (@available (macOS 10.11, *)) {
        return [NSURL fileURLWithPath:baseName isDirectory:NO relativeToURL:directory];
    } else {
        return [directory URLByAppendingPathComponent:baseName];
    }

}
-(void) getArtworkFromSource: (MTImageSource) source thumbVersion: (BOOL) thumbnail {
    if (source == MTNoSource) return;
	if (self.imageInProgress) {
		DDLogMajor(@"ImageInProgress bounce: %@", self);
		return;
	}
    self.imageInProgress = YES;

    NSURL * filename = [self localURLForSource:source thumbVersion:thumbnail];
    //download only if we don't have it already
    if ([filename fileExists]) {
        DDLogDetail (@"Cached artwork found for %@ at %@", self, filename);
        if (source == MTTiVoSource) {
            self.thumbnailFile = filename;
            self.artworkFile = filename;
        } else {
            if (thumbnail) {
                self.thumbnailFile = filename;
            } else {
                self.artworkFile = filename;
            }
        }
        self.imageInProgress = NO;
        return;
    }
    NSString *urlString = nil;
    if (source == MTTiVoSource) {
        if (!self.rpcData.imageURL.length) {
            DDLogReport(@"Warning: TiVo imageURL not available");
			self.imageInProgress = NO;
            return;
        }
        urlString = self.rpcData.imageURL;
    } else {
        NSString *baseUrlString;
        if (self.isMovie) {
            if (thumbnail) {
                baseUrlString = @"http://image.tmdb.org/t/p/w92%@";
            } else {
                baseUrlString = @"http://image.tmdb.org/t/p/w780%@";
            }
        } else {
//            if (thumbnail) {
//                baseUrlString = @"http://thetvdb.com/banners/_cache/%@";
//            } else {
                baseUrlString = @"http://thetvdb.com/banners/%@";
//            }
        }
        NSString * tvdbKey = [self mapTVDBKeyFromSource:source];
        if (!tvdbKey) {
            DDLogReport(@"Warning: Tvdb Key not available");
			self.imageInProgress = NO;
            return;
        }
        urlString = [NSString stringWithFormat: baseUrlString, self.tvdbData[tvdbKey]];
    }
    DDLogDetail(@"downloading artwork at %@ to %@",urlString, filename);
    NSURLRequest *req = [NSURLRequest requestWithURL:[NSURL URLWithString:urlString]];
    [NSURLConnection sendAsynchronousRequest:req
                queue:[NSOperationQueue mainQueue]
        completionHandler:^(NSURLResponse *response, NSData *data, NSError *error) {
        DDLogDetail(@"Got the image URL %@",self);
        dispatch_async(dispatch_get_main_queue(), ^(void){
        	DDLogDetail(@"Image URL Main thread. %@",self);
            self.imageInProgress = NO;
            if (!data || error ) {
                DDLogReport(@"Couldn't get artwork for %@ from %@ , Error: %@", self.seriesTitle, urlString, error.localizedDescription);
                [self failureHandlerForSource:source thumbnail:thumbnail ];
            } else {
                NSInteger statusCode = ((NSHTTPURLResponse *) response).statusCode;
                if ( statusCode == 404 || statusCode == 500 || statusCode == 503 ||data.length < 500) {
                    DDLogMajor(@"Artwork unavailable for %@ from %@ , Error: %@", self.seriesTitle, urlString, @(statusCode));
                    [self failureHandlerForSource:source thumbnail:thumbnail];
                } else {
                    [[NSFileManager defaultManager] createDirectoryAtPath:[filename directory] withIntermediateDirectories:YES attributes:nil error:nil];
                    if ([data writeToURL:filename atomically:YES]) {
                        DDLogDetail(@"Saved %d artwork file for %@ at %@", (int)source, self.showTitle, filename);
                        if (thumbnail) {
                            self.thumbnailFile = filename;
                            if (source == MTTiVoSource) {
                                self.artworkFile = filename;
                            }
                        } else {
                            self.artworkFile = filename;
                        }
                        [[ NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationPictureLoaded object:self];
                    } else {
                        DDLogReport(@"Couldn't write to artwork file %@!", filename);
                        [self failureHandlerForSource:source thumbnail:thumbnail ];
                    }
                }
            }
        });
    }];
}

-(NSString *) mapTVDBKeyFromSource:(MTImageSource) source {
    switch (source) {
        case MTTVDBSeries:
            return kTVDBSeriesArtworkKey;
            break;
        case MTTVDBSeason:
            return kTVDBSeasonArtworkKey;
            break;
        case MTTVDBEpisode:
            return kTVDBEpisodeArtworkKey;
            break;
        default:
            return nil;
            break;
    }
}

-(MTImageSource) nextSourceTo:(MTImageSource) oldSource {
    //given that oldSource has failed, mark as such, and return next source, if any
    //this is a state machine that implements the "business" rule of what order to check for images.
    if (oldSource == MTNoSource) return MTNoSource;
    MTImageSource nextSource = MTSearchingSource;
    MTImageSource prefSource = [[NSUserDefaults standardUserDefaults] integerForKey:KMTPreferredImageSource];
    if (prefSource == MTTiVoSource && !self.tiVo.rpcActive) prefSource = MTTVDBSeries;
    if (oldSource == MTSearchingSource) {
        nextSource = prefSource;
        if (!self.isEpisodicShow && (oldSource == MTTVDBEpisode || oldSource == MTTVDBSeason)) {
            nextSource = MTTVDBSeries;
        } 
    } else {
        switch (prefSource) {
            case MTTiVoSource:
                if (oldSource == MTTiVoSource) {
                    nextSource = MTTVDBSeries;
                } else {
                    nextSource = MTNoSource;
                }
                break;
            case MTTVDBSeries:
                if (oldSource == MTTVDBSeries && self.tiVo.rpcActive) {
                    nextSource = MTTiVoSource;
                } else {
                    nextSource = MTNoSource;
                }
                break;
            case MTTVDBSeason:
            case MTTVDBEpisode:
                if (self.isEpisodicShow) {
                    if (oldSource == prefSource  && self.tiVo.rpcActive) {
                        nextSource = MTTiVoSource;
                    } else if (oldSource == MTTiVoSource) {
                        nextSource = MTTVDBSeries;
                    } else {
                        nextSource = MTNoSource;
                    }
                } else {
                    if (oldSource == prefSource) {
                        nextSource = MTTVDBSeries;
                    } else if (oldSource == MTTVDBSeries && self.tiVo.rpcActive) {
                        nextSource = MTTiVoSource;
                    } else {
                        nextSource = MTNoSource;
                    }
                }
                break;
            case MTNoSource:
            default:
                nextSource = MTNoSource;
                break;
        }
    }
    //check if we have the data yet.
    if (nextSource == MTTiVoSource) {
        if (!self.rpcData.imageURL && self.tiVo.supportsRPC) {
            nextSource = MTSearchingSource; // haven't gotten data yet
        }
    } else if (nextSource == MTTVDBEpisode ||
               nextSource == MTTVDBSeries ||
               nextSource == MTTVDBSeason ) {
        if (!self.tvdbData) {
            nextSource = MTSearchingSource;
        }
    }
    return nextSource;
}

-(NSString *) sourceURL: (MTImageSource) source {
    switch (source) {
        case MTTiVoSource:
            return self.rpcData.imageURL;
            break;
        case MTTVDBSeries:
            return self.tvdbData [kTVDBSeriesArtworkKey];
            break;
        case MTTVDBSeason:
            return self.tvdbData [kTVDBSeasonArtworkKey];
            break;
        case MTTVDBEpisode:
            return self.tvdbData [kTVDBEpisodeArtworkKey];
            break;
        case MTNoSource:
        case MTSearchingSource:
        default:
            return nil;
            break;
    }

}

-(BOOL) sourceUnavailable: (MTImageSource) source {
    if (source == MTSearchingSource || source == MTNoSource) return YES;
    if (!self.isEpisodicShow && (source == MTTVDBSeason || source == MTTVDBEpisode)) {
        return YES; //can't get s/e info
    }
    if (source == MTTiVoSource && ![self.tiVo rpcActive]) return YES;
    NSString * sourceURL = [self sourceURL:source];
    if (!sourceURL) return NO;  //don't know if possible yet
    return ([sourceURL isEqualToString:@""]); //we've tried and failed
}

-(void) getInfoFromSource: (MTImageSource) source {
    if (source == MTTVDBSeason) {
		if (self.tvdbInProgress) {
			return;
		}
        self.tvdbInProgress = YES;
        [tiVoManager.tvdb addSeasonArtwork:self];
    } else if (source == MTTVDBSeries) {
		if (self.tvdbInProgress) {
			return;
		}
        self.tvdbInProgress = YES;
        [tiVoManager.tvdb addSeriesArtwork:self];
    }
}

-(BOOL) noImageAvailable {
    return self.lastImageSource == MTNoSource;
}

-(void) getOnlineArtwork:(BOOL) thumbnail {
    //based on current state, advances progress towards getting image
    MTImageSource source = self.lastImageSource;
    while (source != MTNoSource && [self sourceUnavailable:source]){
            source = [self nextSourceTo:source];
        if (source == MTSearchingSource) return; //source not available yet..., but is expected to be.
    }
    self.lastImageSource = source;
    if (source == MTNoSource) return;

    if ([self sourceURL:source]) {
        [self getArtworkFromSource:source thumbVersion:thumbnail];
    } else {
        [self getInfoFromSource:source];
    }
}

-(void) invalidateCurrentThumbnail:(NSURL *) fileName {
    if (!fileName) {
        fileName = self.thumbnailFile;
    }
    if (!fileName) return;
    if ([[tiVoManager tvdbTempDirectory] directoryContainsURL:fileName]) {
        //tvdb cache file, so remember the deletion
        DDLogDetail(@"Removing TVDB image %@", fileName);
        NSString * tvdbKey = [self mapTVDBKeyFromSource: self.lastImageSource];
        if (tvdbKey) self.tvdbData = [tiVoManager.tvdb cacheArtWork:@"" forKey:tvdbKey forShow:self];
    } else if ([[tiVoManager tivoTempDirectory] directoryContainsURL:fileName]) {
        //tivo cache file, so remember the deletion
        DDLogDetail(@"Removing TiVo image %@", fileName);
        self.rpcData.imageURL = @"";
    } else if (self.lastImageSource != MTNoSource) {
        //user specified file, so allow TVDB to update
        DDLogDetail(@"Removing user specified file %@", fileName);
        self.userSpecifiedArtworkFile = nil;
    }
    if ([fileName isEqual: self.thumbnailFile]) {
        self.thumbnailFile = nil;
    }
    DDLogDetail(@"Deleting image for show %@ at %@", self, fileName);
    NSError * error = nil;
    if (![[NSFileManager defaultManager] trashItemAtURL:fileName resultingItemURL:nil error:&error]) {
        DDLogDetail(@"Could not delete image file %@. Error: %@", fileName, error.localizedDescription);
    }
}

-(NSImage *) thumbnailImage {
    //we automatically ask for artworkLocation from services, and when that arrives, there will be a notification to update the show in the window, which wil call us again.
    //Then we request image, and get the same notification when that arrives
    if (!_thumbnailImage){
        if (self.thumbnailFile) {
          _thumbnailImage = [[NSImage alloc] initWithContentsOfURL:self.thumbnailFile];
            if (!_thumbnailImage) {
                [self invalidateCurrentThumbnail:nil];
            }
        }
        if (!_thumbnailImage) {
            if (self.userSpecifiedArtworkFile.length > 0) {
                _thumbnailImage = [[NSImage alloc] initWithContentsOfFile:self.userSpecifiedArtworkFile];
                if (_thumbnailImage) {
                    self.thumbnailFile = [NSURL fileURLWithPath:self.userSpecifiedArtworkFile isDirectory:NO];
                } else {
                    [self invalidateCurrentThumbnail:[NSURL fileURLWithPath:self.userSpecifiedArtworkFile]];
                    self.userSpecifiedArtworkFile = nil;
                }
            }
        }
        if (!_thumbnailImage) {
            [self getOnlineArtwork:YES];
            if (self.thumbnailFile ) {
                _thumbnailImage = [[NSImage alloc] initWithContentsOfURL:self.thumbnailFile];
                if (!_thumbnailImage) {
                    [self invalidateCurrentThumbnail:nil];
                }
            }
        }
    }
    return _thumbnailImage;
}

-(NSImage *) artWorkImage {
    if (!_artWorkImage) {
        if (self.artworkFile) {
            _artWorkImage = [[NSImage alloc] initWithContentsOfURL:self.artworkFile];
            if (!_artWorkImage) self.artworkFile = nil;
        };
        if (!_artWorkImage) {
            if (self.userSpecifiedArtworkFile.length > 0) {
                _artWorkImage = [[NSImage alloc] initWithContentsOfFile:self.userSpecifiedArtworkFile];
                if (_artWorkImage) {
                    self.artworkFile = [NSURL fileURLWithPath:self.userSpecifiedArtworkFile isDirectory:NO];
               } else {
                    self.userSpecifiedArtworkFile = @"";//mark as bad
                }
            }
        }
        if (!_artWorkImage) {
            [self getOnlineArtwork:NO];
             if (_artworkFile ) {
                 _artWorkImage = [[NSImage alloc] initWithContentsOfURL:self.artworkFile];
                 if (!_artWorkImage) self.artworkFile = nil;
             }
        }
    }
    return _artWorkImage;
}


#pragma mark - Memory Management

-(void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self removeObserver:self forKeyPath:@"showTime"];
    [self removeObserver:self forKeyPath:@"episodeNumber"];
    [self removeObserver:self forKeyPath:@"movieYear"];
    [self removeObserver:self forKeyPath:@"originalAirDate"];
    self.showTitle = nil;
    self.showDescription = nil;
    self.tiVo = nil;
	if (elementString) {
        elementString = nil;
	}
	if (elementArray) {
        elementArray = nil;
	}
}

-(NSString *)description
{
    return [NSString stringWithFormat:@"%@ (%@)%@ %p",_showTitle,self.tiVoName,[_protectedShow boolValue]?@"-Protected":@"", self];
}


@end

