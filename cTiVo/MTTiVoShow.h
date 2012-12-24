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
    NSFileHandle *activeFile, *encodeFile;
	NSString *activeFilePath, *targetFilePath, *encodeFilePath;
    double dataDownloaded;
    NSTask *activeTask, *tivodecoderTask;
	NSURLConnection *activeURLConnection, *detailURLConnection;
	NSString *sourceFilePath, *fileBufferPath;
	NSPipe *pipe1, *pipe2;
	NSMutableArray *dataToWrite;
	BOOL volatile writingData, downloadingURL, pipingData;
	off_t readPointer, writePointer;
	NSFileHandle *fileBufferRead, *fileBufferWrite;
	NSXMLParser *parser;
	NSMutableString *element;
	BOOL gotDetails;
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

@property (nonatomic, readonly) NSString *targetFilePath;
@property time_t showLength;  //length of show in seconds
@property (nonatomic, retain) NSURL *URL;
@property int downloadStatus, showID, season, episode, episodeYear;
@property double processProgress; //Should be between 0 and 1
@property double fileSize;  //Size on TiVo;
@property (nonatomic, retain) NSDictionary *encodeFormat;
@property (nonatomic, retain) NSNetService *tiVo;
@property BOOL addToiTunesWhenEncoded, simultaneousEncode, isSimultaneousEncoding;
@property BOOL volatile isCanceled;
@property (nonatomic, assign) MTProgramList *myTableView;


-(BOOL)cancel;
-(void)download;
-(void)decrypt;
-(void)encode;
-(void)getShowDetail;
-(void)getShowDetailWithNotification;



@end
