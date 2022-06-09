//
//  MTTVDBManager.h
//  cTiVo
//
//  Created by Hugh Mackworth on 6/30/17.
//  Copyright © 2017 cTiVo. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "MTTiVoShow.h"
NS_ASSUME_NONNULL_BEGIN

@interface MTTVDB : NSObject

+ (MTTVDB *)sharedManager;

#define kTVDBSeriesKey  @"series" //what TVDB SeriesID does this belong to?
#define kMTVDBMissing   @"unknown"  //used as value for kTVDBKeySeries, if we've tried and not avaiable
#define kTVDBEpisodeArtworkKey @"episodeArtwork" //URL for artwork at TVDB
#define kTVDBSeasonArtworkKey @"seasonArtwork" //URL for artwork at TVDB
#define kTVDBSeriesArtworkKey @"seriesArtwork" //URL for artwork at TVDB
#define kTVDBEpisodeKey @"episode"  //string with episode number
#define kTVDBSeasonKey  @"season"   //string with season number
#define kTVDBURLsKey    @"reportURL" //URLs for reporting to user
#define kTVDBPossibleIDsKey  @"possibleIds" //Array of IDs that we checked to find series

//all of these will (immediately or eventually) set the tvdbData attributes of show
-(void) getTheTVDBDetails: (MTTiVoShow *) show;

-(void) getTheMovieDBDetails: (MTTiVoShow *) show;

-(NSDictionary *) cacheArtWork: (NSString *) newArtwork forKey: (NSString *) key forShow: (MTTiVoShow *) show;
-(void) resetTVDBInfo:(MTTiVoShow *) show;
-(void) addSeriesArtwork:(MTTiVoShow *) show; //called if regular artwork lookup failed, or switch to series
-(void) addSeasonArtwork:(MTTiVoShow *) show; //called if switch to season.

-(void) resetAll;  //destroys all caches
-(void) saveDefaults; //writes caches to userdefaults
-(NSString *) stats;
-(BOOL) isActive;

-(NSArray <NSString *> *) seriesIDsForShow: (MTTiVoShow *) show;

@end

@interface MTTVDB3 : MTTVDB 

@end
NS_ASSUME_NONNULL_END
