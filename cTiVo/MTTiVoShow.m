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
#import "NSNotificationCenter+Threads.h"

@interface MTTiVoShow () {
	
	NSMutableString *elementString;
	NSMutableArray *elementArray;
	NSArray *arrayHolder;
	NSDictionary *parseTermMapping;

}
//rewrite external readonly properties (from detail XML) to allow internal readwrite
@property (atomic, strong, readwrite) NSString
                                *episodeNumber,
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

@property (nonatomic, assign) BOOL ignoreSection; //are we skipping this section in XML (esp vActualShowing)

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
		_gotTVDBDetails = NO;
		elementString = nil;
		self.inProgress = @(NO); //This is the default
		_season = 0;
		_episode = 0;
		_episodeNumber = @"";
        _isQueued = NO;
		_episodeTitle = @"";
		_seriesTitle = @"";
//		_originalAirDate = @"";
        _tvdbArtworkLocation = nil;
		
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

//Note that getDetails and getTVDB need to be thread-safe. In particular, any setting of values that might be displayed needs to occur on main thread,
//and any access to global data needs to @synchronized
#pragma mark - access theTVDB
//These will be printed out in alpha order...
#define kMTVDBNoEpisode @"Episode Not Found"
#define kMTVDBEpisode @"Episode Found"
#define kMTVDBEpisodeCached @"Episode Found in Cache"
#define kMTVDBMovieInfoFound @"Movie Found"
#define kMTVDBMovieNotFound @"Movie"
#define kMTVDBNewInfo   @"Season/Episode Info Added"
#define kMTVDBWrongInfo @"Season/Episode Info Mismatch"
#define kMTVDBRightInfo @"Season/Episode Info Match"
#define kMTVDBSeriesFoundWithEP @"Series Found EP"
#define kMTVDBSeriesFoundCached @"Series Found In Cache"
#define kMTVDBSeriesFoundWithSH @"Series Found SH"
#define kMTVDBSeriesFoundWithShort @"Series Found SHShort"
#define kMTVDBSeriesFoundName @"Series Found by Name"
#define kMTVDBNoSeriesInfo @"Series Info Not Found"
#define kMTVDBNoSeries @"Show Not Found"


-(NSString *) seriesIDForReporting {
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

-(NSString *) urlsForReporting:(NSArray *) tvdbIDs {
    NSMutableArray * urls = [NSMutableArray arrayWithCapacity:tvdbIDs.count];
    for (NSString * tvdbID in tvdbIDs) {
        NSString * showURL = [NSString stringWithFormat:@"http://thetvdb.com/?tab=series&id=%@",tvdbID];
        [urls addObject:showURL];
    }
	return [urls componentsJoinedByString: @" OR "];
}

-(NSArray <NSString *> *) retrieveTVDBIdFromSeriesName: (NSString *) name  {
    //probably called on background thread to check if series with same name is available
    NSAssert (![NSThread isMainThread], @"retrieveTVDBIdFromSeriesName not running in background");
	NSString * urlString = [[NSString stringWithFormat:@"http://thetvdb.com/api/GetSeries.php?seriesname=%@&language=all",name] stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
	NSURL *url = [NSURL URLWithString:urlString];
	DDLogDetail(@"Getting series for %@ using %@",self,urlString);
	NSString *seriesID = [NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:nil];
	//This can result in multiple series return only 1 of which is correct.  First break up into Series
	NSArray *serieses = [seriesID componentsSeparatedByString:@"<Series>"];
    NSMutableSet <NSString *> *tvdbIDs = [NSMutableSet set];
	DDLogDetail(@"Series for %@: %@",self,serieses);
	for (NSString *series in serieses) {
        if ([series hasPrefix: @"<?xml"]) continue;
		NSString *seriesName = [[self getStringForPattern:@"<SeriesName>(.*)<\\/SeriesName>" fromString:series] stringByConvertingHTMLToPlainText];
        if (![seriesName hasCaseInsensitivePrefix:name]) {
            //check aliases
            NSString * aliasesString = [[self getStringForPattern:@"<AliasNames>(.*)<\\/AliasNames>" fromString:series] stringByConvertingHTMLToPlainText];
            if (aliasesString.length > 0) {
                NSArray <NSString *> * aliases = [aliasesString componentsSeparatedByString:@"|"];
                for (NSString * alias in aliases) {
                    if ([alias hasCaseInsensitivePrefix:name] ) {
                        seriesName = name;
                        break;
                    }
                }
            }
        }
		if (seriesName && [seriesName hasCaseInsensitivePrefix:name]) {
			NSString * tvdbID= [self getStringForPattern:@"<seriesid>(\\d*)" fromString:series];
			NSString * zap2ID= [self getStringForPattern:@"<zap2it_id>(.*)</zap2it_id>" fromString:series];
			if (tvdbID.length) {
				NSString * details = [NSString stringWithFormat:@"tvdb has %@ for our %@; %@ ", zap2ID, [self seriesIDForReporting],[self urlsForReporting:@[tvdbID] ]];
				DDLogVerbose(@"Had to search by name %@, %@",self.showTitle, details);
                [self addValue:details inStatistic:kMTVDBSeriesFoundName forShow:self.seriesTitle];
                if (![tvdbIDs containsObject:tvdbID]){
                    [tvdbIDs addObject:tvdbID];
                }
            }
		}
	}
    DDLogDetail(@"Mapped %@ series to %@", name, [[tvdbIDs allObjects] componentsJoinedByString:@" OR "]);
	return [tvdbIDs allObjects];

}

-(void) incrementStatistic: (NSString *) statistic {
    @synchronized(tiVoManager.theTVDBStatistics) {
        tiVoManager.theTVDBStatistics[statistic] = @([tiVoManager.theTVDBStatistics[statistic] intValue] + 1);
    }
}

-(void) addValue:(NSString *) value inStatistic:(NSString *) statistic forShow:(NSString *) show {
    @synchronized(tiVoManager.theTVDBStatistics) {
        NSString * statisticListName = [statistic stringByAppendingString:@" List"];
        NSMutableDictionary * statisticList = tiVoManager.theTVDBStatistics[statisticListName]; //shorthand
        if (!statisticList) {
            statisticList = [NSMutableDictionary dictionary];
            [tiVoManager.theTVDBStatistics setObject:statisticList forKey:statisticListName];
        }
        if (!statisticList[self.showTitle]) {
            [statisticList setValue: value forKey: show];
            NSString * statisticCount = [statistic stringByAppendingString:@" Count"];
            tiVoManager.theTVDBStatistics[statisticCount] = @([tiVoManager.theTVDBStatistics[statisticCount] intValue] + 1);
        }
        [statisticList setValue: value forKey: show]; //keep latest version in case it changed

    }
}

-(void)  updateSeason: (int) season andEpisode: (int) episode {
    NSAssert ([NSThread isMainThread], @"updateSeason running in background");
    self.episodeNumber = [NSString stringWithFormat:@"%d%02d",season, episode];
    self.episode = episode;
    self.season = season;
    [[ NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationDetailsLoaded object:self];
}

-(void) rememberTVDBSeriesID: (NSArray *) seriesIDs {
    if (seriesIDs.count) {
        @synchronized (tiVoManager.tvdbSeriesIdMapping) {
            [tiVoManager.tvdbSeriesIdMapping setObject:[NSArray arrayWithArray: seriesIDs] forKey:self.seriesTitle];
        }
    }
}

-(NSArray <NSString *> *) checkTVDBSeriesID:(NSString *) title {
    @synchronized (tiVoManager.tvdbSeriesIdMapping) {
       return  [tiVoManager.tvdbSeriesIdMapping objectForKey:title];
    }
}

-(void) retrieveTVDBEpisodeInfo:(NSArray <NSString *> *) seriesIDTVDBs {
    //Now get the details
@autoreleasepool {
    NSAssert (![NSThread isMainThread], @"retrieveTVDBEpisodeInfo not running in background");
    NSString * reportURL = nil;

    for (NSString * seriesIDTVDB in seriesIDTVDBs) {

        NSString *urlString = [[NSString stringWithFormat:@"http://thetvdb.com/api/GetEpisodeByAirDate.php?apikey=%@&seriesid=%@&airdate=%@",kMTTheTVDBAPIKey,seriesIDTVDB,self.originalAirDateNoTime] stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
        reportURL = [urlString stringByReplacingOccurrencesOfString:kMTTheTVDBAPIKey withString:@"APIKEY" ];
        DDLogDetail (@"launching %@ for %@", reportURL, self.showTitle);
        NSURL *url = [NSURL URLWithString:urlString];
        NSError * error = nil;
        NSString * episodeInfo = [NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:&error];

        if (error) {
            DDLogMajor(@"Failed to get info from TVDB for %@ at %@: %@",self.showTitle, reportURL, error.localizedDescription);
        } else if (!episodeInfo.length) {
            DDLogMajor(@"No error from TVDB for %@ at %@, but no content",self.showTitle, reportURL);
        } else {
            NSString * errorMsg = [self getStringForPattern:@"<Error>(.*)<\\/Error>" fromString:episodeInfo];
            if (errorMsg.length > 0) {
                DDLogDetail(@"TVDB Error for %@(%@) aired %@ at %@ : %@ ",self.showTitle,[self seriesIDForReporting ], self.originalAirDateNoTime, reportURL, errorMsg );
            } else {
                NSString * newEpisodeNum = [self getStringForPattern:@"<Combined_episodenumber>(\\d*)" fromString:episodeInfo] ?: @"";
                NSString * newSeasonNum = [self getStringForPattern:@"<Combined_season>(\\d*)" fromString:episodeInfo] ?: @"";
                NSString * newArtwork = [self getStringForPattern:@"<filename>(.*)<\\/filename>" fromString:episodeInfo] ?: @"";
                if (newEpisodeNum.length + newSeasonNum.length + newArtwork.length == 0) {
                    //TVDB gateway gives error code in HTML so this hack parses
                    NSString * gatewayErrorNum = [self getStringForPattern:@"<span class=\"cf-error-code\">(\\d*)</span>" fromString:episodeInfo] ?: @"";
                    NSString * gatewayError = [self getStringForPattern:@"<h2 class=\"cf-subheadline\" data-translate=\"error_desc\">(.*)</h2>" fromString:episodeInfo] ?: @"";
                    if (gatewayErrorNum.length + gatewayError.length > 0) {
                        DDLogMajor(@"TVDB server %@ problem for %@ at %@: %@",gatewayErrorNum, self.showTitle, reportURL, gatewayError);
                    } else {
                        DDLogMajor(@"TVDB server failure; no error msg for %@ at %@", self.showTitle, reportURL);
                    }
                } else {
                    if (![seriesIDTVDBs[0] isEqualToString:seriesIDTVDB]) {
                        DDLogDetail(@"Found theTVDB on second+ try for %@", self.episodeTitle);
                        //move to first position for other episodes
                        NSMutableArray <NSString *> * newSeriesIDTVBs = [NSMutableArray arrayWithArray:seriesIDTVDBs];
                        [newSeriesIDTVBs removeObject:seriesIDTVDB];
                        [newSeriesIDTVBs insertObject:seriesIDTVDB atIndex:0];
                        [self rememberTVDBSeriesID:newSeriesIDTVBs];
                    }
                    @synchronized (tiVoManager.tvdbCache) {
                        [tiVoManager.tvdbCache setObject:@{
                                                           @"season":newSeasonNum,
                                                           @"episode":newEpisodeNum,
                                                           @"artwork":newArtwork,
                                                           @"series": seriesIDTVDB,
                                                           @"date":[NSDate date]
                                                           } forKey:self.episodeID];
                    }
                    _gotTVDBDetails = YES;
                   dispatch_async(dispatch_get_main_queue(), ^{
                       [self finishTVDBProcessing];
                   });
                    DDLogDetail (@"Got episode Info for %@: %@ ops",  self.showTitle, @(tiVoManager.tvdbQueue.operationCount));
                    return;
                }
            }
        }
    }
    //So, an episode not found case, let's report but also try series lookup for artwork
    if (seriesIDTVDBs.count > 1) {
        DDLogDetail(@"Did not find TVDB on second+ try for %@", self.showTitle);
    }

    NSString * details = [NSString stringWithFormat:@"%@ aired %@ (our  %d/%d) at %@ ",[self seriesIDForReporting ], self.originalAirDateNoTime, self.season, self.episode, reportURL ];
    DDLogDetail(@"No episode info for %@ (%@) %@ ",self.showTitle, [seriesIDTVDBs componentsJoinedByString:@"OR"], details );
    [self addValue:details inStatistic:kMTVDBNoEpisode forShow:self.showTitle];

    BOOL gotsOne;
    @synchronized (tiVoManager.tvdbCache) {
        gotsOne = ( tiVoManager.tvdbCache [self.seriesId][@"artwork"]) !=nil;
    }
    if (gotsOne) {
        _gotTVDBDetails = YES;
        dispatch_async(dispatch_get_main_queue(), ^{
            [self finishTVDBProcessing];
        });
    } else {
        [self retrieveTVDBSeriesInfo:seriesIDTVDBs];
    }

    //    NSTimeInterval time = 1.0/kMTMaxTVDBRate + [date timeIntervalSinceNow];
    //    if (time > 0) [NSThread sleepForTimeInterval:time];
    //ensures our operation stays officially running, so not hammering the TVDB API
}
}

-(void) retrieveTVDBSeriesInfo:(NSArray <NSString *> *) seriesIDTVDBs {
    //for non-episodic series, get the artwork info
    @autoreleasepool {
        if (seriesIDTVDBs.count ==0) return;
        NSString * seriesIDTVDB = seriesIDTVDBs[0];
        NSAssert (![NSThread isMainThread], @"retrieveTVDBESeriesInfo not running in background");
        //      <mirrorpath>/api/GetSeries.php?seriesname=<seriesname> <mirrorpath>/api/GetSeries.php?seriesname=<seriesname>&language=<language>
        NSString *urlString = [NSString stringWithFormat:@"http://thetvdb.com/api/%@/series/%@/banners.xml",kMTTheTVDBAPIKey,seriesIDTVDB];
        NSString * reportURL = [urlString stringByReplacingOccurrencesOfString:kMTTheTVDBAPIKey withString:@"APIKEY" ];
        DDLogDetail (@"launching %@ for %@", reportURL, self.showTitle);
        NSURL *url = [NSURL URLWithString:urlString];
        NSError * error = nil;
        NSString * episodeInfo = [NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:&error];

        if (error) {
            DDLogMajor(@"Failed to get series info from TVDB for %@ at %@: %@",self.showTitle, reportURL, error.localizedDescription);
        } else if (!episodeInfo.length) {
            DDLogMajor(@"No error from TVDB for series %@ at %@, but no content",self.showTitle, reportURL);
        } else {
            _gotTVDBDetails = YES;
            NSString * newArtwork = [self getStringForPattern:@"<BannerPath>(.*)</BannerPath>" fromString:episodeInfo] ?: @"";
            if (newArtwork.length > 0) {
                @synchronized (tiVoManager.tvdbCache) {
                    [tiVoManager.tvdbCache setObject:@{
                                                       @"artwork":newArtwork,
                                                       @"series": seriesIDTVDB,
                                                       @"date":[NSDate date]
                                                       } forKey:self.seriesId];
                }
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self finishTVDBProcessing];
                });
            }

        }
        //    NSTimeInterval time = 1.0/kMTMaxTVDBRate + [date timeIntervalSinceNow];
        //    if (time > 0) [NSThread sleepForTimeInterval:time];
        //ensures our operation stays officially running, so not hammering the TVDB API
        DDLogDetail (@"Got series Info for %@: %@ ops",  self.showTitle, @(tiVoManager.tvdbQueue.operationCount));
    }
}

-(void) retrieveTVDBSeriesID {
@autoreleasepool {
    NSAssert (![NSThread isMainThread], @"getTVDBSeriesID not running in background");

    NSArray <NSString *> * mySeriesIDTVDB = [self retrieveTVDBIdFromSeriesName:self.seriesTitle];
    //Don't give up yet; look for "Series: subseries" format
    if (!mySeriesIDTVDB.count)  {
        NSArray * splitName = [self.seriesTitle componentsSeparatedByString:@":"];
        if (splitName.count > 1) {
            mySeriesIDTVDB = [self retrieveTVDBIdFromSeriesName:splitName[0]];
        }
    }

    if (mySeriesIDTVDB.count) {
        DDLogDetail(@"Got TVDB for %@: %@ ",self, [mySeriesIDTVDB componentsJoinedByString:@" OR "]);
        [self rememberTVDBSeriesID:mySeriesIDTVDB];
        if ([self.episodeID hasPrefix:@"SH"]){
            [self retrieveTVDBSeriesInfo:mySeriesIDTVDB];
        } else {
            [self retrieveTVDBEpisodeInfo:mySeriesIDTVDB];
        }
   } else {
        [self rememberTVDBSeriesID: @[ ] ];
        DDLogDetail(@"TheTVDB series not found: %@: %@ ",self.seriesTitle, self.seriesId);
        [self addValue: self.seriesId   inStatistic: kMTVDBNoSeries forShow:self.seriesTitle];
        self.gotTVDBDetails = YES;
        return; //really can't get them.
    }

}
}

-(void)getTheTVDBDetails {
    //Called from main thread
    //Needs to get episode info from TVDB
    //1) do possibly multiple lookups at TheTVDB in background to find TVDB's seriesID
    //2) call retrieveTVDBEpisodeInfo in background to get Episode Info
    //3) call finishTVDBProcessing on main thread to augment TiVo's info with theTVDB
	if (_gotTVDBDetails) {
		return;
	}
	if (self.seriesId.length && [self.seriesId hasPrefix:@"SH"]) { //if we have a series get the other information
        NSDictionary *episodeEntry;
        @synchronized (tiVoManager.tvdbCache) {
            if ([self.episodeID hasPrefix:@"SH"]) {
                episodeEntry = [tiVoManager.tvdbCache objectForKey:self.seriesId];
            } else {
                episodeEntry = [tiVoManager.tvdbCache objectForKey:self.episodeID];
           }
        }
        DDLogDetail(@"%@ %@",episodeEntry? @"Already had": @"Need to get",self.showTitle);
        if (episodeEntry) { // We already had this information
 			_gotTVDBDetails = YES;
            [self incrementStatistic: ([self.episodeID hasPrefix:@"SH" ] ? kMTVDBSeriesFoundCached : kMTVDBEpisodeCached) ];
             [self finishTVDBProcessing];
        } else {
            NSArray *seriesIDTVDBs = [self checkTVDBSeriesID:self.seriesTitle];
            //Need to pace calls to TVDB API
            SEL whichTVDBMethod;
            if (seriesIDTVDBs.count) {
                // already have series ID, but not this episode info
                if ([self.episodeID hasPrefix:@"SH"]) {
                    whichTVDBMethod = @selector(retrieveTVDBSeriesInfo:);
                    DDLogDetail (@"queuing seriesInfo for %@ (%@): %@ ops", [seriesIDTVDBs componentsJoinedByString:@"OR"], self.showTitle, @(tiVoManager.tvdbQueue.operationCount));
               } else {
                    whichTVDBMethod = @selector(retrieveTVDBEpisodeInfo:);
                    DDLogDetail (@"queuing episodeInfo for %@ (%@): %@ ops", [seriesIDTVDBs componentsJoinedByString:@"OR"], self.showTitle, @(tiVoManager.tvdbQueue.operationCount));
                }
            } else {
                //first get seriesID, then Episode Info
                whichTVDBMethod = @selector(retrieveTVDBSeriesID);
                DDLogDetail (@"queuing series ID for %@: %@ ops", self.showTitle, @(tiVoManager.tvdbQueue.operationCount));
            }
            NSInvocationOperation * op = [[NSInvocationOperation alloc] initWithTarget:self selector: whichTVDBMethod object:seriesIDTVDBs ];
            [tiVoManager.tvdbQueue addOperation:op];
        }
    } else {
        //not a series; no TVDB available
        _gotTVDBDetails = YES;
    }
}

-(void) finishTVDBProcessing {

    NSString *episodeNum = nil, *seasonNum = nil, *artwork = nil;
    NSDictionary *episodeEntry;
    @synchronized (tiVoManager.tvdbCache) {
        episodeEntry = [tiVoManager.tvdbCache objectForKey:self.episodeID];
        if (!episodeEntry) episodeEntry = [tiVoManager.tvdbCache objectForKey:self.seriesId];
    }
    if (!episodeEntry) {
        DDLogReport(@"Trying to process missing TVDB data for %@",self.showTitle);
        return;
    }

    if (episodeEntry) { // We already have this information
        episodeNum = [episodeEntry objectForKey:@"episode"];
        seasonNum = [episodeEntry objectForKey:@"season"];
        artwork = [episodeEntry objectForKey:@"artwork"];
        NSArray *seriesIDTVDBs = [self checkTVDBSeriesID:self.seriesTitle];

        if (!seriesIDTVDBs.count) {
            NSString * seriesIDTVDB = [episodeEntry objectForKey:@"series"];
            if (seriesIDTVDB.length) {
                seriesIDTVDBs = @[seriesIDTVDB];
                [self rememberTVDBSeriesID:seriesIDTVDBs];
            } else {
                DDLogMajor(@"Missing series info in TVDB data for %@: %@",self.showTitle, episodeEntry);
            }

        }
        _gotTVDBDetails = YES;
        if (artwork.length+episodeNum.length+seasonNum.length > 0) {
            //got at least one
            [self incrementStatistic:kMTVDBEpisode];
            if (artwork.length) self.tvdbArtworkLocation = artwork;
        } else {
            DDLogDetail(@"QQQ %@", episodeEntry);
            NSString * details = [NSString stringWithFormat:@"%@ aired %@ (our  %d/%d) %@ ",[self seriesIDForReporting ], self.originalAirDateNoTime, self.season, self.episode, [self urlsForReporting:seriesIDTVDBs] ];
            DDLogDetail(@"No series info for %@ %@ ",self.showTitle, details);
            [self addValue:details inStatistic:kMTVDBNoSeriesInfo forShow:self.showTitle];
        }
        if (episodeNum.length && seasonNum.length && [episodeNum intValue] > 0 && [seasonNum intValue] > 0) {
            DDLogDetail(@"Got episode %@, season %@ and artwork %@ from %@",episodeNum, seasonNum, artwork, self);
            [self incrementStatistic:kMTVDBEpisode];
            //special case due to parsing of tivo's season/episode combined string
			if (self.season > 0 && self.season/10 == [seasonNum intValue]  && [episodeNum intValue] == self.episode + (self.season % 10)*10) {
				//must have mis-parsed (assumed SSEE, but actually SEEE, so let's fix
				NSString * details = [NSString stringWithFormat:@"%@/%@ v our %d/%d aired %@ %@ ",seasonNum, episodeNum, self.season, self.episode, self.originalAirDateNoTime,  [self urlsForReporting:seriesIDTVDBs]];
				DDLogDetail(@"TVDB says we misparsed for %@: %@", self.showTitle, details );
				self.season = [seasonNum intValue];
                self.episode = [episodeNum intValue];
			}
			if (self.episode >0 && self.season > 0) {
				//both sources have sea/epi; so compare for report
				if ([episodeNum intValue] != self.episode || [seasonNum intValue] != self.season) {
					NSString * details = [NSString stringWithFormat:@"%@/%@ v our %d/%d; %@ aired %@; %@ ",seasonNum, episodeNum, self.season, self.episode, [self seriesIDForReporting], self.originalAirDateNoTime,  [self urlsForReporting:seriesIDTVDBs]];
					DDLogDetail(@"TheTVDB has different Sea/Eps info for %@: %@ %@", self.showTitle, details, [[NSUserDefaults standardUserDefaults] boolForKey:kMTTrustTVDB] ? @"updating": @"leaving" );
                    [self addValue: details   inStatistic: kMTVDBWrongInfo forShow:self.showTitle];

                    if ([[NSUserDefaults standardUserDefaults] boolForKey:kMTTrustTVDB]) {
                        //user asked us to prefer TVDB
                        [self updateSeason: [seasonNum intValue] andEpisode: [episodeNum intValue]];
                    }
				} else {
                    [self incrementStatistic:kMTVDBRightInfo];
				}
			} else {
                [self updateSeason: [seasonNum intValue] andEpisode: [episodeNum intValue]];
                [self incrementStatistic:kMTVDBNewInfo];
 				DDLogVerbose(@"Adding TVDB season/episode %d/%d to show %@",self.season, self.episode, self.showTitle);
			}
        }

    } else {
        [self incrementStatistic:kMTVDBNoSeries];
        _gotTVDBDetails = YES; //never going to find it
    }
}

#pragma mark - theMovieDB
#define kFormatError @"ERROR"
-(NSString *) checkMovie:(NSDictionary *) movie exact: (BOOL) perfectMatch {
    //if perfectmatch, return filename iff same name and same year; else return filename if either are true
    if(![movie isKindOfClass:[NSDictionary class]]) {
        DDLogMajor(@"theMovieDB returned invalid JSON format: Movie is not a dictionary : %@", movie);
        return kFormatError;
    }
    NSString * movieTitle = movie[@"title"];
    if (!([movieTitle isKindOfClass:[NSString class]])) {
        DDLogMajor(@"For %@, theMovieDB returned a movie that doesn't have a title : %@", self.seriesTitle, movie);
        return kFormatError;
    }
    BOOL titlesMatch = [movieTitle isEqualToString:self.seriesTitle];
    BOOL releaseMatch = NO;

    if (perfectMatch || ! titlesMatch) {
        NSString * releaseDate = movie[@"release_date"];
        if (!([releaseDate isKindOfClass:[NSString class]] && releaseDate.length >= 4)) {
            DDLogMajor(@"theMovieDB returned movie %@ without release year; %@? ", movieTitle, self.movieYear);
            releaseMatch = YES;
        } else {
            NSString * releaseYear = [releaseDate substringToIndex:4];
            releaseMatch = [releaseYear isEqualToString:self.movieYear];
        }

    }
    if ((perfectMatch && titlesMatch && releaseMatch) ||
        (!perfectMatch && (titlesMatch || releaseMatch))) {
        NSString * artwork = movie[@"poster_path"];
        if (!([artwork isKindOfClass:[NSString class]])) {
            DDLogMajor(@"theMovieDB returned invalid JSON format: poster_path is invalid : %@", movie);
            return kFormatError;
        }
        return artwork;
    } else {
        return nil;
    }
}

-(void) getTheMovieDBDetails {
    if (self.gotTVDBDetails) return;

    //we only get artwork
    NSString * urlString = [[NSString stringWithFormat:@"https://api.themoviedb.org/3/search/movie?query=\"%@\"&api_key=%@",self.seriesTitle, kMTTheMoviedDBAPIKey] stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    NSString * reportURL = [urlString stringByReplacingOccurrencesOfString:kMTTheMoviedDBAPIKey withString:@"APIKEY" ];
    DDLogDetail(@"Getting movie Data for %@ using %@",self,reportURL);
    NSURL *url = [NSURL URLWithString:urlString];
    NSData *movieInfo = [NSData dataWithContentsOfURL:url options:NSDataReadingUncached error:nil];
    if (!movieInfo) return;
    self.gotTVDBDetails = YES;

    NSError *error = nil;
    NSDictionary *topLevel = [NSJSONSerialization
                 JSONObjectWithData:movieInfo
                 options:0
                 error:&error];

    if (!topLevel || error) {
        DDLogMajor(@"theMovieDB returned invalid JSON format: %@ Data: %@",error.localizedDescription, movieInfo);
        return;
    }
    if(![topLevel isKindOfClass:[NSDictionary class]]) {
        DDLogMajor(@"theMovieDB returned invalid JSON format:Top Level is not a dictionary; Data: %@", movieInfo);
        return;
    }
     NSArray * results = topLevel[@"results"];
     if(![results isKindOfClass:[NSArray class]]) {
         DDLogMajor(@"theMovieDB returned invalid JSON format: Results not an array; Data: %@", movieInfo);
         return;
     }
     if (results.count == 0) {
         DDLogMajor(@"theMovieDB couldn't find any movies named %@", self.seriesTitle);
         return;
     }
    NSString * newArtwork = nil;
    for (NSDictionary * movie in results) {
        //look for a perfect title/release match
        NSString * location = [self checkMovie:movie exact:YES];
        if (location) {
            if (![location isEqualToString:kFormatError]) {
                newArtwork = location;
            }
            break;
        }
    }
    if (!newArtwork) {
        for (NSDictionary * movie in results) {
           // return first that matches either title or release year
            NSString * location = [self checkMovie:movie exact:NO];
            if (location) {
                if (![location isEqualToString:kFormatError]) {
                    newArtwork = location;
                }
                break;
            }
        }
   }
    if (newArtwork.length > 0 ) {
        self.tvdbArtworkLocation = newArtwork;
        if ( self.seriesId.length > 0) {  //protective only
            @synchronized (tiVoManager.tvdbCache) {
                [tiVoManager.tvdbCache setObject:@{
                                                   @"artwork":newArtwork,
                                                   @"date":[NSDate date]
                                                   } forKey:self.seriesId];
            }
        }
    } else {

    }
}


-(void)retrieveArtworkIntoFile: (NSString *) filename
{
     if(!self.gotTVDBDetails && self.isMovie) {
        //we don't get movie data upfront, so go get it now, but call us back when you have it
        __weak typeof(self) weakSelf = self;
        dispatch_async(dispatch_get_global_queue( DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(void){
            [weakSelf getTheMovieDBDetails];
            dispatch_async(dispatch_get_main_queue(), ^(void){
                [weakSelf retrieveArtworkIntoFile:filename];
            });
        });
         return;

	}
	if (_tvdbArtworkLocation.length == 0) {
		return;
	}
    NSString * fileNameDetail;
    NSString *baseUrlString;
    if (self.isMovie) {
        fileNameDetail = [self movieYear];
         baseUrlString = @"http://image.tmdb.org/t/p/w780%@";
    } else {
        fileNameDetail = [self seasonEpisode];
        baseUrlString = @"http://thetvdb.com/banners/%@";
    }
    NSString * destination;
    if (fileNameDetail.length) {
        destination = [NSString stringWithFormat:@"%@_%@",filename, fileNameDetail];
    } else {
        destination = filename;
    }

    NSString *urlString = [[NSString stringWithFormat: baseUrlString, self.tvdbArtworkLocation ]
           stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];

    NSString * path = [destination stringByDeletingLastPathComponent];
    NSString * base = [destination lastPathComponent];
    NSString * extension = [self.tvdbArtworkLocation pathExtension];

    base = [base stringByReplacingOccurrencesOfString:@"/" withString:@"-"];
    base = [base stringByReplacingOccurrencesOfString:@":" withString:@"-"] ;

    NSString * realDestination = [[path stringByAppendingPathComponent:base] stringByAppendingPathExtension:extension];

    //download only if we don't have it already
    if (![[NSFileManager defaultManager] fileExistsAtPath:realDestination]) {
        DDLogDetail(@"downloading artwork at %@ to %@",urlString, realDestination);
        NSURLRequest *req = [NSURLRequest requestWithURL:[NSURL URLWithString:urlString]];
        [NSURLConnection sendAsynchronousRequest:req queue:[NSOperationQueue mainQueue] completionHandler:^(NSURLResponse *response, NSData *data, NSError *error) {
            if (!data || error) {
                DDLogMajor(@"Couldn't get artwork for %@ from %@ , Error: %@", self.seriesTitle, urlString, error.localizedDescription);
            } else {
                if ([data writeToFile:realDestination atomically:YES]) {
                    self.artworkFile = realDestination;
                    DDLogDetail(@"Saved artwork file for %@ at %@",self.showTitle, realDestination);
                } else {
                    DDLogReport(@"Couldn't write to artwork file %@", realDestination);
                }
            }
        }];
    }
}

static NSMutableDictionary <NSString *, NSRegularExpression *> * cacheRegexes;


-(NSString *)getStringForPattern:(NSString *)pattern fromString:(NSString *)string
{
    NSString *answer = nil;

    //next few lines are just perfomance optimization to avoid recreating regexes.
    static dispatch_once_t onceToken = 0;
    dispatch_once(&onceToken, ^{
        cacheRegexes = [[NSMutableDictionary alloc] init];
    });

    NSRegularExpression * regex = nil;
    @synchronized (cacheRegexes) {
        regex = cacheRegexes[pattern];
       if (!regex) {
           NSError *error = nil;
           regex = [NSRegularExpression regularExpressionWithPattern:pattern options:NSRegularExpressionCaseInsensitive error:&error];
           if (error || ! regex) {
               DDLogReport(@"GetStringFormPattern error %@",error.userInfo);
               return nil;
           }
           [cacheRegexes setValue:regex forKey:pattern];
       }
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
	if ([type isEqualToString:kMTTivoShowPasteBoardType]) {
		return  [NSKeyedArchiver archivedDataWithRootObject:self];
    } else if ( [type isEqualToString:(NSString *)kUTTypeFileURL]) {
        NSArray * files = [tiVoManager.showsOnDisk objectForKey:self.showKey];
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
    if ([tiVoManager.showsOnDisk objectForKey:self.showKey]) {
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


-(void)getShowDetail {
    //run on background queue to only allow a couple at a time running, so must be threadsafe
    //self.tivo, self.detailURL, and self.showID are read, but set long ago.

    @synchronized(self) {
        if (_gotDetails) {
            return;
        }
        _gotDetails = YES;
    }
    NSAssert(![NSThread isMainThread],@"getShowDetail NOT on background");
    NSString *detailFilePath = [NSString stringWithFormat:@"%@/%@_%d_Details.xml",kMTTmpDetailsDir,self.tiVo.tiVo.name,self.showID]; //keep in sync with parseDetails
    NSData *xml = nil;
    NSFileManager * fileMgr = [NSFileManager defaultManager];
    if ([fileMgr fileExistsAtPath:detailFilePath]) {
        DDLogDetail(@"getting details for %@ from file %@", self, detailFilePath);
        xml = [NSData dataWithContentsOfFile:detailFilePath];
        //use fileModDate to know when to delete old detail files
       NSMutableDictionary *attr = [NSMutableDictionary dictionaryWithDictionary:
                                     [fileMgr attributesOfItemAtPath:detailFilePath error:nil]];
        [attr setObject:[NSDate date] forKey:NSFileModificationDate];
        [fileMgr setAttributes:attr ofItemAtPath:detailFilePath error:nil];
    } else {
        DDLogDetail(@"downloading %@ details from path %@", self, self.detailURL);
        NSURLResponse *detailResponse = nil;
        NSURLRequest *detailRequest = [NSURLRequest requestWithURL:_detailURL];;
        xml = [NSURLConnection sendSynchronousRequest:detailRequest returningResponse:&detailResponse error:nil];
        if (![_inProgress boolValue]) {
            [xml writeToFile:detailFilePath atomically:YES];
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
    if (!_gotDetails) {
        //Tivo sometimes puts "&&amp" for "&amp"; if so, fix it and try again

        NSString *detailFilePath = [NSString stringWithFormat:@"%@/%@_%d_Details.xml",kMTTmpDetailsDir,self.tiVo.tiVo.name,self.showID]; //keep in sync with getShowDetail
        NSString *xmlString =  [[NSString alloc] initWithData:xml encoding:NSUTF8StringEncoding	];
        if (firstTime && [xmlString contains:@"&&amp"]) {
            _gotDetails = YES;
            DDLogMajor(@"Fixing TiVo &&amp bug for %@",_showTitle);
            xmlString = [xmlString stringByReplacingOccurrencesOfString:@"&&amp" withString:@"&amp"];
            NSData * revisedXML = [xmlString dataUsingEncoding:NSUTF8StringEncoding];
            [revisedXML writeToFile:detailFilePath atomically:YES];
            [self parseDetails:revisedXML firstTime:NO];

        } else {
            DDLogMajor(@"GetDetails %@fails for %@", firstTime? @"":@"really ",_showTitle);
            DDLogMajor(@"Returned XML is %@",xmlString);
            NSFileManager * fileMgr = [NSFileManager defaultManager];
            if ([fileMgr fileExistsAtPath:detailFilePath]) {
                //cached version is not usable
                DDLogDetail(@"deleting file %@ for show %@", detailFilePath, self);
                [fileMgr removeItemAtPath:detailFilePath error:nil];
            }
        }

    } else {
        if (!self.isMovie) { //no need for movie info, just artwork when we download.
            [self getTheTVDBDetails];
        }
        DDLogDetail(@"GetDetails parsing Finished: %@", self.showTitle);
    }
    [NSNotificationCenter postNotificationNameOnMainThread:kMTNotificationDetailsLoaded object:self ];

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
	_gotDetails = NO;
    DDLogMajor(@"Show: %@ Parser Error %@",self.showTitle, parseError);

}

#pragma mark - Custom Getters

-(NSString *)showKey
{
	return [NSString stringWithFormat:@"%@: %@",self.tiVoName,self.idString];
}
												  
-(NSString *) seasonEpisode {
    if ([self.episodeID hasPrefix:@"SH" ]) return @"";  //non-episodic shows don't have episodes
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
	BOOL value =  ([self.episodeID hasPrefix:@"MV"]) ;
	return value;
}

-(NSAttributedString *)attrStringFromDictionaries:(id)nameList
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
		attstring = [[NSAttributedString alloc] initWithString:self.showDescription attributes:@{NSFontAttributeName : [NSFont systemFontOfSize:11]}];
	}
	return attstring;
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
        if (![self.programId hasPrefix: @"SH"]) {
            //else it's 'non-episodic" show, so no seasons or episodes.
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
	}
	if (self.episodeID.length >0) {
		MP4TagsSetTVEpisodeID(tags, [self.episodeID cStringUsingEncoding:NSUTF8StringEncoding]);
		if ([[NSUserDefaults standardUserDefaults] boolForKey:kMTiTunesContentIDExperiment ] & (self.episodeID.length >2)) {
			NSRange digitPart = NSMakeRange(2, self.episodeID.length-2);
			NSUInteger bigDigits = [[self.episodeID substringWithRange:digitPart] integerValue];
			uint32 digits = (uint32)(bigDigits & ULONG_MAX); //modulo to wrap around over 4G
			DDLogDetail(@"ContentID: %lu => %u", bigDigits, digits);
			MP4TagsSetContentID(tags, &digits);
		}
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
    //sample call code: add to MainWindowController programMenuHandler
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

    NSString *detailFilePath = [NSString stringWithFormat:@"%@/%@_%d_Details.xml",kMTTmpDetailsDir,self.tiVo.tiVo.name,self.showID];

    NSData * xml = [NSData dataWithContentsOfFile:detailFilePath];
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
    return [tiVoManager.showsOnDisk objectForKey:self.showKey] != nil;
}

-(NSString *) isOnDiskString {
    return [self checkString: self.isOnDisk];
}

-(NSString *) h264String {
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

#pragma mark - Custom Setters; many for parsing

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
            long l = _episodeNumber.length;
            if (l > 2 && l < 6) {
                //3,4,5 ok: 3 = SEE 4= SSEE 5 = SSEEE
                //4 might be corrected by tvdb to SEEE
                int epDigits = (l > 4) ? 3:2;
                _episode = [[_episodeNumber substringFromIndex:l-epDigits] intValue];
                _season = [[_episodeNumber substringToIndex:l-epDigits] intValue];
            } else {
                _episode = [_episodeNumber intValue];
            }
        }
    } else if (context == movieYearContext) {
        if (self.originalAirDateNoTime.length == 0) {
            _originalAirDateNoTime = self.movieYear;
        }
    } else if (context == originalAirDateContext) {

        if ([self.episodeID hasPrefix:@"SH"] && self.showDate) {
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

-(void)setVActor:(NSArray *)vActor
{
	if ( ![vActor isKindOfClass:[NSArray class]]) {
		return;
	}
    self.actors = [self parseNames: vActor ]  ;
}

-(void)setVGuestStar:(NSArray *)vGuestStar
{
	if ( ![vGuestStar isKindOfClass:[NSArray class]]) {
		return;
	}
	self.guestStars = [self parseNames: vGuestStar ];
}

-(void)setVDirector:(NSArray *)vDirector
{
	if ( ![vDirector isKindOfClass:[NSArray class]]) {
		return;
	}
	self.directors = [self parseNames: vDirector ];
}

-(void)setVWriter:(NSArray*) vWriter
{
    if ( ![vWriter isKindOfClass:[NSArray class]]) {
        return;
    }
    self.writers = [self parseNames: vWriter ];
}

-(NSAttributedString *) appendNames: (NSArray *) names to: (NSAttributedString *) stringA {
    NSAttributedString * temp = [self parseNames:names];

    if (stringA.string.length == 0) {
        return temp;
    } else {
        return [[NSAttributedString alloc] initWithString:[NSString stringWithFormat: @"%@\n%@",stringA.string, temp.string]
                                               attributes:@{NSFontAttributeName : [NSFont systemFontOfSize:11]} ]
                ;
    }

}

-(void)setVExecProducer:(NSArray *)vExecProducer   //we just merge producers and exec producers together
{
    if ( ![vExecProducer isKindOfClass:[NSArray class]]) {
        return;
    }
    self.producers = [self appendNames:vExecProducer to:self.producers];
}

-(void)setVProducer:(NSArray *)vProducer
{
    if ( ![vProducer isKindOfClass:[NSArray class]]) {
        return;
    }
    self.producers = [self appendNames:vProducer to:self.producers];

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
    return [NSString stringWithFormat:@"%@ (%@)%@",_showTitle,self.tiVoName,[_protectedShow boolValue]?@"-Protected":@""];
}


@end

