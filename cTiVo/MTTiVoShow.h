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

@class MTProgramTableView;

@interface MTTiVoShow : NSObject <NSXMLParserDelegate, NSPasteboardWriting,NSPasteboardReading, NSCoding> {
 }


#pragma mark - Which TiVo did we come from
@property (nonatomic, assign) MTTiVo *tiVo;
@property (nonatomic, retain) NSString *tempTiVoName;  //used before we find TiVo
@property (nonatomic, readonly) NSString *tiVoName; //either of above

//--------------------------------------------------------------
#pragma mark - Properties loaded in from TiVo's XML
@property (nonatomic, retain) NSString 
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
                                    *seriesId,
									*movieYear,
									*isEpisodic,
                                    *tvRating,
                                    *sourceType,
									*imageString,
                                    *idGuidSource;

@property (nonatomic, retain) NSNumber  *protectedShow,  //really BOOLs
										*inProgress,      //Is Tivo currently recording this show
										*isHD;
@property					  double fileSize;  //Size on TiVo;

@property (nonatomic, retain) NSURL *downloadURL,
									*detailURL;

@property (nonatomic, retain) NSDate *showDate;
@property					  int    showID;

@property					  time_t showLength;  //length of show in seconds



#pragma mark - Properties loaded in from Details Page
@property int episodeYear;


//--------------------------------------------------------------
#pragma mark - Calculated properties for display 
@property (nonatomic, retain)	NSString *showTitle;  //calculated from series: episode
@property (nonatomic, readonly) NSString *yearString,
										*originalAirDateNoTime,
										 *showDateString,
										 *showMediumDateString;
@property						int	season, episode; //calculated from EpisodeNumber
@property (nonatomic, readonly) NSString *seasonString;
@property (nonatomic, readonly) NSString *seasonEpisode; // S02 E04 version

@property (nonatomic, readonly)	NSString *episodeGenre;

@property (nonatomic, readonly) BOOL    isMovie;
@property (nonatomic, readonly) BOOL    isSuggestion;
@property (nonatomic, readonly) NSString *idString,
										*combinedChannelString,
										*lengthString,
										*isQueuedString,
										*isHDString,
										*sizeString;
@property (nonatomic, readonly) NSAttributedString *actors,
													*guestStars,
													*directors,
													*producers;

@property BOOL isQueued;

@property (nonatomic, assign) BOOL	gotDetails;
@property (nonatomic, retain) NSData *detailXML;
-(void)getShowDetail;

-(NSArray *) apmArguments;



@end
