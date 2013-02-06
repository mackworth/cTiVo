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
                                    *tvRating,
                                    *sourceType,
                                    *idGuidSource;

@property (nonatomic, retain) NSNumber  *protectedShow,  //really BOOLs
										*inProgress,
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
@property (nonatomic, readonly) NSString *idString,
										*lengthString,
										*isQueuedString,
										*isHDString,
										*sizeString;
@property (nonatomic, readonly) NSAttributedString *actors,
													*guestStars,
													*directors,
													*producers;


//--------------------------------------------------------------
#pragma mark - Properties/Methods for persistent queue
@property (readonly) NSDictionary * queueRecord;  //used to write

-(BOOL) isSameAs:(NSDictionary *) queueEntry;
-(void) restoreDownloadData:(NSDictionary *) queueEntry;



#pragma mark - Properties for download/conversion work
@property (nonatomic, retain) NSNumber *downloadIndex;

@property (nonatomic, retain) NSString *downloadDirectory;
@property (nonatomic, retain) MTFormat *encodeFormat;
@property BOOL  addToiTunesWhenEncoded,
				simultaneousEncode,
				skipCommercials;
				
@property int  	numRetriesRemaining,
				numStartupRetriesRemaining;
-(void) prepForResubmit;

@property (nonatomic, readonly) NSString *encodeFilePath,
										 *bufferFilePath,   //
										 *downloadFilePath;



//--------------------------------------------------------------
#pragma mark - Properties for download/conversion progress
@property (retain) NSNumber *downloadStatus;
@property (nonatomic, readonly)	NSString *showStatus;

@property double processProgress; //Should be between 0 and 1

@property BOOL isSimultaneousEncoding,
				isQueued,
                isSelected;//Used for refresh of table
@property (readonly) BOOL isNew, isDownloading, isInProgress, isDone;


#pragma mark - Methods for download/conversion work
-(void)rescheduleShowWithDecrementRetries:(NSNumber *)decrementRetries;  //decrementRetries is a BOOL standing
-(void)cancel;
-(void)download;
-(void)decrypt;
-(void)commercial;
-(void)encode;
-(void)getShowDetail;

#pragma mark - Methods for manipulating video
-(void) playVideo;
-(void) revealInFinder;

//Move to category on NSString
+(NSDate *)dateForRFC3339DateTimeString:(NSString *)rfc3339DateTimeString;



@end
