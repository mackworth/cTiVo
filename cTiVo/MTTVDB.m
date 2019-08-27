//
//  MTTVDBManager.m
//  cTiVo
//
//  Created by Hugh Mackworth on 6/30/17.
//  Copyright © 2017 cTiVo. All rights reserved.
//
#import "MTTVDB.h"

#import "NSString+Helpers.h"
#import "NSString+HTML.h"
#import "DDLog.h"

@interface MTTVDB ()
    @property (atomic, strong) NSString * tvdbToken;
    @property (atomic, strong) NSDate * tvdbTokenExpireTime;
    @property (atomic, strong) NSURLSession * tvdbURLSession;

    @property (atomic, strong) NSMutableDictionary *tvdbCache;
        //Remembering info from tvdb (and moviedb).
        //key is show's episodeId
        //series: series number (or "unknown")
        //artwork: URL fragment for art
        //artwork: URL fragment for art
        //artwork: URL fragment for art
        //date: last used timestamp to allow expiration
    @property (atomic, strong) NSMutableDictionary <NSString *, NSArray <NSString *> *> *tvdbSeriesIdMapping;
    @property (atomic, strong) NSMutableDictionary * theTVDBStatistics;

    @property (atomic, strong) NSDate * movieDBRateLimitEnd;
    @property (atomic, strong) NSNumber * movieDBRateLimitLock; //just used to lock other calls
    @property (atomic, assign) NSInteger movieDBRateLimitCalls;
	@property (atomic, strong) NSDate * failWaitUntilTime;
@end

@implementation MTTVDB

__DDLOGHERE__
@synthesize  tvdbURLSession = _tvdbURLSession;

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
    [[NSUserDefaults standardUserDefaults] setObject:nil forKey:kMTTheTVDBCache];
    [[NSUserDefaults standardUserDefaults] synchronize];
    self.tvdbSeriesIdMapping = [NSMutableDictionary dictionaryWithCapacity:self.tvdbSeriesIdMapping.count];
    self.theTVDBStatistics = [NSMutableDictionary dictionary];
    self.tvdbCache = [NSMutableDictionary dictionaryWithCapacity:self.tvdbCache.count];
}

#pragma mark -
#pragma mark HTTP sessions for TVDB

-(void) cancelSession {
    if (self.tvdbURLSession) DDLogReport(@"canceling TVDB Session");
    [self.tvdbURLSession invalidateAndCancel];
    self.tvdbURLSession = nil;
    [self checkToken];
}

-(NSURLSession *) tvdbURLSession {
	@synchronized (self) {
		if (_tvdbURLSession) return _tvdbURLSession;
		self.tvdbToken = nil;
		if ([self.failWaitUntilTime timeIntervalSinceNow] >  0) {
			DDLogDetail(@"Still waiting for to try TVDB again");
			return nil;
		}
	}
	NSURLSession * session = nil;
	DDLogReport(@"Establishing Session");
	
	if (![self checkToken]) {
		DDLogMajor(@"Still checking for TVDB token");
		usleep(250000);   //XXX FIX: pausing for a quarter-second on main queue is not good
		[self checkToken];
	}
	if (self.tvdbToken) {
		NSURLSessionConfiguration * config = [NSURLSessionConfiguration defaultSessionConfiguration];
		config.HTTPAdditionalHeaders = @{@"Accept": @"application/json",
										 @"Content-Type": @"application/json",
										 @"Authorization": [NSString stringWithFormat:@"Bearer %@",self.tvdbToken]};
		session = [NSURLSession sessionWithConfiguration:config];
		self.tvdbURLSession = session;
	} else {
		DDLogReport(@"Cannot establish session with TVDB");
		if (self.failWaitUntilTime) {
			self.failWaitUntilTime = [NSDate dateWithTimeIntervalSinceNow:60*10]; //try in 10 minutes
		} else {
			self.failWaitUntilTime = [NSDate dateWithTimeIntervalSinceNow:30]; //retry in 30 seconds
		}
	}
	
	return session;
}

-(void) setTvdbURLSession:(NSURLSession *)tvdbURLSession {
    @synchronized (self) {
        _tvdbURLSession = tvdbURLSession;
    }
}

static BOOL inProgress = NO;

-(BOOL) checkToken {
    @synchronized (self) {
        if (self.tvdbToken && [self.tvdbTokenExpireTime compare:[NSDate date]] == NSOrderedDescending) {
            return YES;
        } else if (inProgress) {
            return NO;
        } else {
            inProgress = YES;
        }
    }
    //don't have a token or it's expired
    self.tvdbToken = nil;

    NSURLSessionConfiguration *sessionConfiguration = [NSURLSessionConfiguration defaultSessionConfiguration];
    sessionConfiguration.HTTPAdditionalHeaders = @{@"Accept": @"application/json"};
    sessionConfiguration.HTTPAdditionalHeaders = @{@"Content-Type": @"application/json"};

    NSURLSession *session = [NSURLSession sessionWithConfiguration:sessionConfiguration];

    NSString *tokenURL = @"https://api.thetvdb.com/login";
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:tokenURL]];
    request.HTTPMethod = @"POST";
    NSString * body = @"{\"apikey\": \"" kMTTheTVDBAPIKey "\"}";
    request.HTTPBody = [body dataUsingEncoding:NSUTF8StringEncoding];
    NSDate * tokenExpiration = [NSDate dateWithTimeIntervalSinceNow:24*60*60];
	__weak __typeof__(self) weakSelf = self;

    NSURLSessionDataTask *task = [session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
		__typeof__(self) strongSelf = weakSelf;
		if (!strongSelf) return;
        if (error) {
			DDLogReport(@"Error %@ communicating with TVDB for token", error);
		} else {
            NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
            if (httpResponse.statusCode == 200){
                NSError * jsonError;
                NSDictionary *jsonData = [NSJSONSerialization JSONObjectWithData:data options: 0 error: &jsonError];
                if (!jsonError || ![jsonData isKindOfClass:[NSDictionary class]]) {
                    NSString * token = jsonData[@"token"];
                    if (token.length) {
                        strongSelf.tvdbToken = token;
                        strongSelf.tvdbTokenExpireTime = tokenExpiration;
                        DDLogDetail(@"Got TVDB token: %@", token);
                    } else {
                        DDLogReport(@"NO Token?? %@", jsonData);
                    }
                } else {
                    DDLogReport(@"TVDB Token JSON parsing Error: %@", data);
                }
            } else {
                DDLogReport(@"TVDB Token HTTP Response Error %ld: %@, %@", (long)httpResponse.statusCode,  [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding], httpResponse.URL );
                [strongSelf cancelSession];
			}
		}
		@synchronized (strongSelf) {
			inProgress = NO;
		}
    }];
    DDLogDetail(@"requesting token: %@", tokenURL);
    [task resume];
    return NO; //no token available right now
}


-(void) seriesIDForShow: (NSString *) series
      completionHandler: (void(^) (NSArray <NSString *> *seriesIDs)) completionBlock
         failureHandler: (void(^) (void)) failureBlock {
    NSAssert ([NSThread isMainThread], @"seriesIDForShow running in background");

    NSURL *seriesURL = [NSURL URLWithString: [NSString stringWithFormat:@"https://api.thetvdb.com/search/series?name=%@",[series escapedQueryString]] ];
    DDLogDetail(@"search for seriesID for %@ at %@",series, seriesURL);
	__weak __typeof__(self) weakSelf = self;
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
                                        if ([series isEqual:seriesName] ||
                                             [series isEqual:seriesNameNoYear]) {
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
            } else if (httpResponse.statusCode == 404) {
                DDLogVerbose(@"TVDB Series %@ not found at %@" , series, seriesURL );
			} else if (httpResponse.statusCode == 522) {
				DDLogReport(@"TVDB Connection Timed out at %@!" , seriesURL );
			} else if (httpResponse.statusCode == 520) {
				DDLogReport(@"TVDB Connection had a Bad Gateway error at %@!" , seriesURL );
			} else {
                DDLogReport(@"TVDB Series HTTP Response Error %ld: %@, %@ for %@", (long)httpResponse.statusCode, [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding], httpResponse.URL, series );
                [weakSelf cancelSession];
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
                     orSeason: (NSInteger) season
                   andEpisode: (NSInteger) episode
                     inSeries: (NSArray <NSString *> *) seriesIDs
            completionHandler: (void(^) (NSString * seriesID, NSDictionary * episodeInfo)) completionBlock
               failureHandler: (void(^) (void)) failureBlock
                   pageNumber: (NSInteger) pageNumber
{
    //Could be in either background or foreground
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
    if (pageNumber ==0 ) {
        DDLogDetail(@"Looking for episode %@ at: %@", episodeName, episodeURL);
    }
	__weak __typeof__(self) weakSelf = self;
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
                                    if ([episodeDict[@"airedEpisodeNumber"] isEqual: @ (episode) ] &&
                                         [episodeDict[@"airedSeason"] isEqual: @(season)]) {
                                             if (completionBlock) {
                                                 dispatch_async(dispatch_get_main_queue(), ^{
                                                     completionBlock(seriesID, episodeDict);
                                                 });
                                             }
                                             return; // found exact match, so no more processing.

                                    } else {
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
                                    }
                                } else {
                                    DDLogReport(@"TVDB Episode JSON type Error (should be dictionary): %@ for %@", episodeDict, seriesID);
                                }
                            }
                        } else {
                            DDLogReport(@"TVDB Episode JSON type Error (should be Array): %@ for %@", episodeList, seriesID);
                        }
                    } else {
                        DDLogDetail(@"TVDB error for %@: %@", seriesID, jsonData[@"error"]);
                    }
                } else {
                    DDLogReport(@"TVDB Episode JSON parsing Error: %@ for %@",  [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding], seriesID);
                }
            } else if (httpResponse.statusCode == 404){
                DDLogVerbose(@"TVDB episode %@ in series %@ not found on page %@", episodeName, seriesID, @(pageNumber));
            } else {
                DDLogReport(@"TVDB Episode HTTP Response Error %ld: %@, %@ fr %@", (long)httpResponse.statusCode,  [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding], httpResponse.URL, seriesID );
                [weakSelf cancelSession];
           }
        } else {
            DDLogReport(@"TVDB Episode Call Error %@: for %@", error.localizedFailureReason, episodeURL );
        }

        //so this one didn't work; let's try the next one, either next page or next seriesID
        if ([nextPage isKindOfClass: NSNumber.class] && nextPage.integerValue > 0) {
            [weakSelf searchForEpisodeNamed: episodeName
                               orSeason: season
                             andEpisode: episode
                               inSeries: seriesIDs
                      completionHandler: completionBlock
                         failureHandler: failureBlock
                             pageNumber: nextPage.integerValue];
        } else if (seriesIDs.count <= 1) {
            //no more candidates, so we failed.
            if (failureBlock) dispatch_async(dispatch_get_main_queue(),failureBlock);
        } else {
            NSArray * restSeriesIDs =    [seriesIDs subarrayWithRange:NSMakeRange(1, seriesIDs.count - 1)];
            [weakSelf searchForEpisodeNamed: episodeName
                               orSeason: season
                             andEpisode: episode
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
                   orSeason: (NSInteger) season
                 andEpisode: (NSInteger) episode
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
     DDLogVerbose(@"looking for episode %@ at %@",episodeName, episodeURL);
	 __weak __typeof__(self) weakSelf = self;
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
                                        } else if (episode > 0) {
                                            //check for exact episode match
                                            NSNumber * tvdbEpisode = episodeDict[@"airedEpisodeNumber"];
                                            NSNumber * tvdbSeason = episodeDict[@"airedSeason"];
                                            if ([tvdbSeason isKindOfClass:[NSNumber class]] &&
                                                [tvdbEpisode isKindOfClass:[NSNumber class]]) {
                                                if (tvdbEpisode.integerValue == episode && tvdbSeason.integerValue == season ){
                                                    if (completionBlock) {
                                                        dispatch_async(dispatch_get_main_queue(), ^{
                                                            completionBlock(seriesID, episodeDict);
                                                        });
                                                    }
                                                    return; // found exact episode match, so no more processing.
                                                }
                                            } else {
                                                DDLogReport(@"TVDB Episode JSON type Error ('airedEpisodeNumber and airedSeason' should be Numbers). For %@ on %@ tvdb has %@",  seriesID, originalAirDate,episodeDict);
                                            }
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
                        DDLogDetail(@"TVDB error for %@: %@", seriesID, jsonData[@"error"]);
                    }
                } else {
                    DDLogReport(@"TVDB Episode JSON parsing Error: %@ for %@",  [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding], seriesID);
                }
            } else if (httpResponse.statusCode == 404){
                DDLogVerbose(@"TVDB episode %@ in series %@ not found on %@", episodeName, seriesID, originalAirDate);
            } else {
                DDLogReport(@"TVDB Episode HTTP Response Error %ld: %@, %@ fr %@", (long)httpResponse.statusCode,  [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding], httpResponse.URL, seriesID );
                [weakSelf cancelSession];
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
            [weakSelf infoForEpisodeNamed:episodeName
                             orSeason: season
                           andEpisode: episode
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
                   orSeason: (NSInteger) season
                 andEpisode: (NSInteger) episode
                   inSeries: (NSArray <NSString *> *) seriesIDs
                  onAirDate: (NSString *) originalAirDate
          completionHandler: (void(^) (NSString * seriesID, NSDictionary * episodeInfo)) completionBlock
             failureHandler: (void(^) (void)) failureBlock {
    //look for first episode that has the original airdate, and whose name matches episodeName.
    //if none, then use first episode with original airdate
    //then call completionBlock to hand values back to original caller.
    //use recursion to index across seriesIDs
	__weak __typeof__(self) weakSelf = self;
    [self infoForEpisodeNamed:episodeName
                     orSeason: season
                   andEpisode: episode
                    inSeries:seriesIDs
                    onAirDate:originalAirDate
            completionHandler:completionBlock
               failureHandler:^{
                   //so no episodes with exact air date, let's find one with exact name match instead
                   if (episodeName.length) {
                       [weakSelf searchForEpisodeNamed: episodeName
                                          orSeason: season
                                        andEpisode: episode
                                      inSeries: seriesIDs
                             completionHandler: completionBlock
                                failureHandler: failureBlock
                                    pageNumber: 1];
                   } else {
                       if (failureBlock) {
                           dispatch_async(dispatch_get_main_queue(),failureBlock);
                       }
                   }
               }
        withSeriesIDCandidate:nil
          andEpisodeCandidate:nil];
}

-(void) searchSeriesArtwork:(MTTiVoShow *) show
                    artType:(NSString *) artType
          completionHandler: (void(^) (NSString *filename)) completionBlock
             failureHandler: (void(^) (void)) failureBlock {
    if (!artType) artType = @"fanart";
    NSString * seriesID = [self cachedSeriesIDForShow:show];

    if (!seriesID) {
        DDLogReport(@"Looking for show %@ with no ID?", show);
        if (failureBlock) {
            dispatch_async(dispatch_get_main_queue(),failureBlock);
        }
        return;
    }
    NSURL *imageURL = [NSURL URLWithString: [NSString stringWithFormat:@"https://api.thetvdb.com/series/%@/images/query?keyType=%@",seriesID, artType]];
	__weak __typeof__(self) weakSelf = self;
  	NSURLSessionDataTask *task = [self.tvdbURLSession dataTaskWithURL:imageURL completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        float bestRating = 0.0;
        float bestTextRating = 0.0;
        NSString * bestFile = nil;
        NSString * bestTextFile = nil;
        //look for the highest rated image, preferably a "text" file
        if (!error) {
            NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
            if (httpResponse.statusCode == 200){
                NSError * jsonError;
                NSDictionary *jsonData = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingAllowFragments error: &jsonError];
                if (!jsonError && [jsonData isKindOfClass:[NSDictionary class]]) {
                    if (!jsonData[@"error"]) {
                        DDLogVerbose(@"TVDB SeriesImage JSON: %@", jsonData);
                        NSArray * imageList = jsonData[@"data"];
                        if ([imageList isKindOfClass:[NSArray class]]) {
                            for (NSDictionary * imageDict in imageList) {
                                if ([imageDict                 isKindOfClass:[NSDictionary class]] &&
                                    [imageDict[@"fileName"]    isKindOfClass:[NSString class]] &&
                                    [imageDict[@"ratingsInfo"] isKindOfClass:[NSDictionary class]]) {
                                    NSNumber * average = imageDict[@"ratingsInfo"][@"average"];

                                    if ([average isKindOfClass:[NSNumber class]]){
                                        if (average.floatValue > bestRating || !bestFile) {
                                            bestRating = average.floatValue;
                                            bestFile = imageDict[@"fileName"];
                                        }
                                        if ([imageDict[@"subKey"] isEqualToString:@"text"] &&
                                            (average.floatValue > bestTextRating || !bestTextFile)) {
                                            bestTextRating = average.floatValue;
                                            bestTextFile = imageDict[@"fileName"];
                                        }
                                    } else {
                                        DDLogReport(@"TVDB Image JSON type Error ('average' should be Number). For %@ on %@ tvdb has %@",  show, seriesID, imageDict);
                                    }
                                } else {
                                    DDLogReport(@"TVDB Image JSON dictionarytype Error . For %@ on %@ tvdb has %@",  show, seriesID, imageDict);
                                }
                            }
                        } else {
                            DDLogReport(@"TVDB Image JSON type Error (should be Array): For %@ on %@ tvdb has %@",  show, seriesID, imageList);
                        }
                    } else {
                        DDLogDetail(@"TVDB error for %@, %@: %@ at %@", show, seriesID, jsonData[@"error"], imageURL);
                    }
                } else {
                    DDLogReport(@"TVDB Episode JSON parsing Error: %@  (%@) for %@",  [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding], jsonError.localizedDescription, seriesID );
                }
            } else if (httpResponse.statusCode == 404 || httpResponse.statusCode == 500){
                DDLogDetail(@"TVDB %@ images not found for show %@ in series %@ at %@", artType, show, seriesID, imageURL);
                if ([artType isEqualToString:@"fanart"]) {
                    //well, if at first you don't ...
                    [weakSelf searchSeriesArtwork:show
                                      artType:@"poster"
                            completionHandler:completionBlock
                               failureHandler:failureBlock];
                    return;
                }
            } else {
                DDLogReport(@"TVDB Episode HTTP Response Error %ld: %@, %@ from %@", (long)httpResponse.statusCode,  [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding], httpResponse.URL, seriesID );
                [weakSelf cancelSession];
            }
        } else {
            DDLogReport(@"TVDB Episode Call Error %@: for %@", error.localizedFailureReason, imageURL );

        }
        if (bestTextFile) {
            if (bestTextRating >= bestRating /2) {
                //so if text version is within half the rating of the best graphical, then use it
                bestFile = bestTextFile;
            }
        }
        if (bestFile) {
            if (completionBlock) {
              dispatch_async(dispatch_get_main_queue(), ^{
                  completionBlock( bestFile );
              });
            }
        } else {
            DDLogDetail(@"No Images for %@: at %@ for %@", show, seriesID, imageURL );
            if (failureBlock) {
                dispatch_async(dispatch_get_main_queue(),failureBlock);
            }
        }
        }];
    DDLogDetail(@"searching Series Image for show %@ in TVDB %@ : %@", show, imageURL, seriesID);
    [task resume];

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

-(NSString *) urlsForReporting:(NSArray <NSString *> *) tvdbIDs {
    if (tvdbIDs.count > 1 && [tvdbIDs[0] isEqualToString:kMTVDBMissing]){
        return kMTVDBMissing;
    }
    NSMutableArray * urls = [NSMutableArray arrayWithCapacity:tvdbIDs.count];
    for (NSString * tvdbID in tvdbIDs) {
        NSString * showURL = [NSString stringWithFormat:@"http://thetvdb.com/?tab=seasonall&id=%@&lid=7",tvdbID];
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
    @"\n" kcTiVoName @" looks up the TiVo's shows on theTVDB and the movies on theMovieDB.\n"
    "You can click on the individual URLs to see what information is available for shows that could not be found.\n\n"
    "Total number of shows is %lu\n"
    "%lu shows are marked as Movies\n"
    "%lu shows are marked as Episodic\n"
    "%lu shows are marked as Non-Episodic (e.g. news/sports events)\n"
    "\n" kcTiVoName @" caches information as possible; successful lookups for 30 days; unsuccessful for 1 day\n"
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

//TVDBCache keys
#define kTVDBDateKey    @"date" //NSDate when this record was created (used to expire old ones)

-(void) cleanCache {
    @synchronized (self.tvdbCache) {    //Clean up old entries
        NSMutableArray *keysToDelete = [NSMutableArray array];
        for (NSString *key in self.tvdbCache) {
            NSDictionary * episodeInfo = [self.tvdbCache objectForKey:key];
            NSDate *createDate = episodeInfo[kTVDBDateKey];
            if (!createDate) continue; //protective only
            NSInteger numDays = 30;
            if ([episodeInfo[kTVDBSeriesKey] isEqualToString:kMTVDBMissing]) {
                numDays = 1;
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

-(NSDictionary *) cacheArtWork: (NSString *) newArtwork forKey: (NSString *) key forShow: (MTTiVoShow *) show {
    if ( show.episodeID.length== 0) return nil;  //protective only
    if (!key) return nil;
    NSDictionary * returnDict = nil;
    @synchronized (self.tvdbCache) {
       NSMutableDictionary * oldEntry = [[self.tvdbCache objectForKey:show.episodeID] mutableCopy];
        if (newArtwork) {
            if (!oldEntry ) {
                oldEntry = [NSMutableDictionary dictionaryWithObject: [NSDate date] forKey:kTVDBDateKey];
            }
            [oldEntry setObject:newArtwork forKey:key];
        } else {
            if (!oldEntry) return nil;
            [oldEntry removeObjectForKey:key];
        }
        returnDict = [oldEntry copy];
        [self.tvdbCache setObject:returnDict
                           forKey:show.episodeID];
    }
    return returnDict;
}

-(NSString *) cachedArtWork: (NSString *) key forShow: (MTTiVoShow *) show {
    if ( show.episodeID.length == 0) return nil; //protective only
    @synchronized (self.tvdbCache) {
        NSDictionary * entry = [self.tvdbCache objectForKey:show.episodeID];
        return entry[key];
    }
}

-(void) resetTVDBInfo:(MTTiVoShow *) show {
    show.tvdbData = nil;
    @synchronized (self.tvdbCache) {
        if (show.episodeID) [self.tvdbCache removeObjectForKey:show.episodeID];
        if (show.seriesTitle) [self.tvdbCache removeObjectForKey:show.seriesTitle];
        [self cacheTVDBSeriesID:nil forSeries:show.seriesTitle];
    }
}

-(void) cache: (NSDictionary <NSString *, id> *) value forShow: (MTTiVoShow *) show {
    if (!show.episodeID) return;
    NSMutableDictionary * newValue = [value mutableCopy];

    newValue[kTVDBDateKey ] = [NSDate date];

    NSString * seriesIDTVDB = value [kTVDBSeriesKey];
    NSArray <NSString *> * seriesIDs = nil;  //just for reporting

    if (seriesIDTVDB) {
        seriesIDs = @[seriesIDTVDB];
    } else {
        DDLogDetail(@"Missing series info in TVDB data for %@: %@",show.showTitle, value);
        seriesIDs = [self cachedTVDBSeriesID:show.seriesTitle];
    }
    if (![seriesIDTVDB isEqualToString:kMTVDBMissing ]) {
        newValue[kTVDBURLsKey] = [self urlsForReporting:seriesIDs];
    }

    @synchronized (self.tvdbCache) {
       [self.tvdbCache setObject:[newValue copy] forKey:show.episodeID];
    }
}

-(NSDictionary <NSString *, id> *) getCacheForShow: (MTTiVoShow *) show {
    @synchronized (self.tvdbCache) {
        return [self.tvdbCache objectForKey:show.episodeID];
    }
}

//tvdbSeriesIdMapping is rebuilt each run only to remember seriesIDs across multiple episodes
//picked up from either tvdbcached episodes or from accessing tvdb
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

-(NSArray <NSString *> *) seriesIDsForShow: (MTTiVoShow *) show {
    //all possible seriesIDs at tvdb
    NSArray <NSString *> * seriesIDs = [self cachedTVDBSeriesID:show.seriesTitle]; // see if we've already done this
    if (!seriesIDs) {
        @synchronized (self.tvdbCache) {
            NSDictionary *TVDBepisodeEntry = [self.tvdbCache objectForKey:show.episodeID];
            NSString * seriesID = [TVDBepisodeEntry objectForKey:kTVDBSeriesKey];
            if ([kMTVDBMissing isEqual:seriesID] ) {
                seriesIDs = @[];
            } else if (seriesID) {
                seriesIDs = @[seriesID];
            } else {
                seriesIDs = nil;
            }
        };
    }
    return seriesIDs;
}

-(NSString *) cachedSeriesIDForShow: (MTTiVoShow *) show {
    NSString * seriesID = [self getCacheForShow:show][kTVDBSeriesKey];
    if (!seriesID) {
        NSArray <NSString *> * ids = [self cachedTVDBSeriesID:show.seriesTitle];
        if (ids.count > 0) {
            seriesID = ids[0];
        } else {
            NSArray * splitNameArray = [show.seriesTitle componentsSeparatedByString:@":"];
            NSString * splitName = (splitNameArray.count > 1) ? splitNameArray[0] : nil;

            if (splitName) {
                ids = [self cachedTVDBSeriesID:splitName];
                if (ids.count > 0) {
                    seriesID = ids[0];
                }
            }
        }
    }
    return seriesID;
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
    NSInteger searchSeason = 0;
    NSInteger searchEpisode = 0;
    if (show.manualSeasonInfo) {
        searchSeason = show.season;
        searchEpisode = show.episode;
    }
    [self infoForEpisodeNamed: show.episodeTitle
                     orSeason: searchSeason
                   andEpisode: searchEpisode
                     inSeries: seriesIDs
                    onAirDate: show.originalAirDateNoTime
            completionHandler:^(NSString *seriesID, NSDictionary *episodeInfo ) {
                typeof(self) strongSelf = weakSelf;

                if ([strongSelf checkType:@"airedSeason" inDict:episodeInfo] &&
                    [strongSelf checkType:@"airedEpisodeNumber" inDict:episodeInfo] &&
                    [strongSelf checkType:@"id" inDict:episodeInfo]) {
                    //episode artwork is calculated, not retrieved, so might as well always do it.
                    NSString * artworkLocation = [NSString stringWithFormat:@"episodes/%@/%@.jpg",seriesID, episodeInfo[@"id"]];
                    DDLogDetail(@"TVDB Artwork for %@ at %@",show, artworkLocation);
                    [strongSelf incrementStatistic:kMTVDBSeriesEpisodeFound];
                    NSNumber * season = episodeInfo[@"airedSeason"];
                    NSNumber * episode = episodeInfo[@"airedEpisodeNumber"];
                    [strongSelf cache: @{
                                kTVDBSeasonKey:  season.description,
                                kTVDBEpisodeKey: episode.description,
                                kTVDBEpisodeArtworkKey: artworkLocation,
                                kTVDBSeriesKey:  seriesID,
                                kTVDBDateKey:    [NSDate date]
                                } forShow: show];
                    //remember the one that worked, forget all the others
                    [self cacheTVDBSeriesID:@[seriesID] forSeries:show.seriesTitle];

                    DDLogVerbose(@"Got TVDB episodeInfo for %@: %@", show.showTitle, episodeInfo);
                    [strongSelf finishTVDBProcessing:show ];
              } else {
                  DDLogReport(@"TVDB Failure for %@; missing Season, Episode or id: %@", [self urlsForReporting:@[seriesID]],episodeInfo);
              }
            } failureHandler:^(){
                typeof(self) strongSelf = weakSelf;
                [strongSelf addValue:[NSString stringWithFormat:@"Date: %@, URLs:%@",show.originalAirDateNoTime, [self urlsForReporting:seriesIDs]] inStatistic:kMTVDBEpisodeNotFound forShow:show.showTitle];
                [strongSelf cache:@{
                              kTVDBSeriesKey:      kMTVDBMissing,  //mark as "TVDB doesn't have this episode"
                              kTVDBEpisodeArtworkKey:     @"",
                              kTVDBSeasonArtworkKey:     @"",
                              kTVDBSeriesArtworkKey:     @"",
                              kTVDBPossibleIDsKey: seriesIDs,  //the ones we checked
                              kTVDBDateKey:        [NSDate date]
                              } forShow: show];
                DDLogDetail(@"TVDB doesn't have episodeInfo for %@ on %@ (%@)", show.showTitle, show.originalAirDateNoTime, [self urlsForReporting:seriesIDs]);
                [strongSelf finishTVDBProcessing:show ];
            }];
}

-(void) getNonEpisodicArworkforShow: (MTTiVoShow *) show withSeriesID: (NSString *) seriesID  {
    __weak typeof(self) weakSelf = self;
    [self searchSeriesArtwork:show
                      artType:nil
            completionHandler:^(NSString *filename) {
                typeof(self) strongSelf = weakSelf;

                [strongSelf cache:@{
                           kTVDBSeriesKey: seriesID,
                           kTVDBSeriesArtworkKey: filename,
                           kTVDBDateKey:[NSDate date]
                           } forShow: show];
                [strongSelf finishTVDBProcessing:show ];

            } failureHandler:^{
                typeof(self) strongSelf = weakSelf;
                DDLogDetail(@"No artwork for %@ (%@)", show, [self urlsForReporting: @[seriesID]]);
                [strongSelf cache:@{
                           kTVDBSeriesKey: seriesID,
                           kTVDBSeriesArtworkKey: @"",
                           kTVDBDateKey:[NSDate date]
                           } forShow: show];
                [strongSelf finishTVDBProcessing:show ];
            }];
}

-(void) addSeasonArtwork: (MTTiVoShow *) show {
    //e.g. https://api.thetvdb.com/series/75930/images/query?keyType=season&subKey=5
    __weak typeof(self) weakSelf = self;
    [self searchSeriesArtwork:show
                      artType:[NSString stringWithFormat:@"season&subKey=%d", show.season]
            completionHandler:^(NSString *filename) {
                typeof(self) strongSelf = weakSelf;
                DDLogDetail(@"Found season artwork for %@: %@", show, filename);

                [strongSelf cacheArtWork:filename
                                  forKey:kTVDBSeasonArtworkKey
                                 forShow:show];
                [strongSelf finishTVDBProcessing:show ];

            } failureHandler:^{
                typeof(self) strongSelf = weakSelf;
                DDLogDetail(@"No season artwork for %@", show);
                [strongSelf cacheArtWork:@""
                                  forKey:kTVDBSeasonArtworkKey
                                 forShow:show];
                [strongSelf finishTVDBProcessing:show ];
            }];
}

-(void) addSeriesArtwork:    (MTTiVoShow *) show {
    __weak typeof(self) weakSelf = self;
    [self searchSeriesArtwork:show
                      artType:nil
            completionHandler:^(NSString *filename) {
                typeof(self) strongSelf = weakSelf;
                DDLogDetail(@"Found series artwork for %@: %@", show, filename);

                [strongSelf cacheArtWork:filename
                                  forKey:kTVDBSeriesArtworkKey
                                 forShow:show];
                [strongSelf finishTVDBProcessing:show ];

            } failureHandler:^{
                typeof(self) strongSelf = weakSelf;
                DDLogDetail(@"No series artwork for %@", show);
                [strongSelf cacheArtWork:@""
                                  forKey:kTVDBSeriesArtworkKey
                                 forShow:show];
                [strongSelf finishTVDBProcessing:show ];
            }];
}

-(void) callSeriesIDForShow: (MTTiVoShow *) show withSeriesName: (NSString *) seriesName andSecondCall: (BOOL) secondCall  {
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
                [self getNonEpisodicArworkforShow:show withSeriesID:seriesIDs[0]];
            }
        }

       failureHandler:^{
           typeof(self) strongSelf = weakSelf;
           NSString * splitName = nil;
           if (secondCall) {
               NSArray * splitNameArray = [show.seriesTitle componentsSeparatedByString:@":"];
               splitName = (splitNameArray.count > 1) ? splitNameArray[0] : nil;
           }
           if (splitName) {
               [strongSelf callSeriesIDForShow:show
                           withSeriesName:splitName
                           andSecondCall:NO];
           } else {
               [strongSelf cache:@{
                           kTVDBSeriesKey: kMTVDBMissing,  //mark as "TVDB doesn't have this series"
                           kTVDBEpisodeArtworkKey:     @"",
                           kTVDBSeasonArtworkKey:     @"",
                           kTVDBSeriesArtworkKey:     @"",
                           kTVDBDateKey:[NSDate date]
                           } forShow: show ];
               NSString *URL = [NSString stringWithFormat:@"http://thetvdb.com/?string=%@&tab=listseries&function=Search", [show.seriesTitle escapedQueryString]];
               if (show.isEpisodicShow) {
                   [strongSelf addValue: URL   inStatistic: kMTVDBEpisodicSeriesNotFound forShow:show.seriesTitle];
               } else {
                   [strongSelf addValue: URL   inStatistic: kMTVDBNonEpisodicSeriesNotFound forShow:show.seriesTitle];
               }
               DDLogDetail(@"TVDB, no series found for %@", show.seriesTitle);
               [self finishTVDBProcessing:show];
           }
       }];
}

-(void)getTheTVDBDetails: (MTTiVoShow *) show {
    //Needs to get episode info from TVDB
    //1) do possibly multiple lookups at TheTVDB in background to find TVDB's seriesID
    //2) call retrieveTVDBEpisodeInfo in background to get Episode Info
    //3) call finishTVDBProcessing on main thread to augment TiVo's info with theTVDB
    NSAssert ([NSThread isMainThread], @"getTheTVDBDetails running in background");

    if (show.tvdbData) {
        return;
    }
    [self incrementStatistic: kMTVDBAll ];

    //if we have a series get the other information
    NSDictionary *episodeEntry = [self getCacheForShow: show];
    if (episodeEntry) { // We already had this information
        NSString * seriesID = episodeEntry[kTVDBSeriesKey];
        if ([seriesID isEqualToString:kMTVDBMissing]) {
            if (episodeEntry[kTVDBPossibleIDsKey]) {
                NSString *URL = [self urlsForReporting:episodeEntry[kTVDBPossibleIDsKey]];
                [self addValue: URL inStatistic:kMTVDBEpisodeNotFoundCached forShow:show.showTitle  ];
            } else {
                NSString *URL = [NSString stringWithFormat:@"http://thetvdb.com/?string=%@&tab=listseries&function=Search", [show.seriesTitle escapedQueryString]];
                if (!show.isEpisodicShow) {
                    [self addValue: URL inStatistic:kMTVDBNonEpisodicSeriesNotFoundCached forShow:show.showTitle  ];
                } else {
                    [self addValue: URL inStatistic:kMTVDBEpisodicSeriesNotFoundCached forShow:show.showTitle  ];
                }
            }
        } else {
            if (seriesID) {
                [self cacheTVDBSeriesID:@[seriesID] forSeries:show.seriesTitle];
            }
            if (show.isEpisodicShow) {
                [self incrementStatistic: kMTVDBSeriesEpisodeFoundCached];
            } else {
               [self incrementStatistic: kMTVDBNonEpisodicSeriesFoundCached ];
           }
        }
        [self finishTVDBProcessing:show];
    } else {
        DDLogDetail(@"Need to get %@", show.showTitle);
        NSArray <NSString *> *seriesIDTVDBs = [self cachedTVDBSeriesID:show.seriesTitle ];

        if (seriesIDTVDBs.count) {
            // already have series ID, but not this episode info
            if (show.isEpisodicShow) {
                [self getEpisodeDetailsForShow:show withIDs:seriesIDTVDBs];
            } else {
                [self incrementStatistic:kMTVDBNonEpisodicSeriesFoundCached];
                [self getNonEpisodicArworkforShow:show withSeriesID:seriesIDTVDBs[0]];
            }
        } else {
            //first get seriesIDs, then Episode Info
            [self callSeriesIDForShow: show withSeriesName:show.seriesTitle andSecondCall:YES];
        }
    }
}

-(void) finishTVDBProcessing: (MTTiVoShow *) show {
    NSAssert ([NSThread isMainThread], @"finishTVDB running in background");
    NSDictionary *tvdbData = [self getCacheForShow:show];
    if (!tvdbData) {
        DDLogReport(@"Trying to process missing TVDB data for %@",show.showTitle);
        tvdbData = @{};
    }
    show.tvdbData = tvdbData;
}

-(BOOL) isActive {
    return NO;  //FIX **** XXX self.tvdbQueue.operationCount > 1;  ??
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
    BOOL titlesMatch = [movieTitle localizedCaseInsensitiveCompare:show.seriesTitle] == NSOrderedSame;
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
        DDLogDetail(@"theMovieDB success : %@ = %@", movie, artwork);

        return artwork;
    } else {
        return nil;
    }
}

-(void) getTheMovieDBDetails: (MTTiVoShow *) show {
    [self incrementStatistic: kMTVDBAll ];
    [self incrementStatistic: kMTVDBMovie ];

    NSString * cachedArt = [self cachedArtWork:kTVDBSeriesArtworkKey forShow:show ];
    if (cachedArt) {
        [self incrementStatistic: cachedArt.length > 0? kMTVDBMovieFoundCached : kMTVDBMovieNotFoundCached];
        [self finishTVDBProcessing:show];
    } else {
        __weak typeof(self) weakSelf = self;
        dispatch_async(dispatch_get_global_queue( DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(void){
            typeof(self) strongSelf = weakSelf;
            [strongSelf getTheMovieDBDetailsBackground:show ];
        });
    }
}

-(void) getTheMovieDBDetailsBackground: (MTTiVoShow *) show  {

    @synchronized (self.movieDBRateLimitLock) {
        self.movieDBRateLimitCalls ++;
        DDLogDetail(@"themovieDB %ld, Entering  =  %@ at %@", (long)self.movieDBRateLimitCalls, show, self.movieDBRateLimitEnd);

        NSTimeInterval delay = [self.movieDBRateLimitEnd timeIntervalSinceNow];

        if (delay > 0 && self.movieDBRateLimitCalls >= 39) {
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
            DDLogReport(@"On %@, hit theMovieDB Rate Limit; please report to " kcTiVoName @" support site", show);
        } else {
            DDLogMajor(@"For %@, theMovieDB returned %@", show, error.localizedDescription ? [@"error: " stringByAppendingString:error.localizedDescription] : @"no information");
       }
        [self addValue:urlString inStatistic:kMTVDBMovieNotFound forShow:show.seriesTitle];
        return;
    }
    error = nil;
    NSDictionary *topLevel = [NSJSONSerialization
                              JSONObjectWithData:movieInfo
                              options:0
                              error:&error];

    NSString * newArtwork = @"";
    if (!topLevel || error) {
        DDLogMajor(@"For &@, theMovieDB returned invalid JSON format: %@ Data: %@",error.localizedDescription, movieInfo);
        [self addValue:lookupURL inStatistic:kMTVDBMovieNotFound forShow:show.seriesTitle];
    } else if(![topLevel isKindOfClass:[NSDictionary class]]) {
        DDLogMajor(@"For &@, theMovieDB returned invalid JSON format:Top Level is not a dictionary; Data: %@", movieInfo);
        [self addValue:lookupURL inStatistic:kMTVDBMovieNotFound forShow:show.seriesTitle];
    } else {
        NSArray * results = topLevel[@"results"];
        if(![results isKindOfClass:[NSArray class]]) {
            DDLogMajor(@"For &@, theMovieDB returned invalid JSON format: Results not an array; Data: %@", movieInfo);
            [self addValue:lookupURL inStatistic:kMTVDBMovieNotFound forShow:show.seriesTitle];
        } else if (results.count == 0) {
            DDLogMajor(@"theMovieDB couldn't find any movies named %@", show.seriesTitle);
            [self addValue:lookupURL inStatistic:kMTVDBMovieNotFound forShow:show.seriesTitle];
        } else {
            for (NSDictionary * movie in results) {
                //look for a perfect title/release match
                NSString * location = [self checkMovie:movie exact:YES forShow:show];
                if (location.length && ![kFormatError isEqualToString:location]) {
                    newArtwork = location;
                    break;
                }
            }
            if (newArtwork.length == 0) {
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
                DDLogDetail(@"for movie %@, theMovieDB had image %@", show.seriesTitle, newArtwork);
                [self incrementStatistic:kMTVDBMovieFound];
            } else {
                DDLogMajor(@"theMovieDB doesn't have any images for %@", show.seriesTitle);
                [self addValue:lookupURL inStatistic:kMTVDBMovieNotFound forShow:show.seriesTitle];
            }
        }
    }

    [self cacheArtWork:newArtwork forKey:kTVDBSeriesArtworkKey forShow:show];
    dispatch_async(dispatch_get_main_queue(), ^(void){
        [self finishTVDBProcessing:show];
    });
}

@end
