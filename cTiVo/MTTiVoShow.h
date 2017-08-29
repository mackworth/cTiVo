//
//  MTTiVoShow.h
//  cTiVo
//
//  Created by Scott Buchanan on 12/18/12.
//  Copyright (c) 2012 Scott Buchanan. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "iTunes.h"
#import "MTTiVo.h"
#import "MTFormat.h"
#import "mp4v2.h"
#import "DragDropImageView.h"
#import "MTRPCData.h"

@class MTProgramTableView;

@interface MTTiVoShow : NSObject <NSXMLParserDelegate, NSPasteboardWriting,NSPasteboardReading, NSCoding, NSURLDownloadDelegate, DragDropImageViewDelegate> {
 }


#pragma mark - Which TiVo did we come from
@property (nonatomic, weak) MTTiVo *tiVo;
@property (nonatomic, strong) NSString *tempTiVoName;  //used before we find TiVo
@property (weak, nonatomic, readonly) NSString *tiVoName; //either of above

//--------------------------------------------------------------
#pragma mark - Properties loaded in from TiVo's XML
@property (nonatomic, strong) NSString 
									*seriesTitle,
									*episodeTitle,
                                    *showDescription,
									*showLengthString,
                                    *channelString,
                                    *stationCallsign,
									*programId,
									*seriesId,
                                    *sourceType,
									*imageString,
                                    *idGuidSource;


@property (nonatomic, strong) NSNumber
                                    *protectedShow,  //really BOOLs
                                    *inProgress,      //Is Tivo currently recording this show
                                    *isHD;
@property (nonatomic, strong) NSDate *showDate;

@property					  double fileSize;  //Size on TiVo;

@property (nonatomic, strong)  NSURL *downloadURL,
                                    *detailURL;

//computed from TiVo's XML
@property					  int    showID;  //pulled out of URL; unique for this TiVo
@property (nonatomic, assign) NSInteger tvRating,
                                        mpaaRating;

//Properties loaded in from TiVo's Detail XML
@property (atomic, strong, readonly) NSString
                                    *movieYear,
                                    *originalAirDate,
                                    *showTime,
                                    *startTime,
                                    *stopTime,
                                    *showingBits,
                                    *colorCode,
                                    *starRating,
                                    *episodeGenre;

@property (atomic, strong) NSString *episodeNumber;

@property (strong, nonatomic, readonly) NSAttributedString
                                    *writers,
                                    *actors,
                                    *guestStars,
                                    *directors,
                                    *producers;

@property (strong, nonatomic) NSString *episodeID;  //normalized version of programID (convert 12 digit to 14
@property (nonatomic, readonly) NSString *uniqueID; //episodeID for episodic
                                                 //episodeID+showDateRFC for non-episodic

@property (nonatomic, assign)  time_t showLength;  //length of show in seconds

@property (nonatomic, strong) NSString  * artworkFile,  //location of images on disk, if they exist
                                        * thumbnailFile;
@property (nonatomic, strong) NSImage   * artWorkImage, //image after loading (triggers download when loaded )
                                        * thumbnailImage;
@property (nonatomic, readonly) BOOL noImageAvailable; //and it'll never arrive

#define kTVDBSeriesKey  @"series" //what TVDB SeriesID does this belong to?
#define kMTVDBMissing   @"unknown"  //used as value for kTVDBKeySeries, if we've tried and not avaiable
#define kTVDBArtworkKey @"artwork" //URL for artwork at TVDB
#define kTVDBEpisodeKey @"episode"  //string with episode number
#define kTVDBSeasonKey  @"season"   //string with season number
#define kTVDBURLsKey    @"reportURL" //URLs for reporting to user
#define kTVDBPossibleIDsKey  @"possibleIds" //Array of IDs that we checked to find series

@property (nonatomic, strong) NSDictionary <NSString *, id> * tvdbData;

//--------------------------------------------------------------
#pragma mark - Calculated properties for display 
@property (nonatomic, strong)	NSString *showTitle;  //calculated from series: episode
@property (nonatomic, readonly) NSString *originalAirDateNoTime,
                                         *showTitlePlusAirDate,
										 *showDateString,
										*showKey,
                                        *showDateRFCString,
										 *showMediumDateString;
@property (atomic, assign)		int	season, episode; //calculated from EpisodeNumber
@property (nonatomic, readonly) NSString *seasonString;
@property (nonatomic, readonly) NSString *seasonEpisode; // S02 E04 version
@property (nonatomic, readonly) BOOL manualSeasonInfo;

@property (readonly, nonatomic) NSString *attribDescription;
@property (readonly, nonatomic) NSString *starRatingString;

@property (nonatomic, readonly) NSString *ageRatingString; //computed from tvRating and MPRating
@property (nonatomic, readonly) NSNumber *ageRatingValue; //computed from tvRating and MPRating

@property (nonatomic, readonly) BOOL    isMovie;
@property (nonatomic, readonly) BOOL    isEpisodicShow;

@property (nonatomic, readonly) BOOL    isSuggestion;

@property (nonatomic, readonly) NSNumber *channelNumber;  //numeric version of channel. Used only for sorting; NA => big number
@property (weak, nonatomic, readonly) NSString *idString,
										*combinedChannelString,
										*lengthString,
										*isQueuedString,
										*isHDString,
                                        *isOnDiskString,
                                        *h264String,
										*sizeString;

@property BOOL isQueued;
@property (nonatomic, readonly) BOOL isOnDisk;
@property (nonatomic, readonly) NSArray <NSString *> *copiesOnDisk;

@property (atomic, assign) BOOL	gotDetails, gotTVDBDetails;
@property (nonatomic, strong) MTRPCData * rpcData;

-(void) getShowDetail;

-(void) setShowSeriesAndEpisodeFrom:(NSString *) newTitle ;
-(void) resetTVDBInfo;

-(void) playVideo:(NSString *)path;
-(void) revealInFinder:(NSArray *)paths;
-(void) addExtendedMetaDataToFile:(MP4FileHandle *)fileHandle withImage:(NSImage *) artwork ;
-(void) createTestMP4;

typedef enum {
	HDTypeNotAvailable = -1,
	HDTypeStandard = 0,
	HDType720p = 1,
	HDType1080p = 2
} HDTypes;

-(NSString *) downloadFileNameWithFormat:(NSString *)formatName createIfNecessary:(BOOL) create;

-(NSString *) swapKeywordsInString: (NSString *) str withFormat:(NSString *) format;  //exposed for test only

-(const MP4Tags * ) metaDataTagsWithImage: (NSImage *) image andResolution:(HDTypes) hdType;

@end
