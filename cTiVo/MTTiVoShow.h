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

@class MTProgramTableView;

@interface MTTiVoShow : NSObject <NSXMLParserDelegate, NSPasteboardWriting,NSPasteboardReading, NSCoding> {
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
									*showTime,
									*episodeNumber,
									*originalAirDate,
									*showLengthString,
                                    *channelString,
                                    *stationCallsign,
									*programId,
									*episodeID,
									*seriesId,
									*movieYear,
									*isEpisodic,
                                    *tvRating,
                                    *sourceType,
									*imageString,
                                    *idGuidSource;

@property (nonatomic, strong) NSNumber  *protectedShow,  //really BOOLs
										*inProgress,      //Is Tivo currently recording this show
										*isHD;
@property					  double fileSize;  //Size on TiVo;

@property (nonatomic, strong) NSURL *downloadURL,
									*detailURL;

@property (nonatomic, strong) NSDate *showDate;
@property					  int    showID;

@property					  time_t showLength;  //length of show in seconds




#pragma mark - Properties loaded in from Details Page
@property int episodeYear;


//--------------------------------------------------------------
#pragma mark - Calculated properties for display 
@property (nonatomic, strong)	NSString *showTitle;  //calculated from series: episode
@property (nonatomic, readonly) NSString *yearString,
										*originalAirDateNoTime,
										 *showDateString,
										*showKey,
										 *showMediumDateString;
@property						int	season, episode; //calculated from EpisodeNumber
@property (weak, nonatomic, readonly) NSString *seasonString;
@property (weak, nonatomic, readonly) NSString *seasonEpisode; // S02 E04 version

@property (weak, nonatomic, readonly)	NSString *episodeGenre;

@property (nonatomic, readonly) BOOL    isMovie;
@property (nonatomic, readonly) BOOL    isSuggestion;
@property (weak, nonatomic, readonly) NSString *idString,
										*combinedChannelString,
										*lengthString,
										*isQueuedString,
										*isHDString,
										*sizeString;
@property (weak, nonatomic, readonly) NSAttributedString *actors,
													*guestStars,
													*directors,
													*producers,
													*attribDescription;

@property BOOL isQueued;

@property (nonatomic, assign) BOOL	gotDetails;
@property (nonatomic, strong) NSData *detailXML;
-(void)getShowDetail;

//-(NSArray *) apmArguments;

-(void)playVideo:(NSString *)path;
-(void)revealInFinder:(NSArray *)paths;

-(const MP4Tags * ) metaDataTagsWithImage: (NSImage *) image;


@end
