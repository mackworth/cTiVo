//
//  MTTiVoShow.h
//  cTiVo
//
//  Created by Scott Buchanan on 12/18/12.
//  Copyright (c) 2012 Scott Buchanan. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "MTTiVo.h"
#import "MTFormat.h"
#import "mp4v2.h"
#import "DragDropImageView.h"
#import "MTRPCData.h"

@class MTProgramTableView;

@interface MTTiVoShow : NSObject <NSXMLParserDelegate, NSPasteboardWriting,NSPasteboardReading, NSSecureCoding, DragDropImageViewDelegate> {
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
@property (readonly) NSURL * detailFileURL;

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

@property (nonatomic, strong) NSURL  * artworkFile,  //location of images on disk, if they exist
                                        * thumbnailFile;
@property (nonatomic, strong) NSImage   * artWorkImage, //image after loading (triggers download when loaded )
                                        * thumbnailImage;
@property (nonatomic, readonly) BOOL noImageAvailable; //and it'll never arrive

@property (nonatomic, strong) NSDictionary <NSString *, id> * tvdbData;
@property (nonatomic, strong) MTRPCData * rpcData;
@property (nonatomic, assign) MPEGFormat mpegFormat;

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
@property (nonatomic, readonly) NSNumber *idNumber;  //numeric version of showID

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
@property (nonatomic, readonly) BOOL isFolder;
@property (nonatomic, readonly) BOOL hasSkipModeList;
@property (nonatomic, readonly) BOOL hasSkipModeInfo; //has the metadata that we need to get skipmode List
@property (nonatomic, readonly) BOOL skipModeFailed;   //tried doing EDL, but failed
@property (nonatomic, readonly) NSNumber * rpcSkipMode; //only for sorting in tables
@property (nonatomic, readonly) NSTimeInterval timeLeftTillRPCInfoWontCome;
@property (nonatomic, readonly) BOOL mightHaveSkipModeInfo;   //whether it's worth waiting for download in Skip scenario
@property (nonatomic, readonly) BOOL mightHaveSkipModeInfoLongest; //true if there's ANY chance of it coming in later (for purging at end of program)

@property (nonatomic, readonly) NSArray <NSString *> *copiesOnDisk;

@property (nonatomic, strong) NSArray <MTEdl *> *edlList;

@property (atomic, assign) BOOL	gotDetails;

-(void) getShowDetail;

-(void) setShowSeriesAndEpisodeFrom:(NSString *) newTitle ; //used only while reloading
-(void) resetSourceInfo:(BOOL) all;
-(void) checkAllInfoSources;

-(BOOL) playVideo;
-(void) addExtendedMetaDataToFile:(MP4FileHandle *)fileHandle withImage:(NSImage *) artwork ;
-(void) createTestMP4;

typedef enum {
	HDTypeNotAvailable = -1,
	HDTypeStandard = 0,
	HDType720p = 1,
	HDType1080p = 2
} HDTypes;

-(NSString *) downloadFileNameWithFormat:(NSString *)formatName andOptions: (NSString *) options createIfNecessary:(BOOL) create;

-(NSString *) swapKeywordsInString: (NSString *) str withFormat:(NSString *) format andOptions: (NSString *) options ;  //exposed for test only

-(const MP4Tags * ) metaDataTagsWithImage: (NSImage *) image andResolution:(HDTypes) hdType;

@end
