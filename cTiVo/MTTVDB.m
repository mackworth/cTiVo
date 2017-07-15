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
    @property (atomic, strong) NSString * tvdbToken;
    @property (nonatomic, strong) NSDate * tvdbTokenExpireTime;
    @property (nonatomic, strong) NSURLSession * tvdbURLSession;

    @property (atomic, strong) NSMutableDictionary <NSString *, NSArray <NSString *> *> *tvdbSeriesIdMapping;
    @property (atomic, strong) NSMutableDictionary *tvdbCache;
    @property (atomic, strong) NSMutableDictionary * theTVDBStatistics;

    @property (atomic, strong) NSDate * movieDBRateLimitEnd;
    @property (atomic, strong) NSNumber * movieDBRateLimitLock;
    @property (atomic, assign) NSInteger movieDBRateLimitCalls;

@end

@implementation MTTVDB

__DDLOGHERE__

#pragma mark - TVDB lifetime

+ (MTTVDB *)sharedManager {
    static dispatch_once_t pred;
    static MTTVDB *myManager = nil;
    dispatch_once(&pred, ^{
        myManager = [[self alloc] init];
    });
    return myManager;
}

-(void) saveDefaults {
    NSUserDefaults * defaults = [NSUserDefaults standardUserDefaults];
    @synchronized(self.tvdbCache) {
        [defaults setObject:self.tvdbCache forKey:kMTTheTVDBCache];
    }
    if ([self.tvdbTokenExpireTime compare:[NSDate distantPast]] == NSOrderedDescending ) {
        [defaults setObject:self.tvdbTokenExpireTime forKey:kMTTVDBTokenExpire];
        [defaults setObject:self.tvdbToken forKey:kMTTVDBToken];
    }
}

-(instancetype) init {
    if ((self = [super init])) {
        self.tvdbTokenExpireTime =  [[NSUserDefaults standardUserDefaults] objectForKey: kMTTVDBTokenExpire ] ?: [NSDate distantPast];
        self.tvdbToken = [[NSUserDefaults standardUserDefaults] objectForKey: kMTTVDBToken ];
        self.movieDBRateLimitLock = @(1); //just for locking

        self.tvdbSeriesIdMapping = [NSMutableDictionary dictionary];
        self.tvdbCache = [NSMutableDictionary dictionaryWithDictionary:[[NSUserDefaults standardUserDefaults] objectForKey:kMTTheTVDBCache]];
        self.theTVDBStatistics = [NSMutableDictionary dictionary];

        [self cleanCache];
        [self checkToken];
    }
    return self;
}

-(void) resetAll {
    //Remove TVDB Cache
    [[NSUserDefaults standardUserDefaults] setObject:@{} forKey:kMTTheTVDBCache];

    self.tvdbSeriesIdMapping = [NSMutableDictionary dictionary];
    @synchronized(self.theTVDBStatistics) {
        self.theTVDBStatistics = [NSMutableDictionary dictionary];
    }

}

#pragma mark -
#pragma mark HTTP sessions for TVDB

-(void) cancelSession {
    if (self.tvdbURLSession) DDLogReport(@"canceling TVDB Session");
    [self.tvdbURLSession getAllTasksWithCompletionHandler:^(NSArray<__kindof NSURLSessionTask *> * _Nonnull tasks) {
        for (NSURLSessionTask * task in tasks) {
            [task cancel];
        }
        [self checkToken];
    }];
    self.tvdbToken = nil; self.tvdbURLSession = nil;

}

-(NSURLSession *) tvdbURLSession {
    if (!_tvdbURLSession) {
        DDLogReport(@"Establishing Session");

        NSInteger numTries = 10;
        while (![self checkToken]  && numTries > 0) {
            DDLogMajor(@"Still checking for TVDB token");
            usleep(250000);   //FIX: pausing for a quarter-second up to 2.5 seconds on main queue is not good
            numTries--;
        }
        if (self.tvdbToken) {
            NSURLSessionConfiguration * config = [NSURLSessionConfiguration defaultSessionConfiguration];
            config.HTTPAdditionalHeaders = @{@"Accept": @"application/json",
                                             @"Content-Type": @"application/json",
                                             @"Authorization": [NSString stringWithFormat:@"Bearer %@",self.tvdbToken]};
            _tvdbURLSession = [NSURLSession sessionWithConfiguration:config];
        } else {
            DDLogReport(@"Cannot establish session with TVDB");
        }
    }
    return _tvdbURLSession;
}

-(BOOL) checkToken {
    @synchronized (self.tvdbTokenExpireTime) {
        static BOOL inProgress = NO;
        if (self.tvdbToken && [self.tvdbTokenExpireTime compare:[NSDate date]] == NSOrderedDescending) {
            return YES;
        } else if (inProgress) {
            return NO;
        } else {
            inProgress = YES;
            //don't have a token or it's expired
            self.tvdbToken = nil;

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
                        NSDictionary *jsonData = [NSJSONSerialization JSONObjectWithData:data options: 0 error: &jsonError];
                        if (!jsonError || ![jsonData isKindOfClass:[NSDictionary class]]) {
                            NSString * token = jsonData[@"token"];
                            if (token.length) {
                                self.tvdbToken = token;
                                self.tvdbTokenExpireTime = tokenExpiration;
                                DDLogDetail(@"Got TVDB token: %@", token);
                            } else {
                                DDLogReport(@"NO Token?? %@", jsonData);
                            }
                        } else {
                            DDLogReport(@"TVDB Token JSON parsing Error: %@", data);
                        }
                    } else {
                        DDLogReport(@"TVDB Token HTTP Response Error %ld: %@, %@", (long)httpResponse.statusCode,  [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding], httpResponse.URL );
                        [self cancelSession];
                    }
                }

            }];
            DDLogDetail(@"requesting token: %@", tokenURL);
            [task resume];
            return NO; //no token available right now
        }
    }
}

-(void) seriesIDForShow: (NSString *) series
      completionHandler: (void(^) (NSArray <NSString *> *seriesIDs)) completionBlock
         failureHandler: (void(^) (void)) failureBlock {
    NSAssert ([NSThread isMainThread], @"seriesIDForShow running in background");

    NSURL *seriesURL = [NSURL URLWithString: [NSString stringWithFormat:@"https://api.thetvdb.com/search/series?name=%@",[series escapedQueryString]] ];
    NSURLSessionDataTask *task = [self.tvdbURLSession  dataTaskWithURL: seriesURL completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (!error) {
            NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
            if (httpResponse.statusCode == 200){
                NSError * jsonError;
                NSDictionary *jsonData = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingAllowFragments error: &jsonError];
                if (!jsonError && [jsonData isKindOfClass:[NSDictionary class]]) {
                    if (!jsonData[@"error"]) {
                        NSArray * seriesList = jsonData[@"data"];
                        if ([seriesList isKindOfClass:[NSArray class]]) {
                            NSMutableArray * seriesIDs = [NSMutableArray array];;
                            for (NSDictionary * seriesDict in seriesList) {
                                //multiple shows
                                if ([seriesDict isKindOfClass:[NSDictionary class]]) {
                                    NSNumber * seriesID = seriesDict[@"id"];
                                    NSString * seriesName = seriesDict[@"seriesName"];
                                    if ([seriesID isKindOfClass:[NSNumber class]] &&
                                        [seriesName isKindOfClass:[NSString class]]) {
                                        NSString * seriesNameNoYear = [[seriesName removeParenthetical] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]; //tvdb adds (2011) to distinguish series
                                        if ([series isEqualTo:seriesName] ||
                                             [series isEqualTo:seriesNameNoYear]) {
                                            [seriesIDs insertObject:seriesID.description atIndex:0];
                                        } else {
                                            [seriesIDs addObject:seriesID.description];
                                        }
                                    } else if (![seriesName isKindOfClass:[NSNull class]]) {
                                        DDLogReport(@"TVDB Series JSON type Error ('id' Number; seriesName String): %@ for %@", seriesDict, series);
                                    }
                                } else {
                                    DDLogReport(@"TVDB Series JSON type Error (data contents should be dictionaries): %@ for %@", seriesDict, series);
                                }
                            }
                            if (completionBlock && seriesIDs.count > 0 ) {dispatch_async(dispatch_get_main_queue(), ^{
                                    completionBlock(seriesIDs);
                                });
                            }
                            return;
                        } else {
                            DDLogReport(@"TVDB Series JSON type Error (data level must be Array): %@ for %@", seriesList, series);
                        }
                    } else {
                        // expected result when series not found
                        DDLogDetail(@"TVDB Series not found: %@ for %@", series, jsonData[@"error"]);
                    }
                } else {
                    DDLogReport(@"TVDB Series JSON parsing Error: %@ for %@",  [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding], series);
                }
            } else if (httpResponse.statusCode == 404){
                DDLogVerbose(@"TVDB Series %@ not found at %@" , series, seriesURL );
            } else {
                DDLogReport(@"TVDB Series HTTP Response Error %ld: %@, %@ for %@", (long)httpResponse.statusCode, [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding], httpResponse.URL, series );
                [self cancelSession];
            }
        }
        if (failureBlock) {
            dispatch_async(dispatch_get_main_queue(),failureBlock);
        }

    }];
    DDLogDetail(@"requesting seriesID for show %@: %@", series, seriesURL);
    [task resume];
}

-(void) searchForEpisodeNamed: (NSString *) episodeName
                     inSeries: (NSArray <NSString *> *) seriesIDs
            completionHandler: (void(^) (NSString * seriesID, NSDictionary * episodeInfo)) completionBlock
               failureHandler: (void(^) (void)) failureBlock
                   pageNumber: (NSInteger) pageNumber
{
    if (seriesIDs.count == 0) return;

    NSString * seriesID = [seriesIDs firstObject];
    NSString *episodeURLString = [NSString stringWithFormat:@"https://api.thetvdb.com/series/%@/episodes/query?page=%ld",seriesID, (long)pageNumber] ;
    NSString * partialEpisodeName = episodeName; //for dual episodes separated by semicolon
    if ([episodeName contains:@";"]) {
        NSArray * episodeSplit = [episodeName componentsSeparatedByString:@";"];
        if (episodeSplit.count > 0) partialEpisodeName = episodeSplit[0];
    }
    partialEpisodeName = [[partialEpisodeName removeParenthetical] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    NSURL *episodeURL = [NSURL URLWithString:episodeURLString];
    NSURLSessionDataTask *task = [self.tvdbURLSession dataTaskWithURL:episodeURL completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSNumber *nextPage = @(-1);
        if (!error) {
            NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
            if (httpResponse.statusCode == 200){
                NSError * jsonError;
                NSDictionary *jsonData = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingAllowFragments error: &jsonError];
                if (!jsonError && [jsonData isKindOfClass:[NSDictionary class]]) {
                    if (!jsonData[@"error"]) {
                        DDLogVerbose(@"TVDB Episode JSON: %@", jsonData);
                        nextPage = jsonData[@"links"][@"next"];
                        NSArray * episodeList = jsonData[@"data"];
                        if ([episodeList isKindOfClass:[NSArray class]]) {
                            for (NSDictionary * episodeDict in episodeList) {
                                if ([episodeDict isKindOfClass:[NSDictionary class]]) {
                                    NSString * tvdbEpisodeName = episodeDict[@"episodeName"];
                                    if ([tvdbEpisodeName isKindOfClass:[NSString class]]) {
                                        NSString * partialTVDB = [[tvdbEpisodeName removeParenthetical] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                                        if ([tvdbEpisodeName localizedCaseInsensitiveCompare: episodeName] == NSOrderedSame ||
                                            [partialTVDB localizedCaseInsensitiveCompare: partialEpisodeName] == NSOrderedSame) {
                                            if (completionBlock) {
                                                dispatch_async(dispatch_get_main_queue(), ^{
                                                    completionBlock(seriesID, episodeDict);
                                                });
                                            }
                                            return; // found exact match, so no more processing.
                                        }
                                    } else if (![tvdbEpisodeName isKindOfClass:[NSNull class]]) {
                                        DDLogReport(@"TVDB Episode JSON type Error ('episodeName' should be String). For %@ on page %@ tvdb has %@",  seriesID, @(pageNumber), episodeDict);
                                    }
                                } else {
                                    DDLogReport(@"TVDB Episode JSON type Error (should be dictionary): %@ for %@", episodeDict, seriesID);
                                }
                            }
                        } else {
                            DDLogReport(@"TVDB Episode JSON type Error (should be Array): %@ for %@", episodeList, seriesID);
                        }
                    } else {
                        DDLogDetail(@"TVDB error for %@: %@", seriesID, error.localizedFailureReason);
                    }
                } else {
                    DDLogReport(@"TVDB Episode JSON parsing Error: %@ for %@",  [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding], seriesID);
                }
            } else if (httpResponse.statusCode == 404){
                DDLogVerbose(@"TVDB episode %@ in series %@ not found on page %@", episodeName, seriesID, @(pageNumber));
            } else {
                DDLogReport(@"TVDB Episode HTTP Response Error %ld: %@, %@ fr %@", (long)httpResponse.statusCode,  [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding], httpResponse.URL, seriesID );
                [self cancelSession];
           }
        } else {
            DDLogReport(@"TVDB Episode Call Error %@: for %@", error.localizedFailureReason, episodeURL );

        }

        //so this one didn't work; let's try the next one, either next page or next seriesID
        if ([nextPage isKindOfClass: NSNumber.class] && nextPage.integerValue > 0) {
            [self searchForEpisodeNamed: episodeName
                               inSeries: seriesIDs
                      completionHandler: completionBlock
                         failureHandler: failureBlock
                             pageNumber: nextPage.integerValue];
        } else if (seriesIDs.count <= 1) {
            //no more candidates, so we failed.
            if (failureBlock) dispatch_async(dispatch_get_main_queue(),failureBlock);
        } else {
            NSArray * restSeriesIDs =    [seriesIDs subarrayWithRange:NSMakeRange(1, seriesIDs.count - 1)];
            [self searchForEpisodeNamed: episodeName
                               inSeries: restSeriesIDs
                      completionHandler: completionBlock
                         failureHandler: failureBlock
                             pageNumber: 1];
        }
    }];
    DDLogDetail(@"searching by episodeName %@ for show in TVDB show %@ : %@", episodeName, seriesID, episodeURL);
   [task resume];
}


-(void) infoForEpisodeNamed: (NSString *) episodeName
                   inSeries: (NSArray <NSString *> *) seriesIDs
                  onAirDate: (NSString *) originalAirDate
          completionHandler: (void(^) (NSString * seriesID, NSDictionary * episodeInfo)) completionBlock
             failureHandler: (void(^) (void)) failureBlock
      withSeriesIDCandidate: (NSString *) seriesIDCandidate
        andEpisodeCandidate: (NSDictionary *) episodeCandidate
 {

    if (seriesIDs.count == 0) return;
     __block NSDictionary * localEpisodeCandidate = episodeCandidate;
     __block NSString * localSeriesIDCandidate = seriesIDCandidate;

    NSString * seriesID = [seriesIDs firstObject];
    NSString *episodeURLString = [NSString stringWithFormat:@"https://api.thetvdb.com/series/%@/episodes/query?firstAired=%@",seriesID, originalAirDate] ;
     NSString * partialEpisodeName = nil; //for dual episodes separated by semicolon
     if ([episodeName contains:@";"]) {
         NSArray * episodeSplit = [episodeName componentsSeparatedByString:@";"];
         if (episodeSplit.count > 0) partialEpisodeName = episodeSplit[0];
     }
    NSURL *episodeURL = [NSURL URLWithString: episodeURLString];
     NSURLSessionDataTask *task = [self.tvdbURLSession dataTaskWithURL:episodeURL completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (!error) {
            NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
            if (httpResponse.statusCode == 200){
                NSError * jsonError;
                NSDictionary *jsonData = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingAllowFragments error: &jsonError];
                if (!jsonError && [jsonData isKindOfClass:[NSDictionary class]]) {
                    if (!jsonData[@"error"]) {
                        DDLogVerbose(@"TVDB Episode JSON: %@", jsonData);
                        NSArray * episodeList = jsonData[@"data"];
                        if ([episodeList isKindOfClass:[NSArray class]]) {
                            for (NSDictionary * episodeDict in episodeList) {
                                //possibly multiple shows on same airdate
                                if ([episodeDict isKindOfClass:[NSDictionary class]]) {
                                    NSString * tvdbEpisodeName = episodeDict[@"episodeName"];
                                    if ([tvdbEpisodeName isKindOfClass:[NSString class]]) {
                                        if ([tvdbEpisodeName localizedCaseInsensitiveCompare: episodeName] == NSOrderedSame ||
                                            [tvdbEpisodeName localizedCaseInsensitiveCompare: partialEpisodeName] == NSOrderedSame) {
                                            if (completionBlock) {
                                                dispatch_async(dispatch_get_main_queue(), ^{
                                                    completionBlock(seriesID, episodeDict);
                                                });
                                            }
                                            return; // found exact match, so no more processing.
                                        } else if (!localEpisodeCandidate) {
                                            //remember first match
                                            localEpisodeCandidate = episodeDict;
                                            localSeriesIDCandidate = seriesID;
                                        }
                                    } else if (![tvdbEpisodeName isKindOfClass:[NSNull class]]) {
                                        DDLogReport(@"TVDB Episode JSON type Error ('episodeNumber' should be String). For %@ on %@ tvdb has %@",  seriesID, originalAirDate,episodeDict);
                                    }
                                } else {
                                    DDLogReport(@"TVDB Episode JSON type Error (should be dictionary): %@ for %@", episodeDict, seriesID);
                                }
                            }
                        } else {
                            DDLogReport(@"TVDB Episode JSON type Error (should be Array): %@ for %@", episodeList, seriesID);
                        }
                    } else {
                        DDLogDetail(@"TVDB error for %@: %@", seriesID, error.localizedFailureReason);
                    }
                } else {
                    DDLogReport(@"TVDB Episode JSON parsing Error: %@ for %@",  [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding], seriesID);
                }
            } else if (httpResponse.statusCode == 404){
                DDLogVerbose(@"TVDB episode %@ in series %@ not found on %@", episodeName, seriesID, originalAirDate);
            } else {
                DDLogReport(@"TVDB Episode HTTP Response Error %ld: %@, %@ fr %@", (long)httpResponse.statusCode,  [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding], httpResponse.URL, seriesID );
                [self cancelSession];
           }
        } else {
            DDLogReport(@"TVDB Episode Call Error %@: for %@", error.localizedFailureReason, episodeURL );

        }
        if (seriesIDs.count <= 1) {
            //no more candidates, so return first fit.
            if (localEpisodeCandidate) {
                if (completionBlock) {
                    dispatch_async(dispatch_get_main_queue(),^{
                        completionBlock(localSeriesIDCandidate, localEpisodeCandidate);
                    });
                }
            } else if (failureBlock) {
                dispatch_async(dispatch_get_main_queue(),failureBlock);
            }
        } else {
            //so this one didn't work; let's try the next one.
            NSArray * restSeriesIDs = [seriesIDs subarrayWithRange:NSMakeRange(1, seriesIDs.count - 1)];
            [self infoForEpisodeNamed:episodeName
                             inSeries:restSeriesIDs
                            onAirDate:originalAirDate
                    completionHandler:completionBlock
                       failureHandler:failureBlock
                 withSeriesIDCandidate:localSeriesIDCandidate
                  andEpisodeCandidate:localEpisodeCandidate];
        }
    }];
     DDLogDetail(@"searching by OAD %@ for show (episode %@) in TVDB %@ : %@", originalAirDate, episodeName, seriesID, episodeURL);
    [task resume];

}


-(void) infoForEpisodeNamed: (NSString *) episodeName
                   inSeries: (NSArray <NSString *> *) seriesIDs
                  onAirDate: (NSString *) originalAirDate
          completionHandler: (void(^) (NSString * seriesID, NSDictionary * episodeInfo)) completionBlock
             failureHandler: (void(^) (void)) failureBlock {
    //look for first episode that has the original airdate, and whose name matches episodeName.
    //if none, then use first episode with original airdate
    //then call completionBlock to hand values back to original caller.
    //use recursion to index across seriesIDs
    [self infoForEpisodeNamed:episodeName
                     inSeries:seriesIDs
                    onAirDate:originalAirDate
            completionHandler:completionBlock
               failureHandler:^{
                   //so no episodes with exact air date, let's find one with exact name match instead
                   if (episodeName.length) {
                       [self searchForEpisodeNamed: episodeName
                                      inSeries: seriesIDs
                             completionHandler: completionBlock
                                failureHandler: failureBlock
                                    pageNumber: 1];
                   } else {
                       if (failureBlock) failureBlock();
                   }
               }
        withSeriesIDCandidate:nil
          andEpisodeCandidate:nil];

}

-(void) test {
//    [ self seriesIDForShow:@"Counting Cars" completionHandler:^(NSArray<NSString *> *seriesIDs) {
//        NSLog(@"TESTING!!! Found %@ for Counting Cars", seriesIDs);
//    } failureHandler:^{
//        NSLog(@"TESTING!!! Couldn't find Counting Cars");
//    }];
//
//    [self infoForEpisodeNamed:@"Patriotic Chopper"
//                     inSeries:@[@"316390",
//                                @"261181"]
//                onAirDate:@"2017-04-08"
//            completionHandler:^(NSString * seriesID, NSDictionary *episodeInfo) {
//                NSLog(@"For SeriesID: %@, episodeInfo: %@", seriesID, episodeInfo);
//            } failureHandler:^{
//                NSLog(@"Couldn't find Chopper");
//            }];
}

#pragma mark -
#pragma mark statistics

//Note that getDetails and getTVDB need to be thread-safe. In particular, any setting of values that might be displayed needs to occur on main thread,
//and any access to global data needs to @synchronized
//These will be printed out in alpha order...

#define kMTVDBAll @"All"
#define kMTVDBMovie @"Movie"
#define kMTVDBMovieFound @"Movie Found"
#define kMTVDBMovieFoundCached @"Movie Found Cached"
#define kMTVDBMovieNotFound @"Movie Not Found"
#define kMTVDBMovieNotFoundCached @"Movie Not Found Cached"

#define kMTVDBNonEpisodicSeriesFound          @"Non-episodic Series Found"
#define kMTVDBNonEpisodicSeriesFoundCached    @"Non-episodic Series Found Cached"
#define kMTVDBNonEpisodicSeriesNotFound       @"Non-episodic Series Info Not Found"
#define kMTVDBNonEpisodicSeriesNotFoundCached @"Non-episodic Series Info Not Found Cached"

#define kMTVDBSeriesEpisodeFound              @"Series and Episode Found"
#define kMTVDBSeriesEpisodeFoundCached        @"Series and Episode Found Cached"
#define kMTVDBEpisodicSeriesNotFound          @"Series Info Not Found"
#define kMTVDBEpisodicSeriesNotFoundCached    @"Series Info Not Found Cached"
#define kMTVDBEpisodeNotFound                 @"Series Found, but Episode Not Found"
#define kMTVDBEpisodeNotFoundCached           @"Series Found, but Episode Not Found Cached"

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

-(NSString *) urlsForReporting:(NSArray <NSString *> *) tvdbIDs {
    NSMutableArray * urls = [NSMutableArray arrayWithCapacity:tvdbIDs.count];
    for (NSString * tvdbID in tvdbIDs) {
        NSString * showURL = [NSString stringWithFormat:@"http://thetvdb.com/?tab=seasonall&id=%@lid=7",tvdbID];
        [urls addObject:showURL];
    }
    return [urls componentsJoinedByString: @" OR "];
}

-(NSString *) stats {
    NSDictionary * statsCopy;
    @synchronized(self.theTVDBStatistics) {
        statsCopy = self.theTVDBStatistics.copy;
    }
    NSString * statisticsReport =
    @"\nAs TiVo doesn't provide us season/episode information or artwork, cTiVo looks up the TiVo's shows on theTVDB and the movies on theMovieDB.\n"
    "You can click on the individual URLs to see what information is available for shows where the lookup failed.\n\n"
    "Total number of shows is %lu\n"
    "%lu shows are marked as Movies\n"
    "%lu shows are marked as Episodic\n"
    "%lu shows are marked as Non-Episodic (e.g. news/sports events)\n"
    "\n"
    "cTiVo caches information as possible; successful lookups for 30 days; unsuccessful for 1 day\n"
    "\n"
    "In the last group we looked up, we had the following results:\n"
    "Movies:\n"
    "   %lu shows found (cached: %0.0f%%)\n"
    "   %lu series not found (cached: %0.0f%%)\n"
    "\n"
    "Episodic:\n"
    "   %lu shows found (cached: %0.0f%%)\n"
    "   %lu series found, but episodes not Found (cached: %0.0f%%)\n"
    "   %lu series not found (cached: %0.0f%%)\n"
    "\n"
    "Non-Episodic:\n"
    "   %lu shows found (cached: %0.0f%%)\n"
    "   %lu series not found (cached: %0.0f%%)\n"
    "\n"
    "Here are the shows that had issues:\n"
    "Movies not Found at theMovieDB\n"
    "%@\n\n"
    "Movies not Found (Cached)\n"
    "%@\n\n"

    "Episodic Series not Found at TVDB\n"
    "%@\n\n"
    "Episodic Series not Found (Cached)\n"
    "%@\n\n"
    "Episodic Series Found, but episodes not found at TVDB\n"
    "%@\n\n"
    "Episodic Series Found, but episodes not found (Cached)\n"
    "%@\n\n"
    "Non-Episodic Series not Found at TVDB\n"
    "%@\n\n"
    "Non-Episodic Series not Found (Cached)\n"
    "%@\n\n"

    ;
#define val(x) (unsigned long)(((NSNumber *)statsCopy[x]).integerValue)
#define combineVal(x) (val(x) + val(x " Cached"))
#define percentVal(x) combineVal(x) , (100.0 * (float)val(x " Cached") / (float)combineVal(x))
#define cval(x) val(x " Count")
#define combineCval(x) (cval(x) + cval(x " Cached"))
#define percentCval(x) combineCval(x) , (100.0 * (float)cval(x " Cached") / (float)combineCval(x))
#define list(x) statsCopy[x " List"] ?: @"None", statsCopy[x " Cached List"]  ?: @"None"
    statisticsReport = [NSString stringWithFormat:
                        statisticsReport
                        ,

                        val(kMTVDBAll),
                        val(kMTVDBMovie),

                        combineVal(kMTVDBSeriesEpisodeFound) +
                        combineCval(kMTVDBEpisodicSeriesNotFound) +
                        combineCval(kMTVDBEpisodeNotFound),

                        combineVal(kMTVDBNonEpisodicSeriesFound) +
                        combineCval(kMTVDBNonEpisodicSeriesNotFound),

                        percentVal(kMTVDBMovieFound),
                        percentCval(kMTVDBMovieNotFound),

                        percentVal(kMTVDBSeriesEpisodeFound),
                        percentCval(kMTVDBEpisodeNotFound),
                        percentCval(kMTVDBEpisodicSeriesNotFound),

                        percentVal(kMTVDBNonEpisodicSeriesFound),
                        percentCval(kMTVDBNonEpisodicSeriesNotFound),

                        list(kMTVDBMovieNotFound),

                        list(kMTVDBEpisodicSeriesNotFound),
                        list(kMTVDBEpisodeNotFound),

                        list(kMTVDBNonEpisodicSeriesNotFound)

                        ];

    return statisticsReport;
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
        NSString * statisticCount = [statistic stringByAppendingString:@" Count"];
        self.theTVDBStatistics[statisticCount] = @([self.theTVDBStatistics[statisticCount] intValue] + 1);
        [statisticList setValue: value forKey: show]; //keep latest version in case it changed
    }
}
#pragma mark - Caching routines
//These should be in TiVoManager, so we can access from MTTiVoShow more appropriately.
#define kMTVDBMissing @"Series Not Found in TVDB"

-(void) cleanCache {
    @synchronized (self.tvdbCache) {    //Clean up old entries
        NSMutableArray *keysToDelete = [NSMutableArray array];
        for (NSString *key in self.tvdbCache) {
            NSDictionary * episodeInfo = [self.tvdbCache objectForKey:key];
            NSDate *createDate = episodeInfo[@"date"];
            NSInteger numDays = 30;
            if ([episodeInfo[@"series"] isEqualToString:kMTVDBMissing]) {
                numDays = 1;
            } else if ([episodeInfo[@"manual"] isEqual:@(YES)]) {
                numDays = 365;
                //would be better to purge tvdbcache after finishing loading episodes.
            }
            if ([[NSDate date] timeIntervalSinceDate:createDate] > 60.0 * 60.0 * 24.0 * numDays) { //Too old so throw out
                [keysToDelete addObject:key];
            }
        }
        for (NSString *key in keysToDelete) {
            [self.tvdbCache removeObjectForKey:key];
        }
    }
}

-(void) cacheArtWork: (NSString *) newArtwork forShow: (NSString *) name {
    if ( name.length > 0) {  //protective only
        @synchronized (self.tvdbCache) {
            NSMutableDictionary * oldEntry = [[self.tvdbCache objectForKey:name] mutableCopy];
            if (!oldEntry) {
                oldEntry = [NSMutableDictionary dictionaryWithObject: [NSDate date] forKey:@"date"];
            }
            [oldEntry setObject:newArtwork forKey:@"artwork"];
            [self.tvdbCache setObject:[oldEntry copy]
                               forKey:name];
        }
    }
}

-(NSString *) cachedArtWorkForShow: (NSString *) name {
    if ( name.length > 0) {  //protective only
        @synchronized (self.tvdbCache) {
            NSDictionary * entry = [self.tvdbCache objectForKey:name];
            return entry[@"artwork"];
        }
    } else {
        return nil;
    }
}

-(void) cacheSeason:(NSInteger) season andEpisode:(NSInteger) episode forShow: (MTTiVoShow *) show {
    NSString * uniqueID = show.uniqueID;
    if ( uniqueID.length > 0) {  //protective only
        @synchronized (self.tvdbCache) {
            NSMutableDictionary * oldEntry = [[self.tvdbCache objectForKey:uniqueID] mutableCopy];
            if (season > 0 || episode > 0) {
                if (!oldEntry) {
                    oldEntry = [NSMutableDictionary dictionaryWithObject: [NSDate date] forKey:@"date"];
                }
                [oldEntry setObject:@(season) forKey:@"season"];
                [oldEntry setObject:@(episode) forKey:@"episode"];
                [oldEntry setObject:@(YES) forKey:@"manual"];

                [self.tvdbCache setObject:[oldEntry copy]
                                   forKey:uniqueID];
            } else if (oldEntry && [oldEntry[@"manual"] isEqual:@(YES)]) {
                [self.tvdbCache removeObjectForKey: uniqueID];
            }
        }
        [[ NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationDetailsLoaded object:show];
    }
}

-(void) cacheTVDBSeriesID: (NSArray *) seriesIDs forSeries: (NSString *) seriesTitle{
    @synchronized (self.tvdbSeriesIdMapping) {
        if (!seriesIDs.count) {
            [self.tvdbSeriesIdMapping removeObjectForKey:seriesTitle];
        } else {
            [self.tvdbSeriesIdMapping setObject:[NSArray arrayWithArray: seriesIDs] forKey:seriesTitle];
        }
    }
}

-(NSArray <NSString *> *) cachedTVDBSeriesID:(NSString *) title {
    @synchronized (self.tvdbSeriesIdMapping) {
        return  [self.tvdbSeriesIdMapping objectForKey:title];
    }
}

-(NSString *) seriesIDsForShow:(MTTiVoShow *)show {
    NSString * seriesIDs = [[self cachedTVDBSeriesID:show.seriesTitle] componentsJoinedByString:@" OR "]; // see if we've already done this
    if (!seriesIDs) {
        @synchronized (self.tvdbCache) {
            NSDictionary *TVDBepisodeEntry = [self.tvdbCache objectForKey:show.uniqueID];
            //could provide these ,too?
            // NSNumber * TVDBepisodeNum = [TVDBepisodeEntry objectForKey:@"episode"];
            //NSNumber * TVDBseasonNum = [TVDBepisodeEntry objectForKey:@"season"];
            seriesIDs = [TVDBepisodeEntry objectForKey:@"series"];
            if ([kMTVDBMissing isEqual:seriesIDs] ) {
                seriesIDs = @"";
            }
        };
    }
    return seriesIDs;
}


#pragma mark - External routines

-(BOOL) checkType:(NSString *) type inDict: (NSDictionary *) dict {
    BOOL result = [dict[type] isKindOfClass:[NSString class]] ||
           [dict[type] isKindOfClass:[NSNumber class]];
    if (!result) {
        DDLogReport(@"TVDB missing or type failure: %@ in %@",type, dict);
    }
    return result;
}

-(void)getEpisodeDetailsForShow: (MTTiVoShow *) show withIDs: (NSArray <NSString *> *) seriesIDs {
    //We have found seriesIDs, now get episodeInfo and process for Show
    NSAssert ([NSThread isMainThread], @"getEpisodeDetailsForShow completion running in background");
    __weak typeof(self) weakSelf = self;

    [self infoForEpisodeNamed:show.episodeTitle
                     inSeries:seriesIDs
                    onAirDate:show.originalAirDateNoTime
            completionHandler:^(NSString *seriesID, NSDictionary *episodeInfo ) {
                typeof(self) strongSelf = weakSelf;

                if ([strongSelf checkType:@"airedSeason" inDict:episodeInfo] &&
                    [strongSelf checkType:@"airedEpisodeNumber" inDict:episodeInfo] &&
                    [strongSelf checkType:@"id" inDict:episodeInfo]) {
                    NSString * artworkLocation = [NSString stringWithFormat:@"episodes/%@/%@.jpg",seriesID, episodeInfo[@"id"]];
                    DDLogDetail(@"TVDB Artwork for %@ at %@",show, artworkLocation);
                    [strongSelf incrementStatistic:kMTVDBSeriesEpisodeFound];
                    NSNumber * season = episodeInfo[@"airedSeason"];
                    NSNumber * episode = episodeInfo[@"airedEpisodeNumber"];
                    @synchronized (strongSelf.tvdbCache) {
                        [strongSelf.tvdbCache setObject:@{
                                                    @"season":  season.description,
                                                    @"episode": episode.description,
                                                    @"artwork": artworkLocation,
                                                    @"series": seriesID,
                                                    @"date":[NSDate date]
                                                    } forKey:show.uniqueID];
                    }
                    //remember the one that worked, not all the others
                    NSArray *seriesIDTVDBs = @[seriesID];
                    [self cacheTVDBSeriesID:seriesIDTVDBs forSeries:show.seriesTitle];

                    [strongSelf finishTVDBProcessing:show];
                    DDLogVerbose(@"Got TVDB episodeInfo for %@: %@", show.showTitle, episodeInfo);
              } else {
                  DDLogReport(@"TVDB Failure for %@; missing Season, Episode or id: %@", [self urlsForReporting:@[seriesID]],episodeInfo);
              }
            } failureHandler:^(){
                typeof(self) strongSelf = weakSelf;
                [strongSelf addValue:[NSString stringWithFormat:@"Date: %@, URLs:%@",show.originalAirDateNoTime, [self urlsForReporting:seriesIDs]] inStatistic:kMTVDBEpisodeNotFound forShow:show.showTitle];
                @synchronized (strongSelf.tvdbCache) {
                    [strongSelf.tvdbCache setObject:@{
                                                      @"series": kMTVDBMissing,  //mark as "TVDB doesn't have this episode"
                                                      @"possibleIds": seriesIDs,
                                                      @"date":[NSDate date]
                                                      } forKey:show.uniqueID];
                }
                DDLogDetail(@"TVDB doesn't have episodeInfo for %@ on %@ (%@)", show.showTitle, show.originalAirDateNoTime, [self urlsForReporting:seriesIDs]);
            }];
}

-(void) callSeriesIDForShow: (MTTiVoShow *) show withSeriesName: (NSString *) seriesName andSecondCall: (NSString *) secondName {
    //helper routine to allow secondary call to seriesID without having to duplicateCode
    //secondary call necessary to check both seriesName and seriesName w/o a subtitle (e.g. 24: The Lost Weekend)
    __weak typeof(self) weakSelf = self;
    //   void  (^successHandler) ( NSArray<NSString *> *) =
    [self seriesIDForShow:seriesName
        completionHandler: ^(NSArray<NSString *> *seriesIDs) {
            typeof(self) strongSelf = weakSelf;
            [strongSelf cacheTVDBSeriesID:seriesIDs forSeries:seriesName];
            if (show.isEpisodicShow) {
                [strongSelf getEpisodeDetailsForShow:show withIDs:seriesIDs];
            } else {
                [strongSelf incrementStatistic:kMTVDBNonEpisodicSeriesFound];
                //need to get series artwork here  (caching in episode entry) and then call
                @synchronized (self.tvdbCache) {
                    [self.tvdbCache setObject:@{
                                                @"series": seriesIDs[0],
                                                @"date":[NSDate date]
                                                } forKey:show.seriesTitle];
                }
                [strongSelf finishTVDBProcessing:show];
            }
        }

       failureHandler:^{
           typeof(self) strongSelf = weakSelf;
           if (secondName) {
               [strongSelf callSeriesIDForShow:show
                          withSeriesName:secondName
                           andSecondCall:nil];
           } else {
               @synchronized (self.tvdbCache) {
                   [self.tvdbCache setObject:@{
                                               @"series": kMTVDBMissing,  //mark as "TVDB doesn't have this series"
                                               @"date":[NSDate date]
                                               } forKey:  show.seriesTitle ];
               }
               NSString *URL = [NSString stringWithFormat:@"http://thetvdb.com/?string=%@&tab=listseries&function=Search", [show.seriesTitle escapedQueryString]];
               if (show.isEpisodicShow) {
                   [strongSelf addValue: URL   inStatistic: kMTVDBEpisodicSeriesNotFound forShow:show.seriesTitle];
               } else {
                   [strongSelf addValue: URL   inStatistic: kMTVDBNonEpisodicSeriesNotFound forShow:show.seriesTitle];
               }
               DDLogDetail(@"TVDB, no series found for %@", show.seriesTitle);
           }
       }];

}

-(void) reloadTVDBInfo:(MTTiVoShow *) show {
    show.gotTVDBDetails = NO;
    @synchronized (self.tvdbCache) {
        [self.tvdbCache removeObjectForKey:show.uniqueID];
        [self.tvdbCache removeObjectForKey:show.seriesTitle];
        [self cacheTVDBSeriesID:nil forSeries:show.seriesTitle];
    }
    [self getTheTVDBDetails:show];
}

-(void)getTheTVDBDetails: (MTTiVoShow *) show {
    //Needs to get episode info from TVDB
    //1) do possibly multiple lookups at TheTVDB in background to find TVDB's seriesID
    //2) call retrieveTVDBEpisodeInfo in background to get Episode Info
    //3) call finishTVDBProcessing on main thread to augment TiVo's info with theTVDB
    NSAssert ([NSThread isMainThread], @"getTheTVDBDetails running in background");

    if (show.gotTVDBDetails) {
        return;
    }
    [self incrementStatistic: kMTVDBAll ];

    if (show.isMovie) { //no need for movie info, just get the artwork when we download.
        [self incrementStatistic: kMTVDBMovie ];
        __weak typeof(self) weakSelf = self;
        dispatch_async(dispatch_get_global_queue( DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(void){
            typeof(self) strongSelf = weakSelf;
            [strongSelf getTheMovieDBDetailsForShow:show];
        });
        return;
    }
    //if we have a series get the other information
    NSDictionary *episodeEntry;
    @synchronized (self.tvdbCache) {
        episodeEntry = [self.tvdbCache objectForKey:show.uniqueID];
        if (!episodeEntry) {
            episodeEntry = [self.tvdbCache objectForKey:show.seriesTitle];
        }
    }
    if (episodeEntry) { // We already had this information
        show.gotTVDBDetails = YES;
        if ([episodeEntry[@"series"] isEqualToString:kMTVDBMissing]) {
            if (episodeEntry[@"possibleIds"]) {
                NSString *URL = [self urlsForReporting:episodeEntry[@"possibleIds"]];
                [self addValue: URL inStatistic:kMTVDBEpisodeNotFoundCached forShow:show.showTitle  ];
            } else {
                NSString *URL = [NSString stringWithFormat:@"http://thetvdb.com/?string=%@&tab=listseries&function=Search", [show.seriesTitle escapedQueryString]];
                if (!show.isEpisodicShow) {
                    [self addValue: URL inStatistic:kMTVDBNonEpisodicSeriesNotFoundCached forShow:show.showTitle  ];
                } else {
                    [self addValue: URL inStatistic:kMTVDBEpisodicSeriesNotFoundCached forShow:show.showTitle  ];

                }
            }
        } else if (!show.isEpisodicShow) {
             [self incrementStatistic: kMTVDBNonEpisodicSeriesFoundCached ];
        } else {
            [self incrementStatistic: kMTVDBSeriesEpisodeFoundCached];
        }
        [self finishTVDBProcessing:show];
    } else {
        DDLogDetail(@"Need to get %@", show.showTitle);
        NSArray <NSString *> *seriesIDTVDBs = [self cachedTVDBSeriesID:show.seriesTitle ];

        NSArray * splitNameArray = [show.seriesTitle componentsSeparatedByString:@":"];
        NSString * splitName = (splitNameArray.count > 1) ? splitNameArray[0] : nil;

        if (!seriesIDTVDBs.count && splitName) {
            seriesIDTVDBs = [self cachedTVDBSeriesID:splitName];
        }
        if (seriesIDTVDBs.count) {
            // already have series ID, but not this episode info
            if (!show.isEpisodicShow) {
                [self incrementStatistic:kMTVDBNonEpisodicSeriesFoundCached];
                @synchronized (self.tvdbCache) {
                    [self.tvdbCache setObject:@{
                          @"series": seriesIDTVDBs[0],
                          @"date":[NSDate date]
                          } forKey:show.uniqueID];
                }
                [self finishTVDBProcessing:show];
            } else {
                [self getEpisodeDetailsForShow:show withIDs:seriesIDTVDBs];
            }
        } else {
            //first get seriesIDs, then Episode Info
            [self callSeriesIDForShow: show withSeriesName:show.seriesTitle andSecondCall:splitName];
        }
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

    NSNumber *episodeNum = nil, *seasonNum = nil;
    NSString *artwork = nil;
    NSDictionary *episodeEntry;
    @synchronized (self.tvdbCache) {
        episodeEntry = [self.tvdbCache objectForKey:show.uniqueID];
        if (!episodeEntry) episodeEntry = [self.tvdbCache objectForKey:show.seriesTitle];
    }
    if (!episodeEntry) {
        DDLogReport(@"Trying to process missing TVDB data for %@",show.showTitle);
        return;
    }

    if (episodeEntry) { // We already have this information
        episodeNum = [episodeEntry objectForKey:@"episode"];
        if ([episodeNum isKindOfClass:[NSString class]]) {
            episodeNum = @(((NSString *) episodeNum).integerValue);
        }
        seasonNum = [episodeEntry objectForKey:@"season"];
        if ([seasonNum isKindOfClass:[NSString class]]) {
            seasonNum = @(((NSString *) seasonNum).integerValue);
        }
        artwork = [episodeEntry objectForKey:@"artwork"];
        NSArray *seriesIDTVDBs = nil;

        NSString * seriesIDTVDB = [episodeEntry objectForKey:@"series"];
        if (!seriesIDTVDB) {
            DDLogMajor(@"Missing series info in TVDB data for %@: %@",show.showTitle, episodeEntry);
            seriesIDTVDBs =[self cachedTVDBSeriesID:show.seriesTitle];
        }

        show.gotTVDBDetails = YES;
        if (artwork.length+episodeNum.intValue +episodeNum.intValue > 0) {
            //got at least one
            if (artwork.length) {
                show.tvdbArtworkLocation = artwork;
                [self retrieveArtworkIntoFile: [kMTThumbnailsDirectory stringByAppendingPathComponent:artwork] forShow:show cacheVersion:YES];
            }
            DDLogDetail(@"Got episode %@, season %@ and artwork %@ from %@",episodeNum, seasonNum, artwork, show);
       } else {
            NSString * details = [NSString stringWithFormat:@"%@ aired %@ (our  %d/%d) %@ ",[self seriesIDForReporting:show.seriesId ], show.originalAirDateNoTime, show.season, show.episode, [self urlsForReporting:seriesIDTVDBs] ];
            DDLogDetail(@"No series info for %@ %@ ",show.showTitle, details);
        }
        if ([episodeNum intValue] > 0) {  //season 0 = specials on theTVDB
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

                    if (YES) {//([[NSUserDefaults standardUserDefaults] boolForKey:kMTTrustTVDB]) {
                        //user asked us to prefer TVDB
                        [self updateSeason: [seasonNum intValue] andEpisode: [episodeNum intValue]forShow:show];
                    }
                }
            } else {
                [self updateSeason: [seasonNum intValue] andEpisode: [episodeNum intValue] forShow:show];
                DDLogVerbose(@"Adding TVDB season/episode %d/%d to show %@",show.season, show.episode, show.showTitle);
            }
        }
    } else {
        show.gotTVDBDetails = YES; //never going to find it
    }
}

-(BOOL) isActive {
    return NO;  //FIX **** XXXXXX self.tvdbQueue.operationCount > 1;  ??
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
        if (([artwork isKindOfClass:[NSNull class]])) {
            return nil;
        }
        if (!([artwork isKindOfClass:[NSString class]])) {
            DDLogMajor(@"theMovieDB returned invalid JSON format: poster_path is invalid : %@", movie);
            return kFormatError;
        }
        DDLogMajor(@"theMovieDB success : %@ = %@", movie, artwork);

        return artwork;
    } else {
        return nil;
    }
}

-(void) getTheMovieDBDetailsForShow: (MTTiVoShow *) show {
    NSAssert (![NSThread isMainThread], @"getTheMovieDBDetailsForShow running in foreground");

    if (show.gotTVDBDetails) return;
    //we only get artwork

    NSString * cachedArt = [self cachedArtWorkForShow:show.seriesTitle];
    if (cachedArt.length > 0) {
        show.artworkFile = cachedArt;
        show.gotTVDBDetails = YES;
        [self incrementStatistic:kMTVDBMovieFoundCached];
        return;
    }
    @synchronized (self.movieDBRateLimitLock) {
        DDLogDetail(@"themovieDB %ld, Entering  =  %@ at %@", (long)self.movieDBRateLimitCalls, show, self.movieDBRateLimitEnd);

        self.movieDBRateLimitCalls ++;
        NSTimeInterval delay = [self.movieDBRateLimitEnd timeIntervalSinceNow];

        if (delay > 0 && self.movieDBRateLimitCalls >= 40) {
            DDLogDetail(@"For Show: %@, theMovieDB sleeping %f", show, delay);
            usleep (delay*1000000);
            DDLogDetail(@"For Show: %@, theMovieDB awaking", show);
            delay = 0;
        }

        if (!self.movieDBRateLimitEnd || delay <= 0) {
            self.movieDBRateLimitEnd = [NSDate dateWithTimeIntervalSinceNow:11];
            self.movieDBRateLimitCalls = 1; //this one
        }
        DDLogDetail(@"themovieDB %ld, Exiting %@ at %@", (long)self.movieDBRateLimitCalls, show, self.movieDBRateLimitEnd);
    }
    NSString * searchString = [show.seriesTitle escapedQueryString];
    NSString * urlString = [NSString stringWithFormat:@"https://api.themoviedb.org/3/search/movie?query=%@&api_key=%@",
                             searchString, kMTTheMoviedDBAPIKey];
    NSString * reportURL = [urlString stringByReplacingOccurrencesOfString:kMTTheMoviedDBAPIKey withString:@"APIKEY" ];
    NSString * lookupURL = [@"https://www.themoviedb.org/search?query=" stringByAppendingString:searchString];

    DDLogDetail(@"Getting movie Data for %@ using %@", show, reportURL);
    NSURL *url = [NSURL URLWithString:urlString];
    NSError * error = nil;
    NSData *movieInfo = [NSData dataWithContentsOfURL:url options:NSDataReadingUncached error:&error];
    if (!movieInfo || error) {
        if ([error.localizedDescription isEqualToString:@"The file “movie” couldn’t be opened."]) {
            DDLogReport(@"On %@, hit theMovieDB Rate Limit; please report to cTiVo support site", show);
        } else {
            DDLogMajor(@"For %@, theMovieDB returned %@", show, error.localizedDescription ? [@"error: " stringByAppendingString:error.localizedDescription] : @"no information");
        }
        [self addValue:urlString inStatistic:kMTVDBMovieNotFound forShow:show.seriesTitle];
        return;
    }
    show.gotTVDBDetails = YES;

    error = nil;
    NSDictionary *topLevel = [NSJSONSerialization
                              JSONObjectWithData:movieInfo
                              options:0
                              error:&error];
    if (!topLevel || error) {
        DDLogMajor(@"For &@, theMovieDB returned invalid JSON format: %@ Data: %@",error.localizedDescription, movieInfo);
        [self addValue:lookupURL inStatistic:kMTVDBMovieNotFound forShow:show.seriesTitle];
        return;
    }
    if(![topLevel isKindOfClass:[NSDictionary class]]) {
        DDLogMajor(@"For &@, theMovieDB returned invalid JSON format:Top Level is not a dictionary; Data: %@", movieInfo);
        [self addValue:lookupURL inStatistic:kMTVDBMovieNotFound forShow:show.seriesTitle];
        return;
    }
    NSArray * results = topLevel[@"results"];
    if(![results isKindOfClass:[NSArray class]]) {
        DDLogMajor(@"For &@, theMovieDB returned invalid JSON format: Results not an array; Data: %@", movieInfo);
        [self addValue:lookupURL inStatistic:kMTVDBMovieNotFound forShow:show.seriesTitle];
        return;
    }
    if (results.count == 0) {
        DDLogMajor(@"theMovieDB couldn't find any movies named %@", show.seriesTitle);
        [self addValue:lookupURL inStatistic:kMTVDBMovieNotFound forShow:show.seriesTitle];
        return;
    }
    NSString * newArtwork = nil;
    for (NSDictionary * movie in results) {
        //look for a perfect title/release match
        NSString * location = [self checkMovie:movie exact:YES forShow:show];
        if (location.length && ![kFormatError isEqualToString:location]) {
            newArtwork = location;
            break;
        }
    }
    if (!newArtwork) {
        for (NSDictionary * movie in results) {
            // return first that matches either title or release year
            NSString * location = [self checkMovie:movie exact:NO forShow:show];
            if (location && ![kFormatError isEqualToString:location]) {
                newArtwork = location;
                break;
            }
        }
    }
    if (newArtwork.length > 0 ) {
        show.tvdbArtworkLocation = newArtwork;
        [self incrementStatistic:kMTVDBMovieFound];
        [self cacheArtWork:newArtwork forShow:show.seriesTitle];
    } else {
        DDLogMajor(@"theMovieDB doesn't have any images for %@", show.seriesTitle);
        [self addValue:lookupURL inStatistic:kMTVDBMovieNotFound forShow:show.seriesTitle];
    }
}

-(void)retrieveArtworkIntoFile: (NSString *) filename forShow: (MTTiVoShow *) show cacheVersion: (BOOL) cache
{
    if(!show.gotTVDBDetails && show.isMovie) {
        //we don't get movie data upfront, so go get it now, but call us back when you have it
        __weak typeof(self) weakSelf = self;
        dispatch_async(dispatch_get_global_queue( DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(void){
            typeof(self) strongSelf = weakSelf;
            [strongSelf getTheMovieDBDetailsForShow:show];
            dispatch_async(dispatch_get_main_queue(), ^(void){
                [strongSelf retrieveArtworkIntoFile:filename forShow:show cacheVersion:cache];
            });
        });
        return;
    }
    NSString *artLocation = show.tvdbArtworkLocation;
    if (artLocation.length == 0) {

    }
    if (show.tvdbArtworkLocation.length == 0) {
        return;
    }

    NSString *baseUrlString;
    if (show.isMovie) {
        if (cache) {
            baseUrlString = @"http://image.tmdb.org/t/p/w92%@";
        } else {
            baseUrlString = @"http://image.tmdb.org/t/p/w780%@";
        }
    } else {
        if (cache) {
            baseUrlString = @"http://thetvdb.com/_cache/%@";
        } else {
            baseUrlString = @"http://thetvdb.com/%@";
        }
    }
    NSString *urlString = [NSString stringWithFormat: baseUrlString, show.tvdbArtworkLocation ];
    //download only if we don't have it already
    if (![[NSFileManager defaultManager] fileExistsAtPath:filename]) {
        DDLogDetail(@"downloading artwork at %@ to %@",urlString, filename);
        NSURLRequest *req = [NSURLRequest requestWithURL:[NSURL URLWithString:urlString]];
        [NSURLConnection sendAsynchronousRequest:req queue:[NSOperationQueue mainQueue] completionHandler:^(NSURLResponse *response, NSData *data, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^(void){
               if (!data || error ) {
                    DDLogReport(@"Couldn't get artwork for %@ from %@ , Error: %@", show.seriesTitle, urlString, error.localizedDescription);
                    show.tvdbArtworkLocation = nil;
                } else {
                    if ( data.length < 3000) {  //too short for a real image
                        NSString * htmlString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                        if ([htmlString contains:@"404 Not Found"]) {
                            //file not found in html
                            DDLogDetail(@"No artwork for %@ from %@ ", show.seriesTitle, urlString);
                            show.tvdbArtworkLocation = nil;
                            // [self removeArtwork:show.episodeID]; FIX
    //                        [self searchArtwork]
    //                        https://api.thetvdb.com/series/281470/images/query/params
                            return;
                        }
                    }
                    if ([data writeToFile:filename atomically:YES]) {
                        show.artworkFile = filename;
                        DDLogDetail(@"Saved artwork file for %@ at %@",show.showTitle, filename);
                    } else {
                        DDLogReport(@"Couldn't write to artwork file %@", filename);
                    }
                }
            });
        }];
    }
}

@end
