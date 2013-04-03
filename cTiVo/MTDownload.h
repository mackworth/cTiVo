//
//  MTDownload.h
//  cTiVo
//
//  Created by Hugh Mackworth on 2/26/13.
//  Copyright (c) 2013 Scott Buchanan. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "iTunes.h"
#import "MTTiVo.h"
#import "MTFormat.h"
#import "MTTiVoShow.h"
#import "MTEdl.h"
#import "MTSrt.h"

@interface MTDownload : NSObject  <NSXMLParserDelegate, NSPasteboardWriting,NSPasteboardReading, NSCoding> {
}

@property (nonatomic, retain) MTTiVoShow * show;

//-------------------------------------------------------------
#pragma mark - Properties/Methods for persistent queue
@property (readonly) NSDictionary * queueRecord;  //used to write

-(BOOL) isSameAs:(NSDictionary *) queueEntry;
-(void) restoreDownloadData:(NSDictionary *) queueEntry;

#pragma mark - Properties for download/conversion work
@property (nonatomic, retain) NSNumber *downloadIndex;

@property (nonatomic, retain) NSString *downloadDirectory;
@property (nonatomic, retain) MTFormat *encodeFormat;

@property (nonatomic, retain) NSNumber *genTextMetaData,
*genXMLMetaData,
*includeAPMMetaData,
*exportSubtitles;
@property BOOL  addToiTunesWhenEncoded,
simultaneousEncode,
skipCommercials;

@property int  	numRetriesRemaining,
numStartupRetriesRemaining;
-(void) prepareForDownload: (BOOL) notifyTiVo;

@property (nonatomic, readonly) NSString *encodeFilePath,
*bufferFilePath,   //
*downloadFilePath;



//--------------------------------------------------------------
#pragma mark - Properties for download/conversion progress
@property (retain) NSNumber *downloadStatus;
@property (nonatomic, readonly)	NSString *showStatus;
@property (nonatomic, readonly) NSString *imageString;
@property double processProgress; //Should be between 0 and 1

@property BOOL isSimultaneousEncoding;

@property (readonly) BOOL isNew, isDownloading, isInProgress, isDone;


#pragma mark - Methods for download/conversion work
-(void)rescheduleShowWithDecrementRetries:(NSNumber *)decrementRetries;  //decrementRetries is a BOOL standing
-(void)cancel;
-(void)download;
-(void)decrypt;
-(void)commercial;
-(void)caption;
-(void)encode;

#pragma mark - Methods for manipulating video
-(NSURL *) videoFileURLWithEncrypted: (BOOL) encrypted;
-(BOOL) canPlayVideo;
-(BOOL) playVideo;
-(BOOL) revealInFinder;

@end
