//
//  MTTiVoShow.h
//  cTiVo
//
//  Created by Scott Buchanan on 12/18/12.
//  Copyright (c) 2012 Scott Buchanan. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "iTunes.h"

@class MTProgramList;

@interface MTTiVoShow : NSObject <NSXMLParserDelegate> {
    NSFileHandle    *downloadFileHandle,
                    *decryptFileHandle,
                    *decryptLogFileHandle,
                    *decryptLogFileReadHandle,
                    *encodeFileHandle,
                    *encodeLogFileHandle,
                    *encodeLogFileReadHandle,
                    *bufferFileReadHandle,
                    *bufferFileWriteHandle,
                    *devNullFileHandle;
	NSString *downloadFilePath, *decryptFilePath, *decryptLogFilePath, *encodeFilePath, *encodeLogFilePath, *bufferFilePath;
    double dataDownloaded;
    NSTask *encoderTask, *decrypterTask;
	NSURLConnection *activeURLConnection, *detailURLConnection;
	NSPipe *pipe1, *pipe2;
	BOOL volatile writingData, downloadingURL, pipingData;
	off_t readPointer, writePointer;
	NSXMLParser *parser;
	NSMutableString *element;
	BOOL    gotDetails;
}

@property (nonatomic, retain) NSString *urlString,
									*downloadDirectory,
									*mediaKey,
									*showTitle,
									*showDescription,
									*showStatus,
									*episodeTitle,
									*showGenre,
									*episodeNumber,
									*isEpisode,
									*originalAirDate,
									*episodeGenre,
									*showDate;

@property (nonatomic, readonly) NSString *encodeFilePath;
@property time_t showLength;  //length of show in seconds
@property (nonatomic, retain) NSURL *URL;
@property int downloadStatus, showID, season, episode, episodeYear;
@property double processProgress; //Should be between 0 and 1
@property double fileSize;  //Size on TiVo;
@property (nonatomic, retain) NSDictionary *encodeFormat;
@property (nonatomic, retain) NSNetService *tiVo;
@property BOOL addToiTunesWhenEncoded, simultaneousEncode, isSimultaneousEncoding, isQueued,
                isSelected;//Used for refresh of table

@property BOOL volatile isCanceled;
@property (nonatomic, assign) MTProgramList *myTableView;


-(BOOL)cancel;
-(void)download;
-(void)decrypt;
-(void)encode;
-(void)getShowDetail;
-(void)getShowDetailWithNotification;



@end
