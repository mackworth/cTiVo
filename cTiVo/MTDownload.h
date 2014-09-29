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
#import "MTTask.h"
#import "MTTaskChain.h"

@interface MTDownload : NSObject  <NSXMLParserDelegate, NSPasteboardWriting,NSPasteboardReading, NSCoding> {
    
    ssize_t volatile totalDataRead, totalDataDownloaded;
}

@property (strong, nonatomic) MTTaskChain *activeTaskChain;

@property (nonatomic, strong) MTTiVoShow * show;

//-------------------------------------------------------------
#pragma mark - Properties/Methods for persistent queue
@property (weak, readonly) NSDictionary * queueRecord;  //used to write

-(BOOL) isSameAs:(NSDictionary *) queueEntry;
-(void) restoreDownloadData:(NSDictionary *) queueEntry;

#pragma mark - Properties for download/conversion work
@property (nonatomic, readonly) NSNumber *downloadIndex;

@property (nonatomic, strong) NSString *downloadDirectory;
@property (nonatomic, strong) MTFormat *encodeFormat;

@property BOOL volatile isCanceled, isRescheduled, downloadingShowFromTiVoFile, downloadingShowFromMPGFile;

@property (nonatomic, strong) NSNumber *genTextMetaData,
#ifndef deleteXML
*genXMLMetaData,
*includeAPMMetaData,
#endif
*exportSubtitles;
@property BOOL  addToiTunesWhenEncoded,
//simultaneousEncode,
skipCommercials,
markCommercials;

@property NSInteger  	numRetriesRemaining,
numStartupRetriesRemaining;
-(void) prepareForDownload: (BOOL) notifyTiVo;

@property (nonatomic, readonly) NSString *encodeFilePath,
*bufferFilePath,   //
*tivoFilePath,  //For checkpointing
*mpgFilePath,   //For checkpointing
*decryptBufferFilePath,
*downloadFilePath;

@property(nonatomic, strong) NSString * baseFileName;



//--------------------------------------------------------------
#pragma mark - Properties for download/conversion progress
@property (strong) NSNumber *downloadStatus;
@property (weak, nonatomic, readonly)	NSString *showStatus;
@property (weak, nonatomic, readonly) NSString *imageString;
@property double processProgress; //Should be between 0 and 1
@property (nonatomic, readonly) NSTimeInterval timeLeft;
@property (nonatomic, readonly) double speed;  //bytes/second
@property (nonatomic, readonly) BOOL shouldSimulEncode, shouldMarkCommercials;

@property BOOL isSimultaneousEncoding;

@property (readonly) BOOL isNew, isDownloading, isInProgress, isDone;


#pragma mark - Methods for download/conversion work
-(void)rescheduleShowWithDecrementRetries:(NSNumber *)decrementRetries;  //decrementRetries is a BOOL standing
-(void)cancel;
-(void)download;
-(void) finishUpPostEncodeProcessing;


#pragma mark - Methods for manipulating video
-(NSURL *) videoFileURLWithEncrypted: (BOOL) encrypted;
-(BOOL) canPlayVideo;
-(BOOL) playVideo;
-(BOOL) revealInFinder;
-(void)rescheduleOnMain;

@end
