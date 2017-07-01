//
//  MTTVDBManager.m
//  cTiVo
//
//  Created by Hugh Mackworth on 6/30/17.
//  Copyright © 2017 cTiVo. All rights reserved.
//
#import "MTTVDB.h"
#import "MTTiVoShow.h"

#import "NSString+Helpers.h"
#import "DDLog.h"
#import "NSString+HTML.h"

@interface MTTVDB ()
    @property (nonatomic, strong) NSOperationQueue * tvdbQueue;
    @property (atomic, strong) NSString * tvdbToken;
    @property (nonatomic, strong) NSDate * tvdbTokenExpireTime;
    @property (nonatomic, strong) NSURLSession * tvdbURLSession;
    @property (nonatomic, strong) NSURLSessionConfiguration * tvdbURLConfiguration;

    @property (atomic, strong) NSMutableDictionary <NSString *, NSArray <NSString *> *> *tvdbSeriesIdMapping;
    @property (atomic, strong) NSMutableDictionary *tvdbCache;
    @property (atomic, strong) NSMutableDictionary * theTVDBStatistics;

@end

@implementation MTTVDB

__DDLOGHERE__

#pragma mark - TVDB

+ (MTTVDB *)sharedManager {
    static dispatch_once_t pred;
    static MTTVDB *myManager = nil;
    dispatch_once(&pred, ^{
        myManager = [[self alloc] init];
    });
    return myManager;
}

-(void) saveDefaults {
    @synchronized(self.tvdbCache) {
        NSUserDefaults * defaults = [NSUserDefaults standardUserDefaults];
        [defaults setObject:self.tvdbCache forKey:kMTTheTVDBCache];

        if ([self.tvdbTokenExpireTime compare:[NSDate distantPast]] == NSOrderedAscending ) {
            [[NSUserDefaults standardUserDefaults] setObject:self.tvdbTokenExpireTime forKey:kMTTVDBTokenExpire];
            [[NSUserDefaults standardUserDefaults] setObject:self.tvdbToken forKey:kMTTVDBToken];
        }
    }
}

-(instancetype) init {
    if ((self = [super init])) {
        self.tvdbTokenExpireTime =  [[NSUserDefaults standardUserDefaults] objectForKey: kMTTVDBTokenExpire ] ?: [NSDate distantPast];
        self.tvdbToken = [[NSUserDefaults standardUserDefaults] objectForKey: kMTTVDBToken ];

        self.tvdbSeriesIdMapping = [NSMutableDictionary dictionary];
        self.tvdbCache = [NSMutableDictionary dictionaryWithDictionary:[[NSUserDefaults standardUserDefaults] objectForKey:kMTTheTVDBCache]];
        self.theTVDBStatistics = [NSMutableDictionary dictionary];
        self.tvdbQueue = [[NSOperationQueue alloc] init];
        self.tvdbQueue.maxConcurrentOperationCount = kMTMaxTVDBRate;

        //Clean up old entries
        NSMutableArray *keysToDelete = [NSMutableArray array];
        for (NSString *key in _tvdbCache) {
            NSDate *d = [[_tvdbCache objectForKey:key] objectForKey:@"date"];
            if ([[NSDate date] timeIntervalSinceDate:d] > 60.0 * 60.0 * 24.0 * 30.0) { //Too old so throw out
                [keysToDelete addObject:key];
            }
        }
        for (NSString *key in keysToDelete) {
            [_tvdbCache removeObjectForKey:key];
        }
    }
    return self;
}

-(void) resetAll {
    //Remove TVDB Cache
    [[NSUserDefaults standardUserDefaults] setObject:@{} forKey:kMTTheTVDBCache];
    self.tvdbCache =  [NSMutableDictionary dictionary];
    self.tvdbSeriesIdMapping = [NSMutableDictionary dictionary];
    @synchronized(self.theTVDBStatistics) {
        self.theTVDBStatistics = [NSMutableDictionary dictionary];
    }

}
-(NSURLSession *) tvdbURLSession {
    if (!_tvdbURLSession) {
        while (![self checkToken] ) sleep(0.1);   //this is WRONG!!!!!!!!!!!  FIX XXXXX
        if (self.tvdbToken) {
            NSURLSessionConfiguration * config = [NSURLSessionConfiguration defaultSessionConfiguration];
            config.HTTPAdditionalHeaders = @{@"Accept": @"application/json",
                                             @"Content-Type": @"application/json",
                                             @"Authorization": [NSString stringWithFormat:@"Bearer %@",self.tvdbToken]};
            _tvdbURLSession = [NSURLSession sessionWithConfiguration:config];
        }
    }
    return _tvdbURLSession;
}

-(BOOL) checkToken {
    @synchronized (self.tvdbTokenExpireTime) {
        if (self.tvdbToken && [self.tvdbTokenExpireTime compare:[NSDate date]] == NSOrderedDescending) {
            return YES;
        } else {
            //don't have a token or it's expired
            self.tvdbToken = nil;
            self.tvdbURLConfiguration = nil;

            NSURLSessionConfiguration *sessionConfiguration = [NSURLSessionConfiguration defaultSessionConfiguration];
            sessionConfiguration.HTTPAdditionalHeaders = @{@"Accept": @"application/json"};
            sessionConfiguration.HTTPAdditionalHeaders = @{@"Content-Type": @"application/json"};

            NSURLSession *session = [NSURLSession sessionWithConfiguration:sessionConfiguration];

            NSString *tokenURL = @"https://api.thetvdb.com/login";
            NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:tokenURL]];
            request.HTTPMethod = @"POST";
            NSString * body = @"{"
            "\"apikey\": \"" kMTTheTVDBAPIKey "\","
            "\"userkey\": \"\","
            "\"username\": \"\""
            "}";
            request.HTTPBody = [body dataUsingEncoding:NSUTF8StringEncoding];
            NSDate * tokenExpiration = [NSDate dateWithTimeIntervalSinceNow:24*60*60];
            NSURLSessionDataTask *task = [session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
                if (!error) {
                    NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
                    if (httpResponse.statusCode == 200){
                        NSError * jsonError;
                        NSDictionary *jsonData = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers|NSJSONReadingAllowFragments error: &jsonError];
                        if (!jsonError) {
                            NSLog(@"TVDB Token JSON: %@", jsonData);
                            NSString * token = jsonData[@"token"];
                            if (token.length) {
                                self.tvdbToken = token;
                                self.tvdbTokenExpireTime = tokenExpiration;
                                self.tvdbURLConfiguration = nil; //regenerate w/ new token;
                            }
                        } else {
                            DDLogReport(@"TVDB Token JSON parsing Error: %@", data);
                        }
                    } else {
                        DDLogReport(@"TVDB Token HTTP Response Error %ld: %@, %@", (long)httpResponse.statusCode, data, response );
                    }
                }

            }];
            [task resume];
            return NO; //no token available right now
        }
    }
}

-(void) seriesIDForShow:(NSString *) series completionHandler: (void(^) (NSString *series))completionBlock {
    NSString *tokenURL = [[NSString stringWithFormat:@"search/series?name=%@",series] stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:tokenURL]];
    NSURLSessionDataTask *task = [self.tvdbURLSession dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (!error) {
            NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
            if (httpResponse.statusCode == 200){
                NSError * jsonError;
                NSDictionary *jsonData = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers|NSJSONReadingAllowFragments error: &jsonError];
                if (!jsonError) {
                    NSLog(@"TVDB Series JSON: %@", jsonData);
                    NSString * seriesID = jsonData[@"data"][@"id"];
                    if (completionBlock) completionBlock(seriesID);
                } else {
                    DDLogReport(@"TVDB Series JSON parsing Error: %@", data);
                }
            } else {
                DDLogReport(@"TVDB Series HTTP Response Error %ld: %@, %@", (long)httpResponse.statusCode, data, response );
            }
        }
        
    }];
    [task resume];
    
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


-(NSString *) seriesIDForReporting: (NSString *) seriesId {
    NSString *epID = nil;
    if (seriesId.length > 1) {
        epID = [seriesId  substringFromIndex:2];
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

-(NSArray <NSString *> *) retrieveTVDBIdFromSeriesName: (NSString *) name withTiVoID: (NSString *) tivoID {
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
                NSString * details = [NSString stringWithFormat:@"tvdb has %@ for our %@; %@ ", zap2ID, [self seriesIDForReporting:tivoID],[self urlsForReporting:@[tvdbID] ]];
                DDLogVerbose(@"Had to search by name %@, %@",name, details);
                [self addValue:details inStatistic:kMTVDBSeriesFoundName forShow:name];
                if (![tvdbIDs containsObject:tvdbID]){
                    [tvdbIDs addObject:tvdbID];
                }
            }
        }
    }
    if (tvdbIDs.count == 0) {
    } else {

        DDLogDetail(@"Mapped %@ series to %@", name, [[tvdbIDs allObjects] componentsJoinedByString:@" OR "]);
    }
    return [tvdbIDs allObjects];

}

-(void) incrementStatistic: (NSString *) statistic {
    @synchronized(self.theTVDBStatistics) {
        self.theTVDBStatistics[statistic] = @([self.theTVDBStatistics[statistic] intValue] + 1);
    }
}

-(void) addValue:(NSString *) value inStatistic:(NSString *) statistic forShow:(NSString *) show {
    @synchronized(self.theTVDBStatistics) {
        NSString * statisticListName = [statistic stringByAppendingString:@" List"];
        NSMutableDictionary * statisticList = self.theTVDBStatistics[statisticListName]; //shorthand
        if (!statisticList) {
            statisticList = [NSMutableDictionary dictionary];
            [self.theTVDBStatistics setObject:statisticList forKey:statisticListName];
        }
        if (!statisticList[show]) {
            [statisticList setValue: value forKey: show];
            NSString * statisticCount = [statistic stringByAppendingString:@" Count"];
            self.theTVDBStatistics[statisticCount] = @([self.theTVDBStatistics[statisticCount] intValue] + 1);
        }
        [statisticList setValue: value forKey: show]; //keep latest version in case it changed

    }
}

-(void) rememberArtWork: (NSString *) newArtwork forSeries: (NSString *) seriesId {
    if ( seriesId.length > 0) {  //protective only
        @synchronized (self.tvdbCache) {
            [self.tvdbCache setObject:@{
                                   @"artwork":newArtwork,
                                   @"date":[NSDate date]
                                   }
                               forKey:seriesId];
        }
    }
}

-(void) rememberTVDBSeriesID: (NSArray *) seriesIDs forSeries: (NSString *) seriesTitle{
    if (seriesIDs.count) {
        @synchronized (self.tvdbSeriesIdMapping) {
            [self.tvdbSeriesIdMapping setObject:[NSArray arrayWithArray: seriesIDs] forKey:seriesTitle];
        }
    }
}

-(NSArray <NSString *> *) checkTVDBSeriesID:(NSString *) title {
    @synchronized (self.tvdbSeriesIdMapping) {
        return  [self.tvdbSeriesIdMapping objectForKey:title];
    }
}

-(void) retrieveTVDBEpisodeInfoForShow: (MTTiVoShow *) show {
    //Now get the details
    @autoreleasepool {
        NSArray *seriesIDTVDBs = [self checkTVDBSeriesID:show.seriesTitle ];
        NSAssert (![NSThread isMainThread], @"retrieveTVDBEpisodeInfo not running in background");
        NSString * reportURL = nil;

        for (NSString * seriesIDTVDB in seriesIDTVDBs) {

            NSString *urlString = [[NSString stringWithFormat:@"http://thetvdb.com/api/GetEpisodeByAirDate.php?apikey=%@&seriesid=%@&airdate=%@",kMTTheTVDBAPIKey,seriesIDTVDB,show.originalAirDateNoTime] stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
            reportURL = [urlString stringByReplacingOccurrencesOfString:kMTTheTVDBAPIKey withString:@"APIKEY" ];
            DDLogDetail (@"launching %@ for %@", reportURL, show.showTitle);
            NSURL *url = [NSURL URLWithString:urlString];
            NSError * error = nil;
            NSString * episodeInfo = [NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:&error];

            if (error) {
                DDLogMajor(@"Failed to get info from TVDB for %@ at %@: %@",show.showTitle, reportURL, error.localizedDescription);
            } else if (!episodeInfo.length) {
                DDLogMajor(@"No error from TVDB for %@ at %@, but no content",show.showTitle, reportURL);
            } else {
                NSString * errorMsg = [self getStringForPattern:@"<Error>(.*)<\\/Error>" fromString:episodeInfo];
                if (errorMsg.length > 0) {
                    DDLogDetail(@"TVDB Error for %@(%@) aired %@ at %@ : %@ ",show.showTitle,[self seriesIDForReporting: show.seriesId], show.originalAirDateNoTime, reportURL, errorMsg );
                } else {
                    NSString * newEpisodeNum = [self getStringForPattern:@"<Combined_episodenumber>(\\d*)" fromString:episodeInfo] ?: @"";
                    NSString * newSeasonNum = [self getStringForPattern:@"<Combined_season>(\\d*)" fromString:episodeInfo] ?: @"";
                    NSString * newArtwork = [self getStringForPattern:@"<filename>(.*)<\\/filename>" fromString:episodeInfo] ?: @"";
                    if (newEpisodeNum.length + newSeasonNum.length + newArtwork.length == 0) {
                        //TVDB gateway gives error code in HTML so this hack parses
                        NSString * gatewayErrorNum = [self getStringForPattern:@"<span class=\"cf-error-code\">(\\d*)</span>" fromString:episodeInfo] ?: @"";
                        NSString * gatewayError = [self getStringForPattern:@"<h2 class=\"cf-subheadline\" data-translate=\"error_desc\">(.*)</h2>" fromString:episodeInfo] ?: @"";
                        if (gatewayErrorNum.length + gatewayError.length > 0) {
                            DDLogMajor(@"TVDB server %@ problem for %@ at %@: %@",gatewayErrorNum, show.showTitle, reportURL, gatewayError);
                        } else {
                            DDLogMajor(@"TVDB server failure; no error msg for %@ at %@", show.showTitle, reportURL);
                        }
                    } else {
                        if (![seriesIDTVDBs[0] isEqualToString:seriesIDTVDB]) {
                            DDLogDetail(@"Found theTVDB on second+ try for %@", show.showTitle);
                            //move to first position for other episodes
                            NSMutableArray <NSString *> * newSeriesIDTVBs = [NSMutableArray arrayWithArray:seriesIDTVDBs];
                            [newSeriesIDTVBs removeObject:seriesIDTVDB];
                            [newSeriesIDTVBs insertObject:seriesIDTVDB atIndex:0];
                            [self rememberTVDBSeriesID:newSeriesIDTVBs forSeries:show.showTitle];
                        }
                        @synchronized (self.tvdbCache) {
                            [self.tvdbCache setObject:@{
                                                               @"season":newSeasonNum,
                                                               @"episode":newEpisodeNum,
                                                               @"artwork":newArtwork,
                                                               @"series": seriesIDTVDB,
                                                               @"date":[NSDate date]
                                                               } forKey:show.episodeID];
                        }
                        show.gotTVDBDetails = YES;
                        dispatch_async(dispatch_get_main_queue(), ^{
                            [self finishTVDBProcessing:show ];
                        });
                        DDLogDetail (@"Got episode Info for %@: %@ ops",  show.showTitle, @(self.tvdbQueue.operationCount));
                    }
                }
            }
        }
        //So, an episode not found case, let's report but also try series lookup for artwork
        if (seriesIDTVDBs.count > 1) {
            DDLogDetail(@"Did not find TVDB on second+ try for %@", show.showTitle);
        }

        NSString * details = [NSString stringWithFormat:@"%@ aired %@ (our  %d/%d) at %@ ",[self seriesIDForReporting:show.seriesId ], show.originalAirDateNoTime, show.season, show.episode, reportURL ];
        DDLogDetail(@"No episode info for %@ (%@) %@ ",show.showTitle, [seriesIDTVDBs componentsJoinedByString:@"OR"], details );
        [self addValue:details inStatistic:kMTVDBNoEpisode forShow:show.showTitle];

        BOOL gotsOne;
        @synchronized (self.tvdbCache) {
            gotsOne = ( self.tvdbCache [show.seriesId][@"artwork"]) !=nil;
        }
        if (gotsOne) {
            show.gotTVDBDetails = YES;
            dispatch_async(dispatch_get_main_queue(), ^{
                [self finishTVDBProcessing: show];
            });
        } else {
            [self retrieveTVDBSeriesInfoForShow:show ];
        }

        //    NSTimeInterval time = 1.0/kMTMaxTVDBRate + [date timeIntervalSinceNow];
        //    if (time > 0) [NSThread sleepForTimeInterval:time];
        //ensures our operation stays officially running, so not hammering the TVDB API
    }
}

-(void) retrieveTVDBSeriesInfoForShow: (MTTiVoShow *) show{
    //for non-episodic series, get the artwork info
    @autoreleasepool {
        NSArray *seriesIDTVDBs = [self checkTVDBSeriesID:show.seriesTitle ];
       if (seriesIDTVDBs.count ==0) return;
        NSString * seriesIDTVDB = seriesIDTVDBs[0];
        NSAssert (![NSThread isMainThread], @"retrieveTVDBESeriesInfo not running in background");
        //      <mirrorpath>/api/GetSeries.php?seriesname=<seriesname> <mirrorpath>/api/GetSeries.php?seriesname=<seriesname>&language=<language>
        NSString *urlString = [NSString stringWithFormat:@"http://thetvdb.com/api/%@/series/%@/banners.xml",kMTTheTVDBAPIKey,seriesIDTVDB];
        NSString * reportURL = [urlString stringByReplacingOccurrencesOfString:kMTTheTVDBAPIKey withString:@"APIKEY" ];
        DDLogDetail (@"launching %@ for %@", reportURL, show.showTitle);
        NSURL *url = [NSURL URLWithString:urlString];
        NSError * error = nil;
        NSString * episodeInfo = [NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:&error];

        if (error) {
            DDLogMajor(@"Failed to get series info from TVDB for %@ at %@: %@",show.showTitle, reportURL, error.localizedDescription);
        } else if (!episodeInfo.length) {
            DDLogMajor(@"No error from TVDB for series %@ at %@, but no content",show.showTitle, reportURL);
        } else {
            show.gotTVDBDetails = YES;
            NSString * newArtwork = [self getStringForPattern:@"<BannerPath>(.*)</BannerPath>" fromString:episodeInfo] ?: @"";
            if (newArtwork.length > 0) {
                @synchronized (self.tvdbCache) {
                    [self.tvdbCache setObject:@{
                                                       @"artwork":newArtwork,
                                                       @"series": seriesIDTVDB,
                                                       @"date":[NSDate date]
                                                       } forKey:show.seriesId];
                }
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self finishTVDBProcessing: show];
                });
            }

        }
        //    NSTimeInterval time = 1.0/kMTMaxTVDBRate + [date timeIntervalSinceNow];
        //    if (time > 0) [NSThread sleepForTimeInterval:time];
        //ensures our operation stays officially running, so not hammering the TVDB API
        DDLogDetail (@"Got series Info for %@: %@ ops",  show.showTitle, @(self.tvdbQueue.operationCount));
    }
}

-(void) retrieveTVDBSeriesIDForShow: (MTTiVoShow *) show {
    @autoreleasepool {
        NSAssert (![NSThread isMainThread], @"getTVDBSeriesID not running in background");

        NSArray <NSString *> * mySeriesIDTVDB = [self retrieveTVDBIdFromSeriesName:show.seriesTitle withTiVoID:show.seriesId ] ;
        //Don't give up yet; look for "Series: subseries" format
        if (!mySeriesIDTVDB.count)  {
            NSArray * splitName = [show.seriesTitle componentsSeparatedByString:@":"];
            if (splitName.count > 1) {
                mySeriesIDTVDB = [self retrieveTVDBIdFromSeriesName:splitName[0] withTiVoID:show.seriesId];
            }
        }

        if (mySeriesIDTVDB.count) {
            DDLogDetail(@"Got TVDB for %@: %@ ",self, [mySeriesIDTVDB componentsJoinedByString:@" OR "]);
            [self rememberTVDBSeriesID:mySeriesIDTVDB forSeries:show.seriesTitle];
            if ([show.episodeID hasPrefix:@"SH"]){
                [self retrieveTVDBSeriesInfoForShow:show];
            } else {
                [self retrieveTVDBEpisodeInfoForShow:show];
            }
        } else {
            [self rememberTVDBSeriesID: @[ ] forSeries:show.seriesTitle];
            DDLogDetail(@"TheTVDB series not found: %@: %@ ",show.seriesTitle, show.seriesId);
            [self addValue: show.seriesId   inStatistic: kMTVDBNoSeries forShow:show.seriesTitle];
            show.gotTVDBDetails = YES;
            return; //really can't get them.
        }

    }
}

-(void)getTheTVDBDetails: (MTTiVoShow *) show {
    //Called from main thread
    //Needs to get episode info from TVDB
    //1) do possibly multiple lookups at TheTVDB in background to find TVDB's seriesID
    //2) call retrieveTVDBEpisodeInfo in background to get Episode Info
    //3) call finishTVDBProcessing on main thread to augment TiVo's info with theTVDB
    if (show.gotTVDBDetails) {
        return;
    }
    if (show.seriesId.length && [show.seriesId hasPrefix:@"SH"]) { //if we have a series get the other information
        NSDictionary *episodeEntry;
        @synchronized (self.tvdbCache) {
            if ([show.episodeID hasPrefix:@"SH"]) {
                episodeEntry = [self.tvdbCache objectForKey:show.seriesId];
            } else {
                episodeEntry = [self.tvdbCache objectForKey:show.episodeID];
            }
        }
        DDLogDetail(@"%@ %@",episodeEntry? @"Already had": @"Need to get",show.showTitle);
        if (episodeEntry) { // We already had this information
            show.gotTVDBDetails = YES;
            [self incrementStatistic: ([show.episodeID hasPrefix:@"SH" ] ? kMTVDBSeriesFoundCached : kMTVDBEpisodeCached) ];
            [self finishTVDBProcessing:show];
        } else {
            NSArray *seriesIDTVDBs = [self checkTVDBSeriesID:show.seriesTitle ];
            //Need to pace calls to TVDB API
            SEL whichTVDBMethod;
            if (seriesIDTVDBs.count) {
                // already have series ID, but not this episode info
                if ([show.episodeID hasPrefix:@"SH"]) {
                    whichTVDBMethod = @selector(retrieveTVDBSeriesInfoForShow:);
                    DDLogDetail (@"queuing seriesInfo for %@ (%@): %@ ops", [seriesIDTVDBs componentsJoinedByString:@"OR"], show.showTitle, @(self.tvdbQueue.operationCount));
                } else {
                    whichTVDBMethod = @selector(retrieveTVDBEpisodeInfoForShow:);
                    DDLogDetail (@"queuing episodeInfo for %@ (%@): %@ ops", [seriesIDTVDBs componentsJoinedByString:@"OR"], show.showTitle, @(self.tvdbQueue.operationCount));
                }
            } else {
                //first get seriesID, then Episode Info
                whichTVDBMethod = @selector(retrieveTVDBSeriesIDForShow:);
                DDLogDetail (@"queuing series ID for %@: %@ ops", show.showTitle, @(self.tvdbQueue.operationCount));
            }
            NSInvocationOperation * op = [[NSInvocationOperation alloc] initWithTarget:self selector: whichTVDBMethod object:show ];
            [self.tvdbQueue addOperation:op];
        }
    } else {
        //not a series; no TVDB available
        show.gotTVDBDetails = YES;
    }
}

-(void)  updateSeason: (int) season andEpisode: (int) episode forShow: (MTTiVoShow *) show{
    NSAssert ([NSThread isMainThread], @"updateSeason running in background");
    show.episodeNumber = [NSString stringWithFormat:@"%d%02d",season, episode];
    show.episode = episode;
    show.season = season;
    [[ NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationDetailsLoaded object:show];
}

-(void) finishTVDBProcessing: (MTTiVoShow *) show {
    NSAssert ([NSThread isMainThread], @"finishTVDB running in background");

    NSString *episodeNum = nil, *seasonNum = nil, *artwork = nil;
    NSDictionary *episodeEntry;
    @synchronized (self.tvdbCache) {
        episodeEntry = [self.tvdbCache objectForKey:show.episodeID];
        if (!episodeEntry) episodeEntry = [self.tvdbCache objectForKey:show.seriesId];
    }
    if (!episodeEntry) {
        DDLogReport(@"Trying to process missing TVDB data for %@",show.showTitle);
        return;
    }

    if (episodeEntry) { // We already have this information
        episodeNum = [episodeEntry objectForKey:@"episode"];
        seasonNum = [episodeEntry objectForKey:@"season"];
        artwork = [episodeEntry objectForKey:@"artwork"];
        NSArray *seriesIDTVDBs = [self checkTVDBSeriesID:show.seriesTitle];

        if (!seriesIDTVDBs.count) {
            NSString * seriesIDTVDB = [episodeEntry objectForKey:@"series"];
            if (seriesIDTVDB.length) {
                seriesIDTVDBs = @[seriesIDTVDB];
                [self rememberTVDBSeriesID:seriesIDTVDBs forSeries:show.seriesTitle];
            } else {
                DDLogMajor(@"Missing series info in TVDB data for %@: %@",show.showTitle, episodeEntry);
            }

        }
        show.gotTVDBDetails = YES;
        if (artwork.length+episodeNum.length+seasonNum.length > 0) {
            //got at least one
            [self incrementStatistic:kMTVDBEpisode];
            if (artwork.length) show.tvdbArtworkLocation = artwork;
        } else {
            DDLogDetail(@"QQQ %@", episodeEntry);
            NSString * details = [NSString stringWithFormat:@"%@ aired %@ (our  %d/%d) %@ ",[self seriesIDForReporting:show.seriesId ], show.originalAirDateNoTime, show.season, show.episode, [self urlsForReporting:seriesIDTVDBs] ];
            DDLogDetail(@"No series info for %@ %@ ",show.showTitle, details);
            [self addValue:details inStatistic:kMTVDBNoSeriesInfo forShow:show.showTitle];
        }
        if (episodeNum.length && seasonNum.length && [episodeNum intValue] > 0) {  //season 0 = specials on theTVDB
            DDLogDetail(@"Got episode %@, season %@ and artwork %@ from %@",episodeNum, seasonNum, artwork, show);
            [self incrementStatistic:kMTVDBEpisode];
            //special case due to parsing of tivo's season/episode combined string
            if (show.season > 0 && show.season/10 == [seasonNum intValue]  && [episodeNum intValue] == show.episode + (show.season % 10)*10) {
                //must have mis-parsed (assumed SSEE, but actually SEEE, so let's fix
                NSString * details = [NSString stringWithFormat:@"%@/%@ v our %d/%d aired %@ %@ ",seasonNum, episodeNum, show.season, show.episode, show.originalAirDateNoTime,  [self urlsForReporting:seriesIDTVDBs]];
                DDLogDetail(@"TVDB says we misparsed for %@: %@", show.showTitle, details );
                show.season = [seasonNum intValue];
                show.episode = [episodeNum intValue];
            }
            if (show.episode >0 && show.season > 0) {
                //both sources have sea/epi; so compare for report
                if ([episodeNum intValue] != show.episode || [seasonNum intValue] != show.season) {
                    NSString * details = [NSString stringWithFormat:@"%@/%@ v our %d/%d; %@ aired %@; %@ ",seasonNum, episodeNum, show.season, show.episode, [self seriesIDForReporting:show.seriesId], show.originalAirDateNoTime,  [self urlsForReporting:seriesIDTVDBs]];
                    DDLogDetail(@"TheTVDB has different Sea/Eps info for %@: %@ %@", show.showTitle, details, [[NSUserDefaults standardUserDefaults] boolForKey:kMTTrustTVDB] ? @"updating": @"leaving" );
                    [self addValue: details   inStatistic: kMTVDBWrongInfo forShow:show.showTitle];

                    if ([[NSUserDefaults standardUserDefaults] boolForKey:kMTTrustTVDB]) {
                        //user asked us to prefer TVDB
                        [self updateSeason: [seasonNum intValue] andEpisode: [episodeNum intValue]forShow:show];
                    }
                } else {
                    [self incrementStatistic:kMTVDBRightInfo];
                }
            } else {
                [self updateSeason: [seasonNum intValue] andEpisode: [episodeNum intValue] forShow:show];
                [self incrementStatistic:kMTVDBNewInfo];
                DDLogVerbose(@"Adding TVDB season/episode %d/%d to show %@",show.season, show.episode, show.showTitle);
            }
        }
        
    } else {
        [self incrementStatistic:kMTVDBNoSeries];
        show.gotTVDBDetails = YES; //never going to find it
    }
}

-(NSString *) stats {
    @synchronized(self.theTVDBStatistics) {
        return [self.theTVDBStatistics description];
    }
}

-(BOOL) isActive {
    return self.tvdbQueue.operationCount > 1;
}


-(NSString *) seriesIDsForShow:(MTTiVoShow *)show {
    NSString * seriesIDs = nil;
    @synchronized (self.tvdbSeriesIdMapping) {
        seriesIDs = [[self.tvdbSeriesIdMapping objectForKey:show.seriesTitle] componentsJoinedByString:@" OR "]; // see if we've already done this
    }
    if (!seriesIDs) {
        @synchronized (self.tvdbCache) {
            NSDictionary *TVDBepisodeEntry = [self.tvdbCache objectForKey:show.episodeID];
            //could provide these ,too?
            // NSNumber * TVDBepisodeNum = [TVDBepisodeEntry objectForKey:@"episode"];
            //NSNumber * TVDBseasonNum = [TVDBepisodeEntry objectForKey:@"season"];
            seriesIDs = [TVDBepisodeEntry objectForKey:@"series"];
        };
    }
    return seriesIDs;
}


#pragma mark - theMovieDB
#define kFormatError @"ERROR"
-(NSString *) checkMovie:(NSDictionary *) movie exact: (BOOL) perfectMatch forShow: (MTTiVoShow *) show {
    //if perfectmatch, return filename iff same name and same year; else return filename if either are true
    if(![movie isKindOfClass:[NSDictionary class]]) {
        DDLogMajor(@"theMovieDB returned invalid JSON format: Movie is not a dictionary : %@", movie);
        return kFormatError;
    }
    NSString * movieTitle = movie[@"title"];
    if (!([movieTitle isKindOfClass:[NSString class]])) {
        DDLogMajor(@"For %@, theMovieDB returned a movie that doesn't have a title : %@", show.seriesTitle, movie);
        return kFormatError;
    }
    BOOL titlesMatch = [movieTitle isEqualToString:show.seriesTitle];
    BOOL releaseMatch = NO;

    if (perfectMatch || ! titlesMatch) {
        NSString * releaseDate = movie[@"release_date"];
        if (!([releaseDate isKindOfClass:[NSString class]] && releaseDate.length >= 4)) {
            DDLogMajor(@"theMovieDB returned movie %@ without release year; %@? ", movieTitle, show.movieYear);
            releaseMatch = YES;
        } else {
            NSString * releaseYear = [releaseDate substringToIndex:4];
            releaseMatch = [releaseYear isEqualToString:show.movieYear];
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

-(void) getTheMovieDBDetailsForShow: (MTTiVoShow *) show {
    if (show.gotTVDBDetails) return;

    //we only get artwork
    NSString * urlString = [[NSString stringWithFormat:@"https://api.themoviedb.org/3/search/movie?query=\"%@\"&api_key=%@",show.seriesTitle, kMTTheMoviedDBAPIKey] stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    NSString * reportURL = [urlString stringByReplacingOccurrencesOfString:kMTTheMoviedDBAPIKey withString:@"APIKEY" ];
    DDLogDetail(@"Getting movie Data for %@ using %@",show,reportURL);
    NSURL *url = [NSURL URLWithString:urlString];
    NSData *movieInfo = [NSData dataWithContentsOfURL:url options:NSDataReadingUncached error:nil];
    if (!movieInfo) return;
    show.gotTVDBDetails = YES;

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
        DDLogMajor(@"theMovieDB couldn't find any movies named %@", show.seriesTitle);
        return;
    }
    NSString * newArtwork = nil;
    for (NSDictionary * movie in results) {
        //look for a perfect title/release match
        NSString * location = [self checkMovie:movie exact:YES forShow:show];
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
            NSString * location = [self checkMovie:movie exact:NO forShow:show];
            if (location) {
                if (![location isEqualToString:kFormatError]) {
                    newArtwork = location;
                }
                break;
            }
        }
    }
    if (newArtwork.length > 0 ) {
        show.tvdbArtworkLocation = newArtwork;
        [self rememberArtWork:newArtwork forSeries:show.seriesId];
    } else {

    }
}

-(void)retrieveArtworkIntoFile: (NSString *) filename forShow: (MTTiVoShow *) show
{
    //should split this into show-specific stuff (filename calc) vs service stuff (URLS and retrieval), and put former back in MTTiVoShow
    if(!show.gotTVDBDetails && show.isMovie) {
        //we don't get movie data upfront, so go get it now, but call us back when you have it
        __weak typeof(self) weakSelf = self;
        dispatch_async(dispatch_get_global_queue( DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(void){
            typeof(self) strongSelf = weakSelf;
            [strongSelf getTheMovieDBDetailsForShow:show];
            dispatch_async(dispatch_get_main_queue(), ^(void){
                [strongSelf retrieveArtworkIntoFile:filename forShow:show];
            });
        });
        return;

    }
    if (show.tvdbArtworkLocation.length == 0) {
        return;
    }
    NSString * fileNameDetail;
    NSString *baseUrlString;
    if (show.isMovie) {
        fileNameDetail = [show movieYear];
        baseUrlString = @"http://image.tmdb.org/t/p/w780%@";
    } else {
        fileNameDetail = [show seasonEpisode];
        baseUrlString = @"http://thetvdb.com/banners/%@";
    }
    NSString * destination;
    if (fileNameDetail.length) {
        destination = [NSString stringWithFormat:@"%@_%@",filename, fileNameDetail];
    } else {
        destination = filename;
    }

    NSString *urlString = [[NSString stringWithFormat: baseUrlString, show.tvdbArtworkLocation ]
                           stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];

    NSString * path = [destination stringByDeletingLastPathComponent];
    NSString * base = [destination lastPathComponent];
    NSString * extension = [show.tvdbArtworkLocation pathExtension];

    base = [base stringByReplacingOccurrencesOfString:@"/" withString:@"-"];
    base = [base stringByReplacingOccurrencesOfString:@":" withString:@"-"] ;

    NSString * realDestination = [[path stringByAppendingPathComponent:base] stringByAppendingPathExtension:extension];

    //download only if we don't have it already
    if (![[NSFileManager defaultManager] fileExistsAtPath:realDestination]) {
        DDLogDetail(@"downloading artwork at %@ to %@",urlString, realDestination);
        NSURLRequest *req = [NSURLRequest requestWithURL:[NSURL URLWithString:urlString]];
        [NSURLConnection sendAsynchronousRequest:req queue:[NSOperationQueue mainQueue] completionHandler:^(NSURLResponse *response, NSData *data, NSError *error) {
            if (!data || error) {
                DDLogMajor(@"Couldn't get artwork for %@ from %@ , Error: %@", show.seriesTitle, urlString, error.localizedDescription);
            } else {
                if ([data writeToFile:realDestination atomically:YES]) {
                    show.artworkFile = realDestination;
                    DDLogDetail(@"Saved artwork file for %@ at %@",show.showTitle, realDestination);
                } else {
                    DDLogReport(@"Couldn't write to artwork file %@", realDestination);
                }
            }
        }];
    }
}

@end
