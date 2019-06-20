//
//  MTDownload.h
//  cTiVo
//
//  Created by Hugh Mackworth on 2/26/13.
//  Copyright (c) 2013 Scott Buchanan. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "MTTiVo.h"
#import "MTFormat.h"
#import "MTTiVoShow.h"
#import "MTEdl.h"
#import "MTSrt.h"
#import "MTTask.h"
#import "MTTaskChain.h"

@interface MTDownload : NSObject  <NSXMLParserDelegate, NSPasteboardWriting,NSPasteboardReading, NSSecureCoding>


#pragma mark - Properties for download/conversion configuration
@property (nonatomic, readonly) MTTiVoShow *show;
@property (nonatomic, readonly) NSString *downloadDirectory;
@property (nonatomic, readonly) NSString *tmpDirectory;
@property (nonatomic, readonly) NSString *baseFileName;
@property (nonatomic, readonly) NSString *encodeFilePath;
@property (nonatomic, strong)   MTFormat *encodeFormat;  //changeable until download starts

@property (nonatomic, strong)  NSNumber *genTextMetaData,
										*useTransportStream,
                                        *exportSubtitles,
										*deleteAfterDownload;
@property (nonatomic, assign) BOOL      addToiTunesWhenEncoded,
										useSkipMode,
										skipCommercials,
                                        markCommercials;

#pragma mark - Methods for download/conversion work
+(MTDownload *) downloadForShow:(MTTiVoShow *) show withFormat: (MTFormat *) format withQueueStatus: (NSInteger) status;
+(MTDownload *) downloadTestPSForShow:(MTTiVoShow *) show;
+(MTDownload *) downloadFromQueue:(NSDictionary *) queueEntry;

-(void) prepareForDownload: (BOOL) notifyTiVo;  //reset for a new download

-(void) rescheduleDownloadFalseStart;
-(void) rescheduleDownload; //can be called from background
-(void) cancel;

-(void) launchDownload;  //actually launch the download process
-(void) launchPostCommercial; //ok to launch now
-(void) skipModeCheck;
-(void)notifyUserWithTitle:(NSString *) title subTitle: (NSString*) subTitle ;   //download  notification

-(BOOL) isSimilarTo: (MTDownload *) testDownload;

#pragma mark - Properties for download/conversion progress
@property (atomic, strong) NSNumber *downloadStatus;
@property (readonly) NSInteger downloadStatusSorter;

@property (readonly) BOOL isNew, isDownloading, isInProgress, isDone, isCompletelyDone;
//convenience versions of downloadStatus
@property (atomic, assign) BOOL isCanceled;
@property (atomic, assign) double processProgress; //Should be between 0 and 1
@property (atomic, strong) MTTaskChain *activeTaskChain; //advanced to nextTaskChain when appropriate


#pragma mark - Properties/Methods for persistent queue (in NSUserDefaults)
@property (weak, readonly) NSDictionary * queueRecord;
-(BOOL) isSameAs:(NSDictionary *) queueEntry;
-(void) convertProxyToRealForShow:(MTTiVoShow *) show;


#pragma mark - Properties for display in NSTableView
@property (nonatomic, readonly) NSNumber *downloadIndex;
@property (nonatomic, readonly) NSString *showStatus;
@property (nonatomic, readonly) NSString *imageString;
@property (nonatomic, readonly) NSString *timeLeft;
@property (atomic, readonly) double speed;  //bytes/second


#pragma mark - Methods for manipulating video files
-(NSURL *) videoFileURLWithEncrypted: (BOOL) encrypted;
-(BOOL) canPlayVideo;
-(BOOL) playVideo;


@end
