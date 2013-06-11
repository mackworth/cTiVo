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
#import "MTiTunes.h"
#import "MTTiVoManager.h"
#import "NSString+RFC3339Date.h"
#import "mp4v2.h"
#import "NSString+Helpers.h"

@interface MTTiVoShow () {
	
	NSXMLParser *parser;
	NSMutableString *elementString;
	NSMutableArray *elementArray;
	NSArray *arrayHolder;
	NSDictionary *parseTermMapping;

}
@property (nonatomic, strong) NSArray *vActor,
										*vExecProducer,
										*vProgramGenre,
										*vSeriesGenre,
										*vGuestStar,
										*vDirector;


@end

@implementation MTTiVoShow

@synthesize seriesTitle		 = _seriesTitle,
			episodeTitle	 = _episodeTitle,
			episodeID    	 = _episodeID,
			imageString		 = _imageString,
			tempTiVoName     = _tempTiVoName;

__DDLOGHERE__

-(id)init
{
    self = [super init];
    if (self) {
        _showID = 0;
		_gotDetails = NO;
		_gotTVDBDetails = NO;
		elementString = nil;
		_vActor = nil;
		_vExecProducer = nil;
        _vDirector = nil;
        _vGuestStar = nil;
		self.inProgress = @(NO); //This is the default
		_season = 0;
		_episode = 0;
		_episodeNumber = @"";
        _isQueued = NO;
		_episodeTitle = @"";
		_seriesTitle = @"";
//		_originalAirDate = @"";
		_episodeYear = 0;
        _tvdbArtworkLocation = nil;
		
		self.protectedShow = @(NO); //This is the default
		parseTermMapping = @{
					   @"description" : @"",  //mark to not load these values
					   @"time": @"showTime",  //maybe this one also
					   @"seriesTitle" : @"",
					   @"episodeTitle" : @""
		};

    }
    return self;
}

#pragma mark - GetDetails from Tivo and parse
-(NSArray *)parseNames:(NSArray *)nameSet
{
	if (!nameSet || ![nameSet respondsToSelector:@selector(count)] || nameSet.count == 0 ) { //|| [nameSet[0] isKindOfClass:[NSString class]]) {
		return nameSet;
	}
	NSRegularExpression *nameParse = [NSRegularExpression regularExpressionWithPattern:@"([^|]*)\\|([^|]*)" options:NSRegularExpressionCaseInsensitive error:nil];
	NSMutableArray *newNames = [NSMutableArray array];
	for (NSString *name in nameSet) {
		NSTextCheckingResult *match = [nameParse firstMatchInString:name options:NSMatchingWithoutAnchoringBounds range:NSMakeRange(0, name.length)];
		NSString *lastName = [name substringWithRange:[match rangeAtIndex:1]];
		NSString *firstName = [name substringWithRange:[match rangeAtIndex:2]];
		[newNames addObject:@{kMTLastName : lastName, kMTFirstName : firstName}];
	}
	return [NSArray arrayWithArray:newNames];
}

-(NSString *)nameString:(NSDictionary *)nameDictionary
{
    return [NSString stringWithFormat:@"%@ %@",nameDictionary[kMTFirstName] ? nameDictionary[kMTFirstName] : @"" ,nameDictionary[kMTLastName] ? nameDictionary[kMTLastName] : @"" ];
}

-(void)setShowLengthString:(NSString *)showLengthString
{
	if (showLengthString != _showLengthString) {
		_showLengthString = showLengthString;
		_showLength = [_showLengthString longLongValue]/1000;
	}
}


-(void)getShowDetail
{
	if (_gotDetails) {
		if (!_gotTVDBDetails) {
			[self getTheTVDBDetails];
		}
		return;
	}
	DDLogDetail(@"getting Detail for %@ at %@",self, _detailURL);
	_gotDetails = YES;
	@autoreleasepool {
//	NSString *detailURLString = [NSString stringWithFormat:@"https://%@/TiVoVideoDetails?id=%d",_tiVo.tiVo.hostName,_showID];
//	NSLog(@"Show Detail URL %@",detailURLString);
        NSString *detailFilePath = [NSString stringWithFormat:@"%@/%@_%d_Details.xml",kMTTmpDetailsDir,_tiVo.tiVo.name,_showID];
        NSData *xml = nil;
        if ([[NSFileManager defaultManager] fileExistsAtPath:detailFilePath]) {
			DDLogDetail(@"downloading details from file %@", detailFilePath);
            xml = [NSData dataWithContentsOfFile:detailFilePath];
            NSMutableDictionary *attr = [NSMutableDictionary dictionaryWithDictionary:[[NSFileManager defaultManager] attributesOfItemAtPath:detailFilePath error:nil]];
            [attr setObject:[NSDate date] forKey:NSFileModificationDate];
            [[NSFileManager defaultManager] setAttributes:attr ofItemAtPath:detailFilePath error:nil];
        } else {
            NSURLResponse *detailResponse = nil;
            NSURLRequest *detailRequest = [NSURLRequest requestWithURL:_detailURL];;
            xml = [NSURLConnection sendSynchronousRequest:detailRequest returningResponse:&detailResponse error:nil];
			if (![_inProgress boolValue]) {
				[xml writeToFile:detailFilePath atomically:YES];
			}
        }
		DDLogVerbose(@"Got Details for %@: %@", self, [[NSString alloc] initWithData:xml encoding:NSUTF8StringEncoding	]);

		parser = [[NSXMLParser alloc] initWithData:xml];
		parser.delegate = self;
		[parser parse];
		if (!_gotDetails) {
			DDLogMajor(@"GetDetails Fail for %@",_showTitle);
			DDLogMajor(@"Returned XML is %@",	[[NSString alloc] initWithData:xml encoding:NSUTF8StringEncoding	]);
		} else {
			DDLogDetail(@"GetDetails parsing Finished");
		}
		[self getTheTVDBDetails];

		NSNotification *notification = [NSNotification notificationWithName:kMTNotificationDetailsLoaded object:self];
    [[NSNotificationCenter defaultCenter] performSelectorOnMainThread:@selector(postNotification:) withObject:notification waitUntilDone:NO];
	}
}
//These will be printed out in alpha order...
#define kMTVDBNoEpisode @"Episode Not Found"
#define kMTVDBEpisode @"Episode Found"
#define kMTVDBCached @"Episode Found in Cache"
#define kMTVDBNewInfo @"Season/Episode Info Added"
#define kMTVDBWrongInfo @"Season/Episode Info Mismatch"
#define kMTVDBRightInfo @"Season/Episode Info Match"
#define KMTVDBSeriesFoundWithEP @"Series Found EP"
#define KMTVDBSeriesFoundWithSH @"Series Found SH"
#define KMTVDBSeriesFoundWithShort @"Series Found SHShort"
#define KMTVDBSeriesFoundName @"Series Found by Name"
#define kMTVDBNoSeries @"Series Not Found"

-(NSString *) retrieveTVDBIdFromZap2itId: (NSString *) zapItID ofType:(NSString *) type {
	//type is just for debugging
	if (zapItID == nil) return nil;
	DDLogVerbose(@"Trying TVDB: %@==>%@",self.seriesId, zapItID);
	NSString *urlString = [[NSString stringWithFormat:@"http://thetvdb.com/api/GetSeriesByRemoteID.php?zap2it=%@",zapItID] stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
	NSURL *url = [NSURL URLWithString:urlString];
	DDLogVerbose(@"Getting %@ details for %@ using %@",type, self, urlString);
	NSString *TVDBText = [NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:nil];
	NSString*seriesIDTVDB = [self getStringForPattern:@"<seriesid>(\\d*)" fromString:TVDBText];
	if (seriesIDTVDB) {
		[tiVoManager.tvdbSeriesIdMapping setObject:seriesIDTVDB forKey:_seriesTitle];
		DDLogVerbose(@"Got series by %@ for %@ using %@", type, self, zapItID);
		tiVoManager.theTVDBStatistics[type] = @([tiVoManager.theTVDBStatistics[type] intValue] + 1);  //note that nonexisting ==> 0
		return seriesIDTVDB;
	} else {
		return nil;
	}
}

-(NSString *) episodeIDForReporting {
	NSString *epID = nil;
	if (self.seriesId.length > 1) {
		epID = [self.seriesId  substringFromIndex:2];
		if (epID.length < 8) {
			epID = [NSString stringWithFormat:@"EP00%@",epID];
		} else {
			epID = [NSString stringWithFormat:@"EP%@",epID];
		}
	}
	return epID;
}

-(NSString *) urlForReporting:(NSString *) tvdbID {
	NSString * showURL = [NSString stringWithFormat:@"http://thetvdb.com/?tab=series&id=%@",tvdbID];
	return showURL;
}

-(NSString *) retrieveTVDBIdFromSeriesName  {
	NSString * urlString = [[NSString stringWithFormat:@"http://thetvdb.com/api/GetSeries.php?seriesname=%@",_seriesTitle] stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
	NSURL *url = [NSURL URLWithString:urlString];
	DDLogDetail(@"Getting details for %@ using %@",self,urlString);
	NSString *seriesID = [NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:nil];
	//This can result in multiple series return only 1 of which is correct.  First break up into Series
	NSArray *serieses = [seriesID componentsSeparatedByString:@"<Series>"];
	for (NSString *series in serieses) {
		NSString *seriesName = [[self getStringForPattern:@"<SeriesName>(.*)<\\/SeriesName>" fromString:series] stringByConvertingHTMLToPlainText];
		if (seriesName && [seriesName caseInsensitiveCompare:self.seriesTitle] == NSOrderedSame) {
			NSString * tvdbID= [self getStringForPattern:@"<seriesid>(\\d*)" fromString:series];
			NSString * zap2ID= [self getStringForPattern:@"<zap2it_id>(.*)</zap2it_id>" fromString:series];
			if (tvdbID) {
				NSString * details = [NSString stringWithFormat:@"tvdb has %@ for our %@; %@ ", zap2ID, [self episodeIDForReporting],[self urlForReporting:tvdbID]  ];
				DDLogVerbose(@"Had to search by name %@, %@",self.showTitle, details);
				tiVoManager.theTVDBStatistics[KMTVDBSeriesFoundName@"Count"] = @([tiVoManager.theTVDBStatistics[KMTVDBSeriesFoundName@"Count"] intValue] + 1);
				[((NSMutableDictionary *)tiVoManager.theTVDBStatistics[KMTVDBSeriesFoundName@"List"]) setValue:  details forKey:self.showTitle  ];
				return tvdbID;
			} else {
				return nil;
			}
		}
	}
	return nil;

}

-(void)getTheTVDBDetails
{
	if (_gotTVDBDetails) {
		return;
	}
    if (!tiVoManager.theTVDBStatistics) {
		tiVoManager.theTVDBStatistics = [NSMutableDictionary dictionaryWithDictionary:@{
										 kMTVDBWrongInfo@"List":[NSMutableDictionary dictionary],
										 kMTVDBNoEpisode@"List":[NSMutableDictionary dictionary],
										 KMTVDBSeriesFoundName@"List":[NSMutableDictionary dictionary],
										 kMTVDBNoSeries@"List":[NSMutableDictionary dictionary]}];
	}
	if (self.seriesId.length && [self.seriesId startsWith:@"SH"]) { //if we have a series get the other informaiton
        NSString *episodeNum = nil, *seasonNum = nil, *artwork = nil;
        NSDictionary *episodeEntry = [tiVoManager.tvdbCache objectForKey:self.episodeID];
        DDLogVerbose(@"%@ %@",episodeEntry? @"Already had": @"Need to get",self.showTitle);
		NSString *seriesIDTVDB = [tiVoManager.tvdbSeriesIdMapping objectForKey:_seriesTitle]; // see if we've already done this
		if (episodeEntry) { // We already have this information 
            episodeNum = [episodeEntry objectForKey:@"episode"];
            seasonNum = [episodeEntry objectForKey:@"season"];
            artwork = [episodeEntry objectForKey:@"artwork"];
            if (!seriesIDTVDB) seriesIDTVDB = [episodeEntry objectForKey:@"series"];
			_gotTVDBDetails = YES;
			tiVoManager.theTVDBStatistics[kMTVDBCached] = @([tiVoManager.theTVDBStatistics[kMTVDBCached] intValue] + 1);
        } else {
            if (!seriesIDTVDB) {
				NSString *longSeriesID = self.seriesId;
				NSString *seriesID = nil;  //signal same as longseries
				if (self.seriesId.length < 10) {
					seriesID = self.seriesId;
					longSeriesID = [NSString stringWithFormat:@"SH00%@",[longSeriesID substringFromIndex:2]];
				}
				NSString * epSeriesID = [NSString stringWithFormat:@"EP%@",[longSeriesID substringFromIndex:2]];
				
				
				if (!seriesIDTVDB)  seriesIDTVDB = [self retrieveTVDBIdFromZap2itId:epSeriesID ofType:KMTVDBSeriesFoundWithEP];
				if (!seriesIDTVDB)  seriesIDTVDB = [self retrieveTVDBIdFromZap2itId:longSeriesID ofType:KMTVDBSeriesFoundWithSH];
				if (!seriesIDTVDB)  seriesIDTVDB = [self retrieveTVDBIdFromZap2itId:seriesID ofType:KMTVDBSeriesFoundWithShort];
				if (!seriesIDTVDB)  seriesIDTVDB = [self retrieveTVDBIdFromSeriesName];
				
				if (seriesIDTVDB) {
					[tiVoManager.tvdbSeriesIdMapping setObject:seriesIDTVDB forKey:_seriesTitle];
				} else {
					[tiVoManager.tvdbSeriesIdMapping setObject:@"" forKey:_seriesTitle];
					DDLogDetail(@"TheTVDB series not found: %@: %@ ",self.seriesTitle, self.seriesId);
					tiVoManager.theTVDBStatistics[kMTVDBNoSeries@"Count"] = @([tiVoManager.theTVDBStatistics[kMTVDBNoSeries@"Count"] intValue] + 1);
					[((NSMutableDictionary *)tiVoManager.theTVDBStatistics[kMTVDBNoSeries@"List"]) setValue: self.seriesId forKey:self.seriesTitle ];
				}
			
            }
            if (seriesIDTVDB.length) {
				//Now get the details
				NSString *urlString = [[NSString stringWithFormat:@"http://thetvdb.com/api/GetEpisodeByAirDate.php?apikey=%@&seriesid=%@&airdate=%@",kMTTheTVDBAPIKey,seriesIDTVDB,self.originalAirDateNoTime] stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
				DDLogDetail(@"urlString %@",urlString);
				NSURL *url = [NSURL URLWithString:urlString];
				NSString *episodeInfo = [NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:nil];
				if (episodeInfo) {
					episodeNum = [self getStringForPattern:@"<Combined_episodenumber>(\\d*)" fromString:episodeInfo];
					seasonNum = [self getStringForPattern:@"<Combined_season>(\\d*)" fromString:episodeInfo];
					artwork = [self getStringForPattern:@"<filename>(.*)<\\/filename>" fromString:episodeInfo];
					if (!seasonNum) {
						seasonNum = @"";
						NSString * details = [NSString stringWithFormat:@"%@ aired %@ %@ ",[self episodeIDForReporting ], self.originalAirDateNoTime, [self urlForReporting:seriesIDTVDB] ];
						DDLogDetail(@"No episode info for %@ %@ ",self.episodeTitle, details);
						tiVoManager.theTVDBStatistics[kMTVDBNoEpisode @"Count"] = @([tiVoManager.theTVDBStatistics[kMTVDBNoEpisode @"Count"] intValue] + 1);
						[((NSMutableDictionary *)tiVoManager.theTVDBStatistics[kMTVDBNoEpisode@"List"]) setValue:  details forKey:self.showTitle  ];
					} else {
						DDLogDetail(@"Got episode %@, season %@ and artwork %@ from %@",episodeNum, seasonNum, artwork, self);
						tiVoManager.theTVDBStatistics[kMTVDBEpisode] = @([tiVoManager.theTVDBStatistics[kMTVDBEpisode] intValue] + 1);
					}
					if (!episodeNum) episodeNum = @"";
					if (!artwork) artwork = @"";
					if (!seriesIDTVDB) seriesIDTVDB = @"";
					[tiVoManager.tvdbCache setObject:@{
					     @"season":seasonNum,
						 @"episode":episodeNum,
						 @"artwork":artwork,
						 @"series": seriesIDTVDB,
  					     @"date":[NSDate date]
					 } forKey:self.episodeID];
					_gotTVDBDetails = YES;
				}
			}
       }
		if (episodeNum.length && seasonNum.length) {
			//special case due to parsing of tivo's season/episode combined string
			if (self.season > 0 && self.season/10 == [seasonNum intValue]  && [episodeNum intValue] == self.episode) {
				//must have mis-parsed, so let's fix
				NSString * details = [NSString stringWithFormat:@"%@/%@ v our %d/%d aired %@ %@ ",seasonNum, episodeNum, self.season, self.episode, self.originalAirDateNoTime,  [self urlForReporting:seriesIDTVDB]];
				DDLogDetail(@"TVDB says we misparsed for %@: %@", self.showTitle, details );
				self.season = [seasonNum intValue];
			}
			if (self.episode >0 && self.season > 0) {
				//both sources have sea/epi; so compare for report
				if ([episodeNum intValue] != self.episode || [seasonNum intValue] != self.season) {
					NSString * details = [NSString stringWithFormat:@"%@/%@ v our %d/%d; %@ aired %@; %@ ",seasonNum, episodeNum, self.season, self.episode, [self episodeIDForReporting], self.originalAirDateNoTime,  [self urlForReporting:seriesIDTVDB]];
					DDLogDetail(@"TheTVDB has different Sea/Eps info for %@: %@", self.showTitle, details );
					tiVoManager.theTVDBStatistics[kMTVDBWrongInfo@"Count"] = @([tiVoManager.theTVDBStatistics[kMTVDBWrongInfo@"Count"] intValue] + 1);
					[((NSMutableDictionary *)tiVoManager.theTVDBStatistics[kMTVDBWrongInfo@"List"]) setValue:  details forKey:self.showTitle  ];
				} else {
					tiVoManager.theTVDBStatistics[kMTVDBRightInfo] = @([tiVoManager.theTVDBStatistics[kMTVDBRightInfo] intValue] + 1);
				}
			} else {
				self.episode = [episodeNum intValue];
				self.season = [seasonNum intValue];
				tiVoManager.theTVDBStatistics[kMTVDBNewInfo] = @([tiVoManager.theTVDBStatistics[kMTVDBNewInfo] intValue] + 1);
				DDLogVerbose(@"Adding TVDB season/episode  %@ to show %@",self.episodeNumber, self.showTitle);
			}
		}

        if (artwork.length) self.tvdbArtworkLocation = artwork;
		DDLogVerbose(@"Remaining Operations: %ld",self.tiVo.queue.operationCount);
		if (self.tiVo.queue.operationCount ==1) {  //we're the last one to load on this tivo, so print out stats.
			DDLogMajor(@"Statistics for TVDB since start or reset: %@",tiVoManager.theTVDBStatistics);
		}
    }
}

-(void)retrieveTVDBArtworkIntoPath: (NSString *) path
{
	if(_gotTVDBDetails) {
		[self getTheTVDBDetails];
	}
	if (_tvdbArtworkLocation.length == 0 ||
		self.episodeNumber.length == 0 ||
		self.season == 0) {
		return;
	}
	NSString * extension = [_tvdbArtworkLocation pathExtension];
	
	NSString * destination = [NSString stringWithFormat:@"%@_%@.%@",path, [self seasonEpisode],extension];
	
	//download only if we don't have it already
	if (![[NSFileManager defaultManager] fileExistsAtPath:destination]) {
		NSString *urlString = [[NSString stringWithFormat:@"http://thetvdb.com/banners/%@",_tvdbArtworkLocation] stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
		DDLogDetail(@"downloading artwork at %@",urlString);
		NSURLRequest *theRequest = [NSURLRequest requestWithURL:[NSURL URLWithString:urlString]
												cachePolicy:NSURLRequestUseProtocolCachePolicy
											timeoutInterval:60.0];
		
		// Create the connection with the request and start loading the data.
		NSURLDownload  *theDownload = [[NSURLDownload alloc] initWithRequest:theRequest
																delegate:nil];
		if (theDownload) {
			// Set the destination file.
			[theDownload setDestination:destination allowOverwrite:YES];
		}
	}
}



-(NSString *)getStringForPattern:(NSString *)pattern fromString:(NSString *)string
{
    NSError *error = nil;
    NSString *answer = nil;
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:NSRegularExpressionCaseInsensitive error:&error];
    if (error) {
        DDLogReport(@"GetStringFormPattern error %@",error.userInfo);
        return nil;
    }
    NSTextCheckingResult *result = [regex firstMatchInString:string options:NSMatchingWithoutAnchoringBounds range:NSMakeRange(0, string.length)];
    if (result && [result numberOfRanges] > 1) {
        NSRange rangeOfanswer = [result rangeAtIndex:1];
        answer = [string substringWithRange:rangeOfanswer];
    }
    return answer;
    
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
	return [self.showTitle isEqual: show.showTitle] &&
			self. showID == show.showID &&
		   [self.tiVoName isEqual: show.tiVoName];
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
		//NSString *title = [decoder decodeObjectForKey:kTitleKey];
		//float rating = [decoder decodeFloatForKey:kRatingKey];
		self.showID   = [[decoder decodeObjectForKey: kMTQueueID] intValue];
		[self setShowSeriesAndEpisodeFrom:[decoder decodeObjectForKey: kMTQueueTitle] ] ;
		NSString * tivoName = [decoder decodeObjectForKey: kMTQueueTivo] ;
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

- (id)pasteboardPropertyListForType:(NSString *)type {
//	NSLog(@"QQQ:pboard Type: %@",type);
	if ([type compare:kMTTivoShowPasteBoardType] ==NSOrderedSame) {
		return  [NSKeyedArchiver archivedDataWithRootObject:self];
	} else {
		return nil;
	}
}
-(NSArray *)writableTypesForPasteboard:(NSPasteboard *)pasteboard {
	NSArray* result = [NSArray  arrayWithObjects: kMTTivoShowPasteBoardType, nil];  //NOT working yet
//	NSLog(@"QQQ:writeable Type: %@",result);
	return result;
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


#pragma  mark - parser methods

-(void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName attributes:(NSDictionary *)attributeDict
{
	elementString = [NSMutableString new];
	if ([elementName compare:@"element"] != NSOrderedSame) {
		elementArray = [NSMutableArray new];
	}
}

-(void)parser:(NSXMLParser *)parser foundCharacters:(NSString *)string
{
	[elementString appendString:string];
}

- (void)setValue:(id)value forUndefinedKey:(NSString *)key{
    //nothing to see here; just move along
	DDLogVerbose(@"Unrecognized key %@", key);
}

-(void) endElement:(NSString *)elementName item:(id) item {
	DDLogDetail(@" %@: %@",elementName, item);

}

-(void)parser:(NSXMLParser *)parser didEndElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName
{
	if (parseTermMapping[elementName]) {
		elementName = parseTermMapping[elementName];
	}
	if ([elementName compare:@"element"] == NSOrderedSame) {
		[elementArray addObject:elementString];
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
	_gotDetails = NO;
	DDLogMajor(@"Show: %@ Parser Error %@",self.showTitle, parseError);
}

#pragma mark - Custom Getters

-(NSString *)showKey
{
	return [NSString stringWithFormat:@"%@: %@",self.tiVoName,self.idString];
}
												  
-(NSString *) seasonEpisode {
    
    NSString *returnString = @"";
    if (_episode > 0) {
		if (_season > 0) {
			returnString = [NSString stringWithFormat:@"S%0.2dE%0.2d",_season,_episode ];
		} else {
			returnString = [NSString stringWithFormat:@"%d",_episode];
		}
     } else {
        returnString = _episodeNumber;
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
        self.seriesTitle = [self seriesFromProgram:_showTitle];
    }
    return _seriesTitle;
}

-(BOOL) isMovie {
	BOOL value =  (self.movieYear.length > 0) ||
				  ([self.episodeID hasPrefix:@"MV"]) ||
					!((self.episodeTitle.length > 0) ||
					   (self.episode > 0) ||
					   (self.showLength < 70*60)) ;
	return value;
}

-(NSAttributedString *)attrStringFromDictionary:(id)nameList
{
    NSMutableString *returnString = [NSMutableString string];
    if ([nameList isKindOfClass:[NSArray class]]) {
        for (NSDictionary *name in nameList) {
            [returnString appendFormat:@"%@\n",[self nameString:name]];
        }
       	if (returnString.length > 0)[returnString deleteCharactersInRange:NSMakeRange(returnString.length-1, 1)];
		
    }
	return [[NSAttributedString alloc] initWithString:returnString attributes:@{NSFontAttributeName : [NSFont systemFontOfSize:11]}];
    
}

-(NSAttributedString *)attribDescription {
	NSAttributedString *attstring = [[NSAttributedString alloc] initWithString:@""];
	if (self.showDescription) {
		attstring = [[NSAttributedString alloc] initWithString:self.showDescription];
	}
	return attstring;
}

-(NSAttributedString *)actors
{
    return [self attrStringFromDictionary:_vActor];
}

-(NSAttributedString *)guestStars
{
    return [self attrStringFromDictionary:_vGuestStar];
}

-(NSAttributedString *)directors
{
    return [self attrStringFromDictionary:_vDirector];
}

-(NSAttributedString *)producers
{
    return [self attrStringFromDictionary:_vExecProducer];
}

-(NSString *)yearString
{
    return [NSString stringWithFormat:@"%d",_episodeYear];
}

-(NSString *)seasonString
{
	NSString *returnString = @"";
	if (_season > 0) {
		returnString = [NSString stringWithFormat:@"%d",_season];
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

-(const MP4Tags * ) metaDataTagsWithImage: (NSImage* ) image {
	const MP4Tags *tags = MP4TagsAlloc();
	uint8_t mediaType = 10;
	if (self.isMovie) {
		mediaType = 9;
	}
	MP4TagsSetMediaType(tags, &mediaType);
	if (self.episodeTitle.length>0) {
		MP4TagsSetName(tags,[self.episodeTitle cStringUsingEncoding:NSUTF8StringEncoding]);
	}
	if (self.episodeGenre.length>0) {
		MP4TagsSetGenre(tags,[self.episodeGenre cStringUsingEncoding:NSUTF8StringEncoding]);
	}
	if (self.originalAirDate.length>0) {
		MP4TagsSetReleaseDate(tags,[self.originalAirDateNoTime cStringUsingEncoding:NSUTF8StringEncoding]);
	} else if (self.movieYear.length>0) {
		MP4TagsSetReleaseDate(tags,[self.movieYear	cStringUsingEncoding:NSUTF8StringEncoding]);
	}
	
	if (self.showDescription.length > 0) {
		if (self.showDescription.length < 255) {
			MP4TagsSetDescription(tags,[self.showDescription cStringUsingEncoding:NSUTF8StringEncoding]);
			
		} else {
			MP4TagsSetDescription(tags,[[self.showDescription  substringToIndex:255] cStringUsingEncoding:NSUTF8StringEncoding]);
			MP4TagsSetLongDescription(tags,[self.showDescription cStringUsingEncoding:NSUTF8StringEncoding]);
		}
	}
	if (self.seriesTitle.length>0) {
		MP4TagsSetTVShow(tags,[self.seriesTitle cStringUsingEncoding:NSUTF8StringEncoding]);
		MP4TagsSetArtist(tags,[self.seriesTitle cStringUsingEncoding:NSUTF8StringEncoding]);
		MP4TagsSetAlbumArtist(tags,[self.seriesTitle cStringUsingEncoding:NSUTF8StringEncoding]);
	}
	if (self.episode > 0) {
		uint32_t episodeNum = self.episode;
		MP4TagsSetTVEpisode(tags, &episodeNum);
	} else if (self.episodeNumber.length>0) {
		uint32_t episodeNum =  [self.episodeNumber intValue];
		MP4TagsSetTVEpisode(tags, &episodeNum);
		
	}
	if (self.season > 0 ) {
		uint32_t showSeason =  self.season;
		MP4TagsSetTVSeason(tags, &showSeason);
		MP4TagsSetAlbum(tags,[[NSString stringWithFormat: @"%@, Season %d",self.seriesTitle, self.season] cStringUsingEncoding:NSUTF8StringEncoding]) ;
	} else {
		MP4TagsSetAlbum(tags,[self.seriesTitle cStringUsingEncoding:NSUTF8StringEncoding]) ;

	}
	if (self.stationCallsign) {
		MP4TagsSetTVNetwork(tags, [self.stationCallsign cStringUsingEncoding:NSUTF8StringEncoding]);
	}
	
	if (image) {
		NSData *PNGData  = [NSBitmapImageRep representationOfImageRepsInArray: [image representations]
																	usingType:NSPNGFileType properties:nil];
		MP4TagArtwork artwork;
		
		artwork.data = (void *)[PNGData bytes];
		artwork.size = (uint32_t)[PNGData length];
		artwork.type = MP4_ART_PNG;
		
		MP4TagsAddArtwork(tags, &artwork);
	}
	
	return tags;
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
			return @"questionmark";
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
-(NSString *) episodeGenre {
    //iTunes says "there can only be one", so pick the first we see.
    NSCharacterSet * quotes = [NSCharacterSet characterSetWithCharactersInString:@"\""];
    NSString * firstGenre = nil;
    if (_vSeriesGenre.count > 0) firstGenre = [_vSeriesGenre objectAtIndex:0];
	else if (_vProgramGenre.count > 0) firstGenre = [_vProgramGenre objectAtIndex:0];
	else firstGenre = @"";
    return [firstGenre stringByTrimmingCharactersInSet:quotes];
}

-(NSString *) tiVoName {
	if (_tiVo) {
		return _tiVo.tiVo.name;
	} else {
		return self.tempTiVoName;
	}
}

-(void) setProgramId:(NSString *)programId {
	if (programId != _programId) {
		_programId = programId;
		_episodeID = programId;
		if (_episodeID.length == 12) {
			_episodeID = [NSString stringWithFormat:@"%@00%@",[_episodeID substringToIndex:2],[_episodeID substringFromIndex:2]];
		}
		if (![_episodeID hasPrefix:@"MV"] && [_episodeID hasSuffix:@"0000"] ) {
			NSDateFormatter *dateFormat = [[NSDateFormatter alloc] init] ;
			[dateFormat setDateStyle:NSDateFormatterShortStyle];
			[dateFormat setTimeStyle:NSDateFormatterNoStyle] ;
			_episodeID = [NSString stringWithFormat: @"%@-%@",_episodeID, [dateFormat stringFromDate: _showDate] ];
		}
	}
}

#pragma mark - Custom Setters; many for parsing


-(void) setShowTime: (NSString *) newTime {
	if (newTime != _showTime) {
        _showTime = newTime;
        NSDate *newDate =[_showTime dateForRFC3339DateTimeString];
        if (newDate) {
            self.showDate = newDate;
        }
		//        NSLog(@"converting %@ from: %@ to %@ ", self.showTitle, newTime, self.showDate);
    }
}
-(void)setMovieYear:(NSString *)movieYear {
	if (movieYear != _movieYear) {
		_movieYear = movieYear;
		if (self.originalAirDateNoTime.length == 0) {
			_originalAirDateNoTime = movieYear;
		}
	}
}

-(void) setImageString:(NSString *)imageString {
	if (imageString != _imageString) {
		_imageString = imageString;
		_isSuggestion = [@"suggestion-recording" isEqualToString:imageString];
	}
}

-(void)setOriginalAirDate:(NSString *)originalAirDate
{
	if (originalAirDate != _originalAirDate) {
		_originalAirDate = originalAirDate;
		if (originalAirDate.length > 4) {
			_episodeYear = [[originalAirDate substringToIndex:4] intValue];
		}
		if (originalAirDate.length >= 10) {
			_originalAirDateNoTime = [originalAirDate substringToIndex:10];
		} else if (originalAirDate.length > 0) {
			_originalAirDateNoTime = originalAirDate;
		} else {
			_originalAirDateNoTime = _movieYear;
		}
	}
}

-(void)setEpisodeNumber:(NSString *)episodeNumber
{
	if (episodeNumber != _episodeNumber) {  // this check is mandatory
        _episodeNumber = episodeNumber;
		if (episodeNumber.length) {
			long l = episodeNumber.length;
			if (l > 2) {
				int epDigits = (l > 4) ? 3:2; 
					_episode = [[episodeNumber substringFromIndex:l-epDigits] intValue];
					_season = [[episodeNumber substringToIndex:l-epDigits] intValue];
			} else {
				_episode = [episodeNumber intValue];
			}
		}
	}
	
}

-(void)playVideo:(NSString *)path
{
    [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:path]];

}

-(void)revealInFinder:(NSArray *)paths
{
   	NSMutableArray * showURLs = [NSMutableArray arrayWithCapacity:paths.count];
	for (NSString *fileName in paths) {
		NSURL * showURL = [NSURL fileURLWithPath:fileName];
		if (showURL) {
			[showURLs addObject:showURL];
		}
	}
	if (showURLs.count > 0) {
		[[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:showURLs];
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
		_seriesTitle = seriesTitle;
		if (_episodeTitle.length > 0 ) {
			self.showTitle =[NSString stringWithFormat:@"%@: %@",_seriesTitle, _episodeTitle];
		} else {
			self.showTitle =_seriesTitle;
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
    NSString * tribuneCopyright = @" Copyright Tribune Media Services, Inc.";
	if (_showDescription == showDescription) {
		return;
	}
    if ([showDescription hasSuffix: tribuneCopyright]){
        _showDescription = [showDescription substringToIndex:showDescription.length -tribuneCopyright.length];
    } else {
        _showDescription = showDescription;

    }
}

-(void)setVActor:(NSArray *)vActor
{
	if (_vActor == vActor || ![vActor isKindOfClass:[NSArray class]]) {
		return;
	}
	_vActor = [self parseNames: vActor ];
}

-(void)setVGuestStar:(NSArray *)vGuestStar
{
	if (_vGuestStar == vGuestStar || ![vGuestStar isKindOfClass:[NSArray class]]) {
		return;
	}
	_vGuestStar = [self parseNames: vGuestStar ];
}

-(void)setVDirector:(NSArray *)vDirector
{
	if (_vDirector == vDirector || ![vDirector isKindOfClass:[NSArray class]]) {
		return;
	}
	_vDirector = [self parseNames: vDirector ];
}

-(void)setVExecProducer:(NSArray *)vExecProducer
{
	if (_vExecProducer == vExecProducer || ![vExecProducer isKindOfClass:[NSArray class]]) {
		return;
	}
	_vExecProducer = [self parseNames:vExecProducer];
}


-(void)setVProgramGenre:(NSArray *)vProgramGenre
{
	if (_vProgramGenre == vProgramGenre || ![vProgramGenre isKindOfClass:[NSArray class]]) {
		return;
	}
	_vProgramGenre = vProgramGenre;
}

-(void)setVSeriesGenre:(NSArray *)vSeriesGenre{
	if (_vSeriesGenre == vSeriesGenre || ![vSeriesGenre isKindOfClass:[NSArray class]]) {
		return;
	}
	_vSeriesGenre = vSeriesGenre;
}

#pragma mark - Memory Management

-(void)dealloc
{
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
    return [NSString stringWithFormat:@"%@ (%@)%@",_showTitle,self.tiVoName,[_protectedShow boolValue]?@"-Protected":@""];
}


@end

