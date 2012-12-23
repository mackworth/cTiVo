//
//  MTTiVoShow.h
//  cTiVo
//
//  Created by Scott Buchanan on 12/18/12.
//  Copyright (c) 2012 Scott Buchanan. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "iTunes.h"

@interface MTTiVoShow : NSObject {
    NSFileHandle *activeFile, *encodeFile;
	NSString *activeFilePath, *encodeFilePath;
    double dataDownloaded;
    NSTask *activeTask, *tivodecoderTask;
	NSURLConnection *activeURLConnection;
	NSString *sourceFilePath, *targetFilePath, *fileBufferPath;
	NSPipe *pipe1, *pipe2;
	NSMutableArray *dataToWrite;
	BOOL volatile writingData, downloadingURL, pipingData;
	off_t readPointer, writePointer;
	NSFileHandle *fileBufferRead, *fileBufferWrite;
}

@property (nonatomic, retain) NSString *urlString, *downloadDirectory, *mediaKey, *title, *description, *showStatus, *showDate;
@property (nonatomic, retain) NSURL *URL;
@property int downloadStatus, showID;
@property double processProgress; //Should be between 0 and 1
@property double fileSize;  //Size on TiVo;
@property (nonatomic, retain) NSDictionary *encodeFormat;
@property (nonatomic, retain) NSNetService *tiVo;
@property BOOL addToiTunesWhenEncoded, simultaneousEncode, isSimultaneousEncoding;
@property BOOL volatile isCanceled;


-(BOOL)cancel;
-(void)download;
-(void)decrypt;
-(void)encode;



@end
