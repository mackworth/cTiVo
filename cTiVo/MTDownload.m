//
//  MTDownload.m
//  cTiVo
//
//  Created by Hugh Mackworth on 2/26/13.
//  Copyright (c) 2013 Scott Buchanan. All rights reserved.
//

#import "MTProgramTableView.h"
#import "MTiTunes.h"
#import "MTTiVoManager.h"
#import "MTDownload.h"
#import "NSString+Helpers.h"
#include "mp4v2.h"
#include "NSNotificationCenter+Threads.h"
#include "NSURL+MTURLExtensions.h"
#include "NSDate+Tomorrow.h"
#include "MTWeakTimer.h"
#include "NSTask+RunTask.h"

#import <Carbon/Carbon.h>

#ifndef DEBUG
#import "Crashlytics/Crashlytics.h"
#endif


@interface MTDownload ()

//Task Flow Types
// bit 0 = Subtitle
// bit 1 = Simultaneous download/encoding
// bit 2 = Skip Com
// bit 3 = Mark Com
//no 12-15 because skipCom <==> ! markCom

typedef NS_ENUM(NSUInteger, MTTaskFlowType) {
	kMTTaskFlowNonSimu = 0,
	kMTTaskFlowSubtitles = 1,
	kMTTaskFlowSimu = 2,
	kMTTaskFlowSimuSubtitles = 3,
	kMTTaskFlowSkipcom = 4,
	kMTTaskFlowSkipcomSubtitles = 5,
	kMTTaskFlowSimuSkipcom = 6,
	kMTTaskFlowSimuSkipcomSubtitles = 7,
	kMTTaskFlowMarkcom = 8,
	kMTTaskFlowMarkcomSubtitles = 9,
	kMTTaskFlowSimuMarkcom = 10,
	kMTTaskFlowSimuMarkcomSubtitles = 11
};

@property (nonatomic, strong) MTTiVoShow * show;
@property (nonatomic, strong) NSString *downloadDirectory;
@property (nonatomic, strong) NSString *tmpDirectory;

@property (nonatomic, strong) NSFileHandle  *bufferFileWriteHandle;
//we read from EITHER bufferFileReadHandle or urlBuffer (if memory-based and encoder keeping up with Tivo)
@property (atomic, strong) NSFileHandle * bufferFileReadHandle;
@property (atomic, strong) NSMutableData *urlBuffer;
@property (atomic, assign) ssize_t urlReadPointer;
@property (atomic, strong) NSURLConnection *activeURLConnection;

@property (atomic, strong) NSFileHandle *taskChainInputHandle;

@property (atomic, assign) NSInteger  	numRetriesRemaining,
                                        numStartupRetriesRemaining;

@property (atomic, assign) BOOL  writingData;  //says background thread writedata is still active, so don't launch another

//these vars used for watchdog "checkStillActive"
@property (atomic, strong) NSDate *previousCheck, *progressAt100Percent;
@property (atomic, assign) double previousProcessProgress;

@property (atomic, assign) double displayedProcessProgress;

@property (nonatomic) MTTask *decryptTask, *encodeTask, *commercialTask, *captionTask;

@property (nonatomic, strong) NSDate *startTimeForPerformance;
@property (nonatomic, assign) double startProgressForPerformance;
@property (nonatomic, assign) NSTimeInterval downloadDelay;
@property (nonatomic, strong) NSDate *downloadDelayStart;

@property (nonatomic, strong) NSTimer * performanceTimer;
@property (nonatomic, assign) int numZeroSpeeds;

@property (atomic, assign) ssize_t  totalDataRead, totalDataDownloaded;

@property (atomic, assign) double speed;

@property (atomic, assign) BOOL volatile isRescheduled, downloadingShowFromTiVoFile, downloadingShowFromMPGFile;
@property (nonatomic, assign) MTTaskFlowType taskFlowType;

@property (nonatomic, strong) NSString *baseFileName,
*tivoFilePath,  //For reading .tivo file from a prev run (not implemented; reuse bufferFilePath?)
//*mpgFilePath,   //For reading decoded .mpg from a prev run (not implemented; reuse decryptedFilePath?)
*bufferFilePath,  //downloaded show prior to decryption; .tivo if complete, .bin if not (due to memory buffer usage)
*decryptedFilePath, //show after decryption; .mpg
*encodeFilePath, //ultimate destination for show after encoding (e.g. MP4)
*tempEncodeFilePath, //same in temp folder before final xfer due to sandbox problem.(No difference in non-sandbox)
*commercialFilePath,  //.edl after commercial processing
*nameLockFilePath, //.lck to ensure we don't save to same file name twice
*captionFilePath, //ultimate destination for .srt after caption processing
*tempCaptionFilePath; //same in temp folder before final xfer due to sandbox problem. (No difference in non-sandbox)

@property (nonatomic, strong) NSTimer * waitForSkipModeInfoTimer;

@end

@implementation MTDownload


__DDLOGHERE__

#pragma mark Initializers
-(id)init
{
    self = [super init];
    if (self) {
 		_decryptedFilePath = nil;
        _commercialFilePath = nil;
		_nameLockFilePath = nil;
        _captionFilePath = nil;
		_addToiTunesWhenEncoded = NO;
		_writingData = NO;
		_genTextMetaData = nil;
		_exportSubtitles = nil;
		_deleteAfterDownload = @NO;
        _urlReadPointer = 0;
        _useTransportStream = nil;
        _downloadStatus = @(0);
        _baseFileName = nil;
        _processProgress = 0.0;

        _previousCheck = [NSDate date];
    }
    return self;
}

-(void) setupNotifications {
    [self addObserver:self forKeyPath:@"downloadStatus" options:NSKeyValueObservingOptionNew context:nil];
    [self addObserver:self forKeyPath:@"processProgress" options:NSKeyValueObservingOptionOld context:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(skipModeUpdated:) name:kMTNotificationDownloadRowChanged object:nil];
   [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(formatMayHaveChanged) name:kMTNotificationFormatListUpdated object:nil];
}

-(id) copyWithZone:(NSZone *)zone {
    MTDownload *download = [[[self class] allocWithZone:zone] init];
    if (download) {
        download.show = _show;
        download.encodeFormat = _encodeFormat;
        download.downloadStatus= @(kMTStatusNew);
		download.exportSubtitles = _exportSubtitles;
		download.deleteAfterDownload = _deleteAfterDownload;
		download.useSkipMode = _useSkipMode;
		download.skipCommercials = _skipCommercials;
        download.markCommercials = _markCommercials;
        download.genTextMetaData = _genTextMetaData;
        [download prepareForDownload:NO];
		[download checkTransportStream];
        [download setupNotifications];
    }
    return download;
}

-(void) setShow:(MTTiVoShow *)show {
	if (show != _show) {
		if (_show) {
			[[NSNotificationCenter defaultCenter] removeObserver:self name:kMTNotificationFoundSkipModeInfo object: _show ];
			if (![tiVoManager sharedShowWith:self]) _show.isQueued = NO;
		}
		_show = show;
		if (show) {
			[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(skipModeUpdated:) name:kMTNotificationFoundSkipModeInfo object: show];
			show.isQueued = YES;
		}
	}
}
-(void) checkTransportStream {
	if (self.show.inProgress.boolValue || !self.show.tiVo) return; //not set up yet
	if (self.isDone) return; //no reason to change
	if (self.encodeFormat.isTestPS) {
		self.useTransportStream = @NO;  //if testing whether PS is bad, naturally don't use TS
	} else if (!self.useTransportStream) {
		if (!self.show.tiVo.supportsTransportStream) {
			self.useTransportStream = @NO;
		} else {
			switch (self.show.mpegFormat) {
				case MPEGFormatMPG2:    self.useTransportStream = @NO;  break;
				case MPEGFormatH264:    self.useTransportStream = @YES; break;
				case MPEGFormatUnknown:
				case MPEGFormatOther:
				default: {
					NSString * channelName = self.show.stationCallsign;
					switch ([ tiVoManager useTSForChannel:channelName]) {
						case NSOffState:
							self.useTransportStream = @NO;
							break;
						case NSOnState: //user specified TS for this channel
							self.useTransportStream = @YES;
							break;
						case NSMixedState: //user didn't specify for this channel, but did in general OR we've seen need
						default: {
							BOOL alwaysDownloadTS = [[NSUserDefaults standardUserDefaults] boolForKey:kMTDownloadTSFormat];
							NSCellStateValue channelPSFailed =    [tiVoManager failedPSForChannel:channelName];
							self.useTransportStream = @(alwaysDownloadTS || (channelPSFailed == NSOnState));
							break;
						}
					}
				}
			}
		}
	}
}

//always use this initializer; not init
+(MTDownload *) downloadForShow:(MTTiVoShow *) show withFormat: (MTFormat *) format withQueueStatus: (NSInteger) status {
    MTDownload * download = [[MTDownload alloc] init];
    download.show = show;
    download.encodeFormat = format;
    download.downloadStatus= @(status);
	[download checkTransportStream];
    [download setupNotifications];
    return download;
}

+(MTDownload *) downloadTestPSForShow:(MTTiVoShow *) show {
    MTDownload * download = [self downloadForShow:show
									   withFormat: [tiVoManager testPSFormat]
								  withQueueStatus: kMTStatusNew];
    return download;
}

-(void)prepareForDownload: (BOOL) notifyTiVo {
    //set up initial parameters for download before submittal; can also be used to resubmit while still in DL queue
    if (self.downloadStatus.intValue == kMTStatusDeleted) return;
    if (self.isInProgress) {
        [self cancel];
    }
    self.baseFileName = nil;
    self.processProgress = 0.0;
    if (self.encodeFormat.isTestPS) {
        self.numRetriesRemaining = 0;
        self.numStartupRetriesRemaining = 0;
    } else {
        self.numRetriesRemaining = (int) [[NSUserDefaults standardUserDefaults] integerForKey:kMTNumDownloadRetries];
        self.numStartupRetriesRemaining = kMTMaxDownloadStartupRetries;
    }
    self.downloadDirectory = nil;

	self.downloadStatus = @(kMTStatusNew);
	[self skipModeCheck]; //redundant
    if (notifyTiVo) {
		[self checkQueue];
	}
}

-(void)progressUpdated {
    [NSNotificationCenter postNotificationNameOnMainThread:kMTNotificationProgressUpdated object:self];
}

-(void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if ([keyPath compare:@"downloadStatus"] == NSOrderedSame) {
		DDLogMajor(@"Changing DL status of %@ to %@ (%@)", object, [(MTDownload *)object showStatus], [(MTDownload *)object downloadStatus]);
        [NSNotificationCenter postNotificationNameOnMainThread:kMTNotificationDownloadStatusChanged object:object];
		[self skipModeCheck];
		[self cancelPerformanceTimer];
		[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(checkStillActive) object:nil];
         if (self.isInProgress) {
             self.performanceTimer = [MTWeakTimer scheduledTimerWithTimeInterval:5 target:self selector:@selector(launchPerformanceTimer:) userInfo:nil repeats:NO];
             [self performSelector:@selector(checkStillActive) withObject:nil afterDelay:[[NSUserDefaults standardUserDefaults] integerForKey: kMTMaxProgressDelay]];
         }
		//if done downloading, then maybe taskchain needs to update progress
		if (self.downloadStatus.intValue == kMTStatusEncoding) {
			self.activeTaskChain.providesProgress = !(_encodeTask.progressCalc || _encodeTask.trackingRegEx);
		} else if (self.downloadStatus.intValue == kMTStatusCaptioning) {
			self.activeTaskChain.providesProgress = !(_captionTask.progressCalc || _captionTask.trackingRegEx);
		}
    } else if ([keyPath isEqualToString:@"processProgress"]) {
        double progressChange = ABS(self.processProgress - self.displayedProcessProgress);
        if (progressChange > 0.02 || self.processProgress >= 1.0) { //only update if enough changed or done.
            DDLogVerbose(@"%@ at %0.1f%%", self, self.processProgress*100);
           self.displayedProcessProgress = self.processProgress;
            [self progressUpdated];
        }
	} else {
		[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

- (void) formatMayHaveChanged{
    //if format list is updated, we need to ensure our format still exists
    //known bug: if name of current format changed, we will not find correct one
    self.encodeFormat = [tiVoManager findFormat:self.encodeFormat.name];
}

#pragma mark -
#pragma mark Performance timer for UI
-(void) launchPerformanceTimer:(NSTimer *) timer {
    //start Timer after 5 seconds
    self.performanceTimer = [MTWeakTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(updatePerformance:) userInfo:nil repeats:YES];
    self.startTimeForPerformance = [NSDate date];
    self.startProgressForPerformance = self.processProgress;
    DDLogVerbose(@"creating performance timer");
}

-(void) cancelPerformanceTimer {
    if (self.performanceTimer){
        [self.performanceTimer invalidate]; self.performanceTimer = nil;
        self.startTimeForPerformance = nil;
        self.speed = 0.0;
        DDLogVerbose(@"cancelling performance timer");
    }
}

-(void) updatePerformance: (NSTimer *) timer {
    if (self.startTimeForPerformance == nil) {
        [self cancelPerformanceTimer];
    } else {
        NSTimeInterval timeSoFar = -[self.startTimeForPerformance timeIntervalSinceNow];
        double recentSpeed =  self.show.fileSize * (self.processProgress-self.startProgressForPerformance)/timeSoFar;
        if (recentSpeed < 0.0) recentSpeed = 0.0;
        if (recentSpeed == 0.0) {
            self.numZeroSpeeds ++;
            if (self.numZeroSpeeds > 9) {
                //not getting much data; hide meter
                if (self.numZeroSpeeds == 10) {
                    self.speed = 0.0;
                    DDLogVerbose(@"ten measurements of zero; hide speed");
                    [self progressUpdated];
                }
            }
        } else {
            self.numZeroSpeeds = 0;
            if (self.speed <= 0.0) {
                self.speed = recentSpeed;
           } else {
                const double kSMOOTHING_FACTOR = 0.03;
                double newSpeed = kSMOOTHING_FACTOR * recentSpeed + (1-kSMOOTHING_FACTOR) * self.speed;
                DDLogVerbose(@"Speed was %0.1f; is %0.1f; ==> %0.1f",self.speed/1000, recentSpeed/1000, newSpeed/1000);
                self.speed = newSpeed; //exponential decay on older average
            }
            [self progressUpdated];
            self.startTimeForPerformance = [NSDate date];
            self.startProgressForPerformance = self.processProgress;
        }
    }
}

-(NSString *) timeLeft {
	if (self.downloadStatus.intValue == kMTStatusWaiting) {
		if (!self.downloadDelayStart) return nil;
		NSTimeInterval actualTimeLeft = self.downloadDelay - [[NSDate date] timeIntervalSinceDate: self.downloadDelayStart];
		return [NSString stringFromTimeInterval:  actualTimeLeft];
	}
    if (!self.isInProgress) return nil;
    if (self.speed == 0.0) return nil;
    NSTimeInterval actualTimeLeft = self.show.fileSize *(1-self.processProgress) /self.speed;
    if (actualTimeLeft == 0.0) return nil;
    return [NSString stringFromTimeInterval:  actualTimeLeft];
}

-(void) updateDownloadDelay {
	NSTimeInterval soFar = [[NSDate date] timeIntervalSinceDate: self.downloadDelayStart];
	NSTimeInterval length = self.downloadDelay;
	if (soFar > length) {
		self.downloadStatus = @(kMTStatusDownloading);
		self.processProgress = 0.0;
	} else {
		self.processProgress = soFar/length;
		[self performSelector:@selector(updateDownloadDelay) withObject:nil afterDelay:0.2];
	}
}

#pragma mark - Queue encoding/decoding methods for persistent queue, copy/paste, and drag/drop

- (void) encodeWithCoder:(NSCoder *)encoder {
	//necessary for cut/paste drag/drop. Not used for persistent queue, as we like having english readable pref lists
	//keep parallel with queueRecord
	DDLogVerbose(@"encoding %@",self);
	[self.show encodeWithCoder:encoder];
	[encoder encodeObject:[NSNumber numberWithBool:self.addToiTunesWhenEncoded] forKey: kMTSubscribediTunes];
	[encoder encodeObject:@(self.skipCommercials) forKey: kMTSubscribedSkipCommercials];
	[encoder encodeObject:@(self.useSkipMode) forKey: kMTSubscribedUseSkipMode];
	[encoder encodeObject:self.useTransportStream forKey: kMTSubscribedUseTS];
	[encoder encodeObject:@(self.markCommercials) forKey: kMTSubscribedMarkCommercials];
	[encoder encodeObject:self.encodeFormat.name forKey:kMTQueueFormat];
	[encoder encodeObject:self.downloadStatus forKey: kMTQueueStatus];
	[encoder encodeObject: self.encodeFilePath forKey: kMTQueueFinalFile] ;
	[encoder encodeObject: self.genTextMetaData forKey: kMTQueueGenTextMetaData];
	[encoder encodeObject: self.exportSubtitles forKey:	kMTQueueExportSubtitles];
	[encoder encodeObject: self.deleteAfterDownload forKey:	kMTQueueDeleteAfterDownload];
}

- (NSDictionary *) queueRecord {
	//used for persistent queue, as we like having english-readable pref lists
	//keep parallel with encodeWithCoder
	//need to watch out for a nil object ending the dictionary too soon.

	NSMutableDictionary *result = [NSMutableDictionary dictionaryWithObjectsAndKeys:
								   @(self.show.showID), kMTQueueID,
								   @(self.addToiTunesWhenEncoded), kMTSubscribediTunes,
								   @(self.skipCommercials), kMTSubscribedSkipCommercials,
								   @(self.useSkipMode), kMTSubscribedUseSkipMode,
								   @(self.markCommercials), kMTSubscribedMarkCommercials,
								   self.show.showTitle, kMTQueueTitle,
								   self.show.tiVoName, kMTQueueTivo,
								   nil];
	if (self.useTransportStream) [result setValue:self.useTransportStream forKey:kMTSubscribedUseTS];
	if (self.encodeFormat.name) [result setValue:self.encodeFormat.name forKey:kMTQueueFormat];
	if (self.downloadStatus)    [result setValue:self.downloadStatus forKey:kMTQueueStatus];
	if (self.encodeFilePath)    [result setValue:self.encodeFilePath forKey: kMTQueueFinalFile];
	if (self.genTextMetaData)   [result setValue:self.genTextMetaData forKey: kMTQueueGenTextMetaData];
	if (self.exportSubtitles) [result setValue:self.exportSubtitles forKey: kMTQueueExportSubtitles];
	if (self.deleteAfterDownload) [result setValue:self.deleteAfterDownload forKey: kMTQueueDeleteAfterDownload];

	return [NSDictionary dictionaryWithDictionary: result];
}

-(BOOL) isSameAs:(NSDictionary *) queueEntry {
	NSInteger queueID = [queueEntry[kMTQueueID] integerValue];
	BOOL result = (queueID == self.show.showID) && ([self.show.tiVoName compare:queueEntry[kMTQueueTivo]] == NSOrderedSame);
	if (result && [self.show.showTitle compare:queueEntry[kMTQueueTitle]] != NSOrderedSame) {
		DDLogReport(@"Very odd, but reloading anyways: same ID: %ld same TiVo:%@ but different titles: <<%@>> vs <<%@>>",queueID, queueEntry[kMTQueueTivo], self, queueEntry[kMTQueueTitle] );
	}
	return result;
	
}

+(MTDownload *) downloadFromQueue:queueEntry {

	MTTiVoShow *fakeShow = [[MTTiVoShow alloc] init];
	fakeShow.showID   = [(NSNumber *)queueEntry[kMTQueueID] intValue];
	[fakeShow setShowSeriesAndEpisodeFrom: queueEntry[kMTQueueTitle]];
	fakeShow.tempTiVoName = queueEntry[kMTQueueTivo] ;
	fakeShow.protectedShow = @YES; //until we matchup with show or not.

    MTFormat * format = [tiVoManager findFormat: queueEntry[kMTQueueFormat]]; //bug here: will not be able to restore a no-longer existent format, so will substitue with first one available, which is wrong for completed/failed entries
    NSInteger queueStatus = ((NSNumber *)queueEntry[kMTQueueStatus]).integerValue;
    if (queueStatus < kMTStatusDone) queueStatus = kMTStatusNew;

    MTDownload *download = [MTDownload downloadForShow:fakeShow withFormat:format  withQueueStatus: queueStatus];
    if (format.isTestPS) {
        download.numRetriesRemaining = 0;
        download.numStartupRetriesRemaining = 0;
    } else {
        download.numRetriesRemaining = (int) [[NSUserDefaults standardUserDefaults] integerForKey:kMTNumDownloadRetries];
        download.numStartupRetriesRemaining = kMTMaxDownloadStartupRetries;
    }
	download.addToiTunesWhenEncoded = [queueEntry[kMTSubscribediTunes ]  boolValue];
	download.skipCommercials = [queueEntry[kMTSubscribedSkipCommercials ]  boolValue];
	download.useSkipMode = [queueEntry[kMTSubscribedUseSkipMode ]  boolValue]; //could be nil, but that works.
	download.useTransportStream = (NSNumber *) queueEntry[kMTSubscribedUseTS ];
	download.markCommercials = [queueEntry[kMTSubscribedMarkCommercials ]  boolValue];

	if (download.isInProgress || download.downloadStatus.intValue == kMTStatusAwaitingPostCommercial) {
		download.downloadStatus = @kMTStatusNew;		//until we can launch an in-progress item
	}
	download.encodeFilePath = queueEntry[kMTQueueFinalFile];
	download.genTextMetaData = queueEntry[kMTQueueGenTextMetaData]; if (!download.genTextMetaData) download.genTextMetaData= @(NO);
	download.exportSubtitles = queueEntry[kMTQueueExportSubtitles]; if (!download.exportSubtitles) download.exportSubtitles= @(NO);
	download.deleteAfterDownload = queueEntry[kMTQueueDeleteAfterDownload]; if (!download.deleteAfterDownload) download.deleteAfterDownload= @NO;
    return download;
}

- (id)initWithCoder:(NSCoder *)decoder {
	//keep parallel with updateFromDecodedShow
	if ((self = [self init])) {
		//NSString *title = [decoder decodeObjectOfClass:[NSString class] forKey:kTitleKey];
		//float rating = [decoder decodeFloatForKey:kRatingKey];
		self.show = [[MTTiVoShow alloc] initWithCoder:decoder ];
		self.addToiTunesWhenEncoded= [[decoder decodeObjectOfClass:[NSNumber class] forKey: kMTSubscribediTunes] boolValue];
//		self.simultaneousEncode	 =   [decoder decodeObjectOfClass:[NSNumber class] forKey: kMTSubscribedSimulEncode];
		self.skipCommercials   =     [[decoder decodeObjectOfClass:[NSNumber class] forKey: kMTSubscribedSkipCommercials] boolValue];
		self.useSkipMode   =    [[decoder decodeObjectOfClass:[NSNumber class] forKey: kMTSubscribedUseSkipMode] boolValue];
		self.useSkipMode   =    [[decoder decodeObjectOfClass:[NSNumber class] forKey: kMTSubscribedUseTS] boolValue];
		self.markCommercials   =    [[decoder decodeObjectOfClass:[NSNumber class] forKey: kMTSubscribedMarkCommercials] boolValue];
		NSString * encodeName	 = [decoder decodeObjectOfClass:[NSString class] forKey:kMTQueueFormat];
		self.encodeFormat =	[tiVoManager findFormat: encodeName]; //minor bug here: will not be able to restore a no-longer existent format, so will substitue with first one available, which is then wrong for completed/failed entries
		self.downloadStatus		 = [decoder decodeObjectOfClass:[NSNumber class] forKey: kMTQueueStatus];
		self.encodeFilePath = [decoder decodeObjectOfClass:[NSString class] forKey:kMTQueueFinalFile];
		self.genTextMetaData = [decoder decodeObjectOfClass:[NSNumber class] forKey:kMTQueueGenTextMetaData]; if (!self.genTextMetaData) self.genTextMetaData= @(NO);
		self.exportSubtitles = [decoder decodeObjectOfClass:[NSNumber class] forKey:kMTQueueExportSubtitles]; if (!self.exportSubtitles) self.exportSubtitles= @(NO);
		self.deleteAfterDownload = [decoder decodeObjectOfClass:[NSNumber class] forKey:kMTQueueDeleteAfterDownload]; if (!self.deleteAfterDownload) self.deleteAfterDownload= @(NO);
        [self setupNotifications];
	}
	DDLogDetail(@"initWithCoder for %@",self);
	return self;
}

+(BOOL) supportsSecureCoding {
    return YES;
}

-(void) convertProxyToRealForShow:(MTTiVoShow *) show {
	MTTiVoShow * formerShow = self.show;
    self.show = show;
    show.isQueued = YES;
	[self checkTransportStream];
	if (formerShow.rpcData && !show.rpcData) show.rpcData = formerShow.rpcData;
	if (self.downloadStatus.integerValue == kMTStatusDeleted || [formerShow.imageString isEqualToString:@"deleted"]) {
		DDLogDetail(@"Tivo restored previously deleted show %@",show);
		if (self.downloadStatus.intValue == kMTStatusDeleted){
			self.downloadStatus = @(kMTStatusNew);
		}
		if ( self.isNew ) { //inProgress is fine, as is completelyDone.
			[self prepareForDownload:YES];
		}
	}
	[self skipModeCheck];
}

-(BOOL) isSimilarTo:(MTDownload *) testDownload {
    //not isEqualTo, as we only want to use with pasteboard copies, not in real arrays.
	if (testDownload == self) return YES;
    if (!testDownload || ![testDownload isKindOfClass:MTDownload.class]) {
		return NO;
	}
	return ([self.show isEqual:testDownload.show] &&
			[self.encodeFormat isEqual: testDownload.encodeFormat] &&
            (self.encodeFilePath == testDownload.encodeFilePath ||
			 [self.encodeFilePath isEqualToString:testDownload.encodeFilePath]));
}

-(NSUInteger) hash {
    return [self.show hash] ^
    [self.encodeFormat hash] ^
    [self.encodeFilePath hash];
}

- (id)pasteboardPropertyListForType:(NSString *)type {
	//	NSLog(@"QQQ:pboard Type: %@",type);
	if ([type compare:kMTDownloadPasteBoardType] ==NSOrderedSame) {
		return  [NSKeyedArchiver archivedDataWithRootObject:self];
	} else if ([type isEqualToString:(NSString *)kUTTypeFileURL] && self.encodeFilePath) {
		NSURL *URL = [NSURL fileURLWithPath:self.encodeFilePath isDirectory:NO];
		id temp =  [URL pasteboardPropertyListForType:(id)kUTTypeFileURL];
		return temp;
    } else if ( [type isEqualToString:NSPasteboardTypeString]) {
        return [self.show pasteboardPropertyListForType:type] ;
	} else {
		return nil;
	}
}
-(NSArray *)writableTypesForPasteboard:(NSPasteboard *)pasteboard {
	NSArray* result = @[kMTDownloadPasteBoardType , (NSString *)kUTTypeFileURL, NSPasteboardTypeString];  
	return result;
}

- (NSPasteboardWritingOptions)writingOptionsForType:(NSString *)type pasteboard:(NSPasteboard *)pasteboard {
	return 0;
}

+ (NSArray *)readableTypesForPasteboard:(NSPasteboard *)pasteboard {
	return @[kMTDownloadPasteBoardType];
}

+ (NSPasteboardReadingOptions)readingOptionsForType:(NSString *)type pasteboard:(NSPasteboard *)pasteboard {
	if ([type compare:kMTDownloadPasteBoardType] ==NSOrderedSame)
		return NSPasteboardReadingAsKeyedArchive;
	return 0;
}

#pragma mark - Configure files

//Method called at the beginning of the download to configure all required files and file handles
-(void)deallocDownloadHandling {
	self.commercialFilePath = nil;
	self.commercialFilePath = nil;
	self.encodeFilePath = nil;
	self.bufferFilePath = nil;
	self.urlBuffer = nil;
	if (self.bufferFileReadHandle ) {
		[self.bufferFileReadHandle closeFile];
		self.bufferFileReadHandle = nil;
	}
	if (self.bufferFileWriteHandle) {
		[self.bufferFileWriteHandle closeFile];
		self.bufferFileWriteHandle = nil;
	}
}

-(BOOL)configureBaseFileNameAndDirectory {
	if (!self.baseFileName) {
        // generate only once
        NSMutableArray * optionArray = [NSMutableArray array];
        if (self.skipCommercials) {
			[optionArray addObject:@"Cut"];
		}
        if (self.markCommercials) {
			[optionArray addObject:@"Mark"];
		}
        if (self.useSkipMode) {
			[optionArray addObject:@"SkipMode"];
		}
		if (self.exportSubtitles.boolValue) {
			[optionArray addObject:@"Subtitle"];
		}
		NSString * options = optionArray.count == 0 ? @"" : [optionArray componentsJoinedByString:@","];
        NSString * downloadName = [self.show downloadFileNameWithFormat:self.encodeFormat.name andOptions:options  createIfNecessary:YES];
		if (!downloadName) return NO;
        self.downloadDirectory = [downloadName stringByDeletingLastPathComponent];
		self.tmpDirectory = tiVoManager.tmpFilesDirectory;
        NSString * baseTitle = [downloadName lastPathComponent];
		if (!baseTitle) return NO;
		self.baseFileName = [self createUniqueBaseFileName:baseTitle ];
	}
    return self.baseFileName ? YES : NO;
}

-(void) markCompleteCTiVoFile:(NSString *) path {
    //This is for a checkpoint and tell us the file is complete with show ID
    [path setXAttr:kMTXATTRFileComplete toValue:self.show.idString];

}

-(BOOL) isCompleteCTiVoFile: (NSString *) path forFileType: (NSString *) fileType {
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:path]) {
        NSString *tiVoID = [path getXAttr:kMTXATTRFileComplete];
        if ([tiVoID compare:self.show.idString] == NSOrderedSame) {
            DDLogMajor(@"Found Complete %@ File at %@", fileType, path);
            return YES;
        }
    }
    return NO;
}

-(NSString *)createUniqueBaseFileName:(NSString *)baseName {
	if (!baseName) {
		DDLogReport(@"No basename for %@!",self);
		return nil;
	}
	NSFileManager *fm = [NSFileManager defaultManager];
    NSString * tmpDir = self.tmpDirectory;
	if (!tmpDir) {
		DDLogReport(@"No temporary directory for %@!",self);
		return nil;
	}
    NSString * downloadDir = [self downloadDirectory];
    NSString * extension = self.useTransportStream.boolValue ? self.encodeFormat.transportStreamExtension :
                                                     self.encodeFormat.filenameExtension;
    NSString *trialEncodeFilePath = [NSString stringWithFormat:@"%@/%@%@",downloadDir,baseName,extension];
	NSString *trialLockFilePath = [NSString stringWithFormat:@"%@/%@.lck" ,tmpDir,baseName];
	self.tivoFilePath = [NSString stringWithFormat:@"%@/buffer%@.tivo",tmpDir,baseName];
//	self.mpgFilePath = [NSString stringWithFormat:@"%@/buffer%@.mpg",tmpDir,baseName];
    BOOL tivoFileExists = NO; // [self isCompleteCTiVoFile:self.tivoFilePath forFileType:@"TiVo"];  Note: if tivFileExists, then stomps on file w/ current basename!
    
    self.downloadingShowFromTiVoFile = NO;

    BOOL mpgFileExists = NO; //[self isCompleteCTiVoFile: self.mpgFilePath forFileType:@"MPEG"];
        if (mpgFileExists) {
            self.downloadingShowFromTiVoFile = NO;
         self.downloadingShowFromMPGFile = NO;
    }
	if (tivoFileExists || mpgFileExists) {  //we're using an existing file so start the next download
            [NSNotificationCenter postNotificationNameOnMainThread:kMTNotificationTransferDidFinish object:self.show.tiVo afterDelay:kMTTiVoAccessDelay];
	}
	if (([fm fileExistsAtPath:trialEncodeFilePath] || [fm fileExistsAtPath:trialLockFilePath]) && !tivoFileExists  && !mpgFileExists) { //If .tivo file exits assume we will use this and not download.
		NSString * nextBase;
		NSRegularExpression *ending = [NSRegularExpression regularExpressionWithPattern:@"(.*)-([0-9]+)$" options:NSRegularExpressionCaseInsensitive error:nil];
		NSTextCheckingResult *result = [ending firstMatchInString:baseName options:NSMatchingWithoutAnchoringBounds range:NSMakeRange(0, (baseName).length)];
		if (result) {
			int n = [[baseName substringWithRange:[result rangeAtIndex:2]] intValue];
			DDLogVerbose(@"found output file named %@, incrementing to version number %d", baseName, n+1);
			nextBase = [[baseName substringWithRange:[result rangeAtIndex:1]] stringByAppendingFormat:@"-%d",n+1];
		} else {
			nextBase = [baseName stringByAppendingString:@"-1"];
			DDLogVerbose(@"found output file named %@, adding version number", baseName);
		}
		return [self createUniqueBaseFileName:nextBase ];
		
	} else {
		DDLogDetail(@"Using baseFileName %@",baseName);
		self.nameLockFilePath = trialLockFilePath;
		[[NSFileManager defaultManager] createFileAtPath:self.nameLockFilePath contents:[NSData data] attributes:nil];  //Creating the lock file
		return baseName;
	}
	
}

-(long long) spaceAvailable:(NSString *) path {
	NSError *error = nil;
	if (@available(macOS 10.13, *)) {
		NSURL *fileURL = [[NSURL alloc] initFileURLWithPath:path];
		NSDictionary *results = [fileURL resourceValuesForKeys:@[NSURLVolumeAvailableCapacityForImportantUsageKey] error:&error];
		NSNumber * value = results[NSURLVolumeAvailableCapacityForImportantUsageKey];
		if (!value || error) {
			DDLogReport(@"Error retrieving Important Volume key for %@: %@\n%@", path, [error localizedDescription], [error userInfo]);
			return LLONG_MAX;
		} else if (value.integerValue == 0) {
			//ZFS and SANs may return 0.
			results = [fileURL resourceValuesForKeys:@[NSURLVolumeAvailableCapacityKey] error:&error];
			value = results[NSURLVolumeAvailableCapacityKey];
			if (!value || error) {
				DDLogReport(@"Error retrieving Volme Available key for %@: %@\n%@", path, [error localizedDescription], [error userInfo]);
				return LLONG_MAX;
			} else if (value.longLongValue == 0){
				DDLogReport(@"Volume for %@ shows zero space", path);
				return 0;
			} else {
				return value.longLongValue;
			}

		} else {
			DDLogDetail(@"Got space for %@: %@", path, value);
			return value.longLongValue;
		}
	} else {
    	NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfFileSystemForPath:path error:&error];
    	if (error || !attributes) return LLONG_MAX;
    	return  ( (NSNumber *)[attributes objectForKey:NSFileSystemFreeSize]).longLongValue;
	}
}

-(BOOL) shouldUseMemoryBuffer {
	return [[NSUserDefaults standardUserDefaults] boolForKey:kMTUseMemoryBufferForDownload] &&
	 !(self.useSkipMode && self.markCommercials); //else might need the whole file later for post-commercial
}

-(BOOL)configureFiles {
    DDLogDetail(@"configuring files for %@",self);
	//Release all previous attached pointers
    [self deallocDownloadHandling];
    self.downloadingShowFromTiVoFile = NO;
    self.downloadingShowFromMPGFile = NO;

    NSFileManager *fm = [NSFileManager defaultManager];
    if (! [self configureBaseFileNameAndDirectory]) {
        return NO;
    }
    long long tmpSpace = [self spaceAvailable: self.tmpDirectory];
    long long downloadSpace = [self spaceAvailable: self.downloadDirectory];
    long long fileSize = self.show.fileSize;
    if (!self.encodeFormat.isTestPS) {
		DDLogVerbose(@"Checking Space Available: %lldMB tmp and %lldMB file", tmpSpace/1000000, downloadSpace/1000000);

		if ((tmpSpace == downloadSpace  && downloadSpace < 1.5 * fileSize) ||
			// both on same drive
			(downloadSpace < fileSize))  {
			[tiVoManager pauseQueue:nil];
			DDLogReport(@"Disk space problem: %lldMB tmp and %lldMB download vs %lldMB fileSize", tmpSpace/1000000, downloadSpace/1000000, fileSize/1000000);
			[self notifyUserWithTitle:@"Pausing downloads: Your download disk is low on space" subTitle:@"Probably need to delete some files."];
		   return NO;
		} else if (tmpSpace < fileSize)  {
			[tiVoManager pauseQueue:nil];
			DDLogReport(@"Disk space problem: %lldMB tmp and %lld download vs %lld fileSize", tmpSpace/1000000, downloadSpace/1000000, fileSize/1000000);
			[self notifyUserWithTitle:@"Pausing downloads: Your temporary or boot drive is low on space" subTitle:@"Probably need to delete some files."];
		   return NO;
		}
	}
    NSString * warning = nil;
    if (downloadSpace < tiVoManager.sizeOfShowsToDownload) {
        warning =  @"Warning: you may be getting low on disk space";
    } else if (tmpSpace < tiVoManager.biggestShowToDownload ) {
        warning =  @"Warning: you may be getting low on temporary space";
    }
    if (warning) {
		DDLogMajor(@"Disk space warning: %lldMB tmp and %lldMB download vs %lldMB biggest show and %lldMB total shows", tmpSpace/1000000, downloadSpace/1000000, tiVoManager.biggestShowToDownload/1000000, tiVoManager.sizeOfShowsToDownload/1000000);
        [tiVoManager notifyForName: self.show.showTitle
                         withTitle: warning
                          subTitle: @"Should you delete some files?"
                          isSticky: NO
         ];
   }
    if (!self.downloadingShowFromTiVoFile && !self.downloadingShowFromMPGFile) {  //We need to download from the TiVo
        if ([self shouldUseMemoryBuffer]) {
            self.bufferFilePath = [NSString stringWithFormat:@"%@/buffer%@.bin",self.tmpDirectory,self.baseFileName];
            DDLogVerbose(@"downloading to memory; buffer: %@", self.bufferFilePath);
            self.urlBuffer = [NSMutableData new];
            self.urlReadPointer = 0;
            self.bufferFileReadHandle = nil;
        } else {
            self.bufferFilePath = [NSString stringWithFormat:@"%@/buffer%@.tivo",self.tmpDirectory,self.baseFileName];
            DDLogVerbose(@"downloading to file: %@", self.bufferFilePath);
            [fm createFileAtPath:self.bufferFilePath contents:[NSData data] attributes:nil];
            self.bufferFileWriteHandle = [NSFileHandle fileHandleForWritingAtPath:self.bufferFilePath];
           self. bufferFileReadHandle = [NSFileHandle fileHandleForReadingAtPath:self.bufferFilePath];
            self.urlBuffer = nil;
        }
    }
    if (!self.downloadingShowFromMPGFile) {
        self.decryptedFilePath = [NSString stringWithFormat:@"%@/buffer%@.mpg",self.tmpDirectory,self.baseFileName];
        DDLogVerbose(@"setting decrypt path: %@", self.decryptedFilePath);
        [[NSFileManager defaultManager] createFileAtPath:self.decryptedFilePath contents:[NSData data] attributes:nil];
    }
    NSString * extension = self.useTransportStream.boolValue ? self.encodeFormat.transportStreamExtension :
                                                     self.encodeFormat.filenameExtension;
	self.encodeFilePath = [NSString stringWithFormat:@"%@/%@%@",self.downloadDirectory,self.baseFileName,extension];
	DDLogVerbose(@"setting encodepath: %@", self.encodeFilePath);
    self.captionFilePath = [NSString stringWithFormat:@"%@/%@.srt",self.downloadDirectory ,self.baseFileName];
    DDLogVerbose(@"setting self.captionFilePath: %@", self.captionFilePath);
#ifdef SANDBOX
	self.tempEncodeFilePath = [NSString stringWithFormat:@"%@/%@%@",self.tmpDirectory,self.baseFileName,extension];
	self.tempCaptionFilePath = [NSString stringWithFormat:@"%@/%@.srt",self.tmpDirectory ,self.baseFileName];
#else
	self.tempEncodeFilePath = self.encodeFilePath;
	self.tempCaptionFilePath = self.captionFilePath;
#endif
	
    self.commercialFilePath = [NSString stringWithFormat:@"%@/buffer%@.edl" ,self.tmpDirectory, self.baseFileName];  //0.92 version
    DDLogVerbose(@"setting self.commercialFilePath: %@", self.commercialFilePath);
	
	if (!self.encodeFormat.isTestPS) {
        [self.show artWorkImage];  //make sure it's available by time we finish
 	}
    return YES;
}

-(NSString *) encoderPath {
	NSString *encoderLaunchPath = [self.encodeFormat pathForExecutable];
    if (!encoderLaunchPath) {
        DDLogReport(@"Encoding of %@ failed for %@ format, encoder %@ not found",self,self.encodeFormat.name,self.encodeFormat.encoderUsed);
        return nil;
    } else {
        DDLogVerbose(@"using encoder: %@", encoderLaunchPath);
		return encoderLaunchPath;
	}
}

#pragma mark - Download processing Methods

//should be in an NSMutableArray extension
-(void)addArguments:(NSString *)argString toArray:(NSMutableArray *) arguments {
    if (argString.length == 0) return;
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"([^\\s\"\']+)|\"(.*?)\"|'(.*?)'" options:NSRegularExpressionCaseInsensitive error:nil];
	NSArray *matches = [regex matchesInString:argString options:NSMatchingWithoutAnchoringBounds range:NSMakeRange(0, argString.length)];
	NSMutableArray *newArgs = [NSMutableArray array];
	for (NSTextCheckingResult *tr in matches) {
		NSUInteger j;
		for ( j=1; j<tr.numberOfRanges; j++) {
			if ([tr rangeAtIndex:j].location != NSNotFound) {
				break;
			}
		}
		[newArgs addObject:[argString substringWithRange:[tr rangeAtIndex:j]]];
	}
    if (newArgs.count > 0) {
        [arguments addObjectsFromArray:newArgs];
    }
}

-(void)addArgument:(NSString *)argString toArray:(NSMutableArray *) arguments {
    NSString * trimString = [argString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if (trimString.length > 0) [arguments addObject:trimString];
}

-(BOOL) isArgument:(NSString *) argString {
    NSString * trimString = [argString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    return trimString.length > 0;
}

-(NSMutableArray *)encodingArgumentsWithInputFile:(NSString *)inputFilePath outputFile:(NSString *)outputFilePath
{
	NSMutableArray *arguments = [NSMutableArray array];
    MTFormat * f = self.encodeFormat;
	BOOL includeEDL = [f.comSkip boolValue] && self.skipCommercials && [self isArgument:f.edlFlag ];
	[self addArguments:f.encoderEarlyVideoOptions toArray:arguments];
	[self addArguments:f.encoderEarlyAudioOptions toArray:arguments];
	[self addArguments:f.encoderEarlyOtherOptions toArray:arguments];
    if ( [self isArgument: f.outputFileFlag] ) {
        [self addArgument: f.outputFileFlag toArray:arguments];
        [self addArgument: outputFilePath toArray:arguments];
		if (includeEDL) {
            [self addArgument:f.edlFlag toArray:arguments];
            [self addArgument:self.commercialFilePath toArray:arguments];
		}
        if ([self isArgument: f.inputFileFlag ]) {
            [self addArgument:f.inputFileFlag toArray:arguments];
            [self addArgument:inputFilePath toArray:arguments];
			[self addArguments:f.encoderLateVideoOptions toArray:arguments];
			[self addArguments:f.encoderLateAudioOptions toArray:arguments];
			[self addArguments:f.encoderLateOtherOptions toArray:arguments];
        } else {
            [self addArgument:inputFilePath toArray:arguments];
		}
    } else {
		if (includeEDL) {
            [self addArgument:f.edlFlag toArray:arguments];
            [self addArgument:self.commercialFilePath toArray:arguments];
		}
        [self addArgument:f.inputFileFlag toArray:arguments];
        [self addArgument:inputFilePath toArray:arguments];
        [self addArguments:f.encoderLateVideoOptions toArray:arguments];
        [self addArguments:f.encoderLateAudioOptions toArray:arguments];
        [self addArguments:f.encoderLateOtherOptions toArray:arguments];
        [self addArgument:outputFilePath toArray:arguments];
    }
	return arguments;
}

-(MTTask *)mpegTask {
	//cancels current download if MP2 file and reschedules as Program Stream
	MTTask *mpegTask = [MTTask taskWithName:@"mpegCheck" download:self];
	[mpegTask setLaunchPath:[[NSBundle mainBundle] pathForAuxiliaryExecutable:@"ffmpeg"]];
	[mpegTask setArguments:@[@"-i",@"pipe:"]];
	mpegTask.successfulExitCodes = @[@0,@1]; //just want text; expected to return 1
//	[[NSFileManager defaultManager] createFileAtPath:self.mpegCheckFilePath contents:[NSData data] attributes:nil];
//	NSFileHandle *file = [NSFileHandle fileHandleForWritingAtPath:self.mpegCheckFilePath];
	//mpegTask.standardOutput = file;
	mpegTask.requiresInputPipe = YES;
	mpegTask.requiresOutputPipe = NO;
	mpegTask.terminatesEarly = YES;
	mpegTask.shouldReschedule  = NO;  //expected to fail, but other tasks should continue
	
	__weak __typeof__(self) weakSelf = self;
	NSString * errFilePath = mpegTask.errorFilePath ;
	mpegTask.cleanupHandler = ^(){
		__typeof__(self) strongSelf = weakSelf;
		if (! [[NSFileManager defaultManager] fileExistsAtPath:errFilePath] ) {
			if (!strongSelf.isCanceled) DDLogReport(@"Warning: %@: File %@ not found after mpegTask completion", strongSelf, errFilePath );
			return;
		}
		NSString *log = [NSString stringWithEndOfFile:errFilePath ];
		//for future reference; mpegts ==> transport stream; h264 => h.264 video; "Input #0, mpeg," == program stream
		if ([log contains:@"mpegts"]) {
			if ([log contains:@"mpeg2video"]) {
				DDLogReport(@"Found Mpeg2 video in Transport Stream. Rescheduling");
				DDLogDetail(@"%@", log);
				strongSelf.useTransportStream = @NO;
				[strongSelf markMyChannelAsPSOnly];
				[strongSelf rescheduleDownloadFalseStart];
			} else if ([log contains: @"h264"]) { //good file
				[strongSelf markMyChannelAsTSOnly];
			} else {
				DDLogReport(@"Neither MPEG2 nor H.264 video in %@: %@", strongSelf, log);
			}
		} else { //program Stream
			if ([log contains:@"mpeg2video"]) {
				DDLogMajor(@"Program stream test passed for %@ on %@",strongSelf, strongSelf.show.stationCallsign);
				[strongSelf markMyChannelAsPSOnly];
			} else {
				[strongSelf handleNewTSChannel];
				if (! strongSelf.encodeFormat.isTestPS) {
					[strongSelf rescheduleDownloadFalseStart];
				}
			}
			if (strongSelf.encodeFormat.isTestPS) {
				[strongSelf cancel];
				strongSelf.processProgress = 1.0;
				strongSelf.downloadStatus = @(kMTStatusDone);
			}
		}
	};
	DDLogVerbose(@"MPEG task created");
	return mpegTask;
}

-(MTTask *)catTask:(NSString *)outputFilePath
{
    return [self catTask:outputFilePath withInputFile:nil];
}

-(MTTask *)catTask:(id)outputFile withInputFile:(id)inputFile
{
    if (outputFile && !([outputFile isKindOfClass:[NSString class]] || [outputFile isKindOfClass:[NSFileHandle class]])) {
        DDLogMajor(@"catTask must be called with output file either nil, NSString or NSFileHandle");
        return nil;
    }
    if (inputFile && !([inputFile isKindOfClass:[NSString class]] || [inputFile isKindOfClass:[NSFileHandle class]])) {
        DDLogMajor(@"catTask must be called with input file either nil, NSString or NSFileHandle");
        return nil;
    }
    MTTask *catTask = [MTTask taskWithName:@"cat" download:self];
    [catTask setLaunchPath:@"/bin/cat"];
    if (outputFile && [outputFile isKindOfClass:[NSString class]]) {
        [catTask setStandardOutput:[NSFileHandle fileHandleForWritingAtPath:outputFile]];
        catTask.requiresOutputPipe = NO;
    } else if(outputFile){
        [catTask setStandardOutput:outputFile];
        catTask.requiresOutputPipe = NO;
    }
    if (inputFile && [inputFile isKindOfClass:[NSString class]]) {
        [catTask setStandardInput:[NSFileHandle fileHandleForReadingAtPath:inputFile]];
        catTask.requiresInputPipe = NO;
    } else if (inputFile) {
        [catTask setStandardInput:inputFile];
        catTask.requiresInputPipe = NO;
    }
    if ([outputFile isKindOfClass:[NSString class]]) {
		__weak __typeof__(self) weakSelf = self;
        catTask.completionHandler = ^BOOL(){
            if (!weakSelf.isCanceled && ! [[NSFileManager defaultManager] fileExistsAtPath:outputFile] ) {
                DDLogReport(@"Warning: %@: File %@ not found after cat completion", weakSelf, outputFile );
            }
            return YES;
        };
    }
    DDLogVerbose(@"Cat task: From %@ to %@ = %@",inputFile?:@"stdIn", outputFile?:@"stdOut", catTask);
    return catTask;
}
-(void) checkDecodeLog {
    NSString *log = [NSString stringWithEndOfFile:_decryptTask.errorFilePath ];
    if (log && log.length > 25 ) {
        NSRange badMAKRange = [log rangeOfString:@"Invalid MAK"];
        if (badMAKRange.location != NSNotFound) {
            DDLogMajor(@"tivodecode failed with 'Invalid MAK' error message");
            DDLogDetail(@"log file: %@",[log maskMediaKeys]);
			if (self.useTransportStream.boolValue) {
				[self notifyUserWithTitle:@"Decoding Failed" subTitle: @"Either an invalid Media Access Key or just a damaged file." ];
			} else {
				[self notifyUserWithTitle:@"Decoding Failed" subTitle: @"Possibly invalid Media Access Key? Or try Transport Stream, or maybe just a damaged file." ];
			}
        }
    }
}

-(MTTask *)decryptTask  //Decrypting is done in parallel with download so no progress indicators are needed.
{
    if (_decryptTask) {
        return _decryptTask;
    }
	MTTask *decryptTask = [MTTask taskWithName:@"decrypt" download:self];
	if (self.encodeFormat.isEncryptedDownload) {
		//don't use decrypt, just copy file to disk
		[decryptTask setLaunchPath:@"/bin/cat"];
		decryptTask.requiresOutputPipe = YES;
		_decryptTask = decryptTask;
		return _decryptTask;
	}
	NSString * decoder = [[NSUserDefaults standardUserDefaults] objectForKey:kMTDecodeBinary];
    NSString * decryptPath = nil;
    NSString * libreJar = nil;
    if ([decoder isEqualToString:@"TivoLibre"]) {
        // NSFileManager * fm = [NSFileManager defaultManager];
        decryptPath = @"/usr/bin/java";
        libreJar = [[NSBundle mainBundle] pathForResource: @"tivo-libre" ofType:@"jar"];
    } else {
        decryptPath = [[NSBundle mainBundle] pathForAuxiliaryExecutable: decoder];
    }
    if (!decryptPath) { //should never happen, but did once.
        [self notifyUserWithTitle:[NSString stringWithFormat:@"Can't Find %@", decoder]
                         subTitle:@"Please go to " kcTiVoName @" site for help!"];
        DDLogReport(@"Fatal Error: decoder %@ not found???", decoder);
        return nil;
    }
    [decryptTask setLaunchPath:decryptPath] ;
    decryptTask.successfulExitCodes = @[@0,@6];
	__weak __typeof__(self) weakSelf = self;

    decryptTask.completionHandler = ^BOOL(){
		__typeof__(self) strongSelf = weakSelf;
		if (!strongSelf) return NO;
        if (!strongSelf.shouldSimulEncode) {
            if (strongSelf.downloadStatus.intValue < kMTStatusDownloaded ) {
                strongSelf.downloadStatus = @(kMTStatusDownloaded);
            }
            [NSNotificationCenter  postNotificationNameOnMainThread:kMTNotificationDecryptDidFinish object:nil];
            if (strongSelf.decryptedFilePath) {
                [strongSelf markCompleteCTiVoFile: strongSelf.decryptedFilePath ];
            }
        }

        [strongSelf checkDecodeLog];
		return YES;
    };
	
	decryptTask.terminationHandler = ^(){
        [weakSelf checkDecodeLog];
	};
    
    if (self.downloadingShowFromTiVoFile) {
        [decryptTask setStandardError:decryptTask.logFileWriteHandle];
		NSUInteger fileSize = self.show.fileSize ?: 1000000000; //defensive
        decryptTask.progressCalc = ^(NSString *data){
            NSArray *lines = [data componentsSeparatedByString:@"\n"];
            double position = 0.0;
            for (NSInteger lineNum =  lines.count-2; lineNum >= 0; lineNum--) {
                NSString * line = [lines objectAtIndex:lineNum];
                NSArray * words = [line componentsSeparatedByString:@":"]; //always 1
                position= [[words objectAtIndex:0] doubleValue];
                if (position  > 0) {
                    return (position/fileSize);
                }
            };
            return 0.0;
        };
    }

	NSArray *arguments = nil;
	if (self.shouldPipeFromDecrypt) {
		decryptTask.requiresOutputPipe = YES;
		if (libreJar) {
			arguments = @[
						  @"-jar",
						  libreJar,
						  @"-m", self.show.tiVo.mediaKey,
						  @"-d"
						  ];
		} else {
			arguments =@[
						 @"-m", self.show.tiVo.mediaKey,
						 @"-v",
						 @"--",
						 @"-"
						 ];
		}
	} else {
		decryptTask.requiresOutputPipe = NO;
		if (libreJar) {
			arguments = @[
						  @"-jar",
						  libreJar,
						  @"-m",self.show.tiVo.mediaKey,
						  @"-d",
						  @"-o", self.decryptedFilePath
						  ];
		} else {
			arguments = @[
						  @"-m",self.show.tiVo.mediaKey,
						  @"-o",self.decryptedFilePath,
						  @"-v",
						  @"-"
						  ];
		}
    }
    [decryptTask setArguments:arguments];
    DDLogDetail(@"Decrypt Arguments: %@",[[arguments componentsJoinedByString:@" "] maskMediaKeys]);
    _decryptTask = decryptTask;
    return _decryptTask;
}

-(MTTask *)encodeTask
{
    if (_encodeTask) {
        return _encodeTask;
    }
    MTTask *encodeTask = [MTTask taskWithName:@"encode" download:self];
	
    NSString * encoderPath = [self encoderPath];
    if (!encoderPath) return nil;
    [encodeTask setLaunchPath:encoderPath];
    encodeTask.requiresOutputPipe = NO;
	__weak __typeof__(self) weakSelf = self;

    encodeTask.completionHandler = ^BOOL(){
		__typeof__(self) strongSelf = weakSelf;
        if (! [[NSFileManager defaultManager] fileExistsAtPath:strongSelf.tempEncodeFilePath] ) {
            DDLogReport(@" %@ encoding complete, but the video file not found: %@ ",strongSelf, strongSelf.tempEncodeFilePath );
            return NO;
        }
        unsigned long long fileSize = [[[NSFileManager defaultManager] attributesOfItemAtPath:strongSelf.tempEncodeFilePath error:nil] fileSize];
        if (fileSize == 0) {
            DDLogReport(@" %@ encoding complete, but empty file found: %@",strongSelf, strongSelf.tempEncodeFilePath );
            return NO;
        }
#ifdef SANDBOX
		NSError * error = nil;
		if (! [[NSFileManager defaultManager]
			   	moveItemAtPath:strongSelf.tempEncodeFilePath
						toPath:strongSelf.encodeFilePath
			   			 error: &error] ) {
			DDLogReport(@" %@ encoding complete, but could not transfer file %@ to destination directory: %@ Error: %@",strongSelf, strongSelf.tempEncodeFilePath, strongSelf.encodeFilePath, error.localizedDescription);
		}
#endif
        strongSelf.downloadStatus = @(kMTStatusEncoded);
        strongSelf.processProgress = 1.0;
		//normally when encode finished, we're all done, except when we have parallel tasks still running, or follow-on tasks to come.
		BOOL notDone = NO;
		switch (strongSelf.taskFlowType) {
			case kMTTaskFlowSimuSubtitles:
				notDone = strongSelf->_captionTask.isRunning;
				if (notDone) strongSelf.downloadStatus = @(kMTStatusCaptioning);
				break;
			case kMTTaskFlowMarkcom:
			case kMTTaskFlowMarkcomSubtitles:
				notDone = strongSelf->_commercialTask.isRunning;
				if (notDone) strongSelf.downloadStatus = @(kMTStatusCommercialing);
			break;
			case kMTTaskFlowSimuMarkcom :
			case kMTTaskFlowSimuMarkcomSubtitles :
				notDone = YES; //always run commercial after encoder
				if (notDone) strongSelf.downloadStatus = @(kMTStatusCommercialing);
				break;
			default:
				break;
		}
		if (!notDone) {
			[strongSelf finishUpPostEncodeProcessing];
		}

        return YES;
    };
	NSString * errFilePath = encodeTask.errorFilePath; //hang onto for cleanup.
    encodeTask.cleanupHandler = ^(){
		__typeof__(self) strongSelf = weakSelf;
		if (!strongSelf) return;
		if (strongSelf.isCanceled) {
			[strongSelf deleteVideoFile];
			return;
		}
		double downloadedSize = strongSelf.totalDataDownloaded;
		double filePercent =  downloadedSize/ strongSelf.show.fileSize*100;
		BOOL useTS = strongSelf.useTransportStream.boolValue;
		BOOL tooSmall = filePercent > 0 && ((useTS && filePercent < 70.0) ||
											(!useTS && filePercent < 80.0 ));
		if (useTS) {
			MPEGFormat format = [strongSelf videoFileType:self.decryptedFilePath];
			strongSelf.show.mpegFormat = format;
			if (format == MPEGFormatMPG2) {  //MPEG2
				BOOL failed = strongSelf.encodeTask.taskFailed;
				DDLogReport(@"For download %@, after downloading file with Transport Stream, we find it is an MPEG2, which %@ to a corrupted video file. Retrying with Program Stream.", strongSelf, failed ? @"apparently led" : @"might lead");

				if (tooSmall || failed || ![[NSUserDefaults standardUserDefaults] boolForKey:kMTAllowMP2InTS]) {
					//Looks like either user forced us to use TS OR channel is sending mixture of H.264 and MPEG2
					//try again with ProgramStream
					strongSelf.useTransportStream = @NO;
					[strongSelf markMyChannelAsPSOnly];
					tooSmall = NO; //don't warn below
				}
			} else if (format == MPEGFormatH264) {
				if (strongSelf.encodeTask.taskFailed) {
					DDLogMajor(@"After downloading file with Transport Stream, encoding failed, but it actually is an H264 stream %@",strongSelf);
				} else {
					DDLogDetail(@"After downloading file with Transport Stream, encoding passed with an H264 stream %@",strongSelf);
				}
			} else {
				DDLogDetail(@"After downloading file with Transport Stream, invalid video file %@",strongSelf);
			}
		} else {
			//Program Stream
			if (tooSmall) {   //hmm, doesn't look like it's big enough
				BOOL foundAudioOnly = [strongSelf checkLogForAudio: errFilePath] ||
										(!strongSelf.encodeFormat.testsForAudioOnly &&
										 filePercent > 2.0 &&
										 filePercent < 25.0);
						//encoder won't check decrypted-only file, so rely on size alone
				
				if (foundAudioOnly) {
					DDLogMajor(@"Due to Audio Only in file, switching to Transport Stream %@",strongSelf);
					[strongSelf handleNewTSChannel];
					tooSmall = NO; //don't warn below
				}
			} else {
				//got full length file, so under Program Stream, it must be MP2
				[strongSelf markMyChannelAsPSOnly];
			}

		}
		//Too small, and not handled above
		if (tooSmall) {
			DDLogReport(@"Show %@ supposed to be %0.0f Kbytes, actually %0.0f Kbytes (%0.1f%%)", strongSelf.show, strongSelf.show.fileSize/1000, downloadedSize/1000, 100.0 * downloadedSize / strongSelf.show.fileSize);
			[strongSelf notifyUserWithTitle: @"Warning: Show may be damaged/incomplete."
								   subTitle:@"Transfer is too short" ];
		}
	};

    encodeTask.terminationHandler = nil;
    NSArray * encoderArgs = nil;

    if (self.shouldSimulEncode)  {
        encoderArgs = [self encodingArgumentsWithInputFile:@"-" outputFile:self.tempEncodeFilePath];
    } else {
        if (self.encodeFormat.canSimulEncode) {  //Need to setup up the startup for sequential processing to use the writeData progress tracking
            encoderArgs = [self encodingArgumentsWithInputFile:@"-" outputFile:self.tempEncodeFilePath];
            encodeTask.requiresInputPipe = YES;
            __block NSPipe *encodePipe = [NSPipe new];
			[encodeTask setStandardInput:encodePipe]; ///XXX maybe delete;
            encodeTask.startupHandler = ^BOOL(){
				__typeof__(self) strongSelf = weakSelf;
                if ([strongSelf isCompleteCTiVoFile:self.tempEncodeFilePath forFileType:@"Encoded"]){
                    return NO;
                }

                if (strongSelf.bufferFileReadHandle) {
                    [strongSelf.bufferFileReadHandle closeFile];
                }
                strongSelf.bufferFileReadHandle = [NSFileHandle fileHandleForReadingAtPath:self.decryptedFilePath];
                strongSelf.urlBuffer = nil;
                strongSelf.taskChainInputHandle = [encodePipe fileHandleForWriting];
				strongSelf.activeTaskChain.dataSource = encodePipe;
                strongSelf.processProgress = 0.0;
                strongSelf.previousProcessProgress = 0.0;
                strongSelf.totalDataRead = 0.0;
                strongSelf.downloadStatus = @(kMTStatusEncoding);
                [strongSelf performSelectorInBackground:@selector(writeData) withObject:nil];
                return YES;
            };

        } else {
            encoderArgs = [self encodingArgumentsWithInputFile:self.decryptedFilePath outputFile:self.tempEncodeFilePath];
            encodeTask.requiresInputPipe = NO;
            NSRegularExpression *percents = [NSRegularExpression regularExpressionWithPattern:self.encodeFormat.regExProgress ?:@"" options:NSRegularExpressionCaseInsensitive error:nil];
            if (!percents) {
                DDLogReport(@"Missing Regular Expression for Format %@!!", self.encodeFormat.name);
            } else {
                encodeTask.progressCalc = ^double(NSString *data){
                    double returnValue = -1.0;
                    NSArray *values = nil;
                    if (data) {
                        values = [percents matchesInString:data options:NSMatchingWithoutAnchoringBounds range:NSMakeRange(0, data.length)];
                    }
                    if (values && values.count) {
                        NSTextCheckingResult *lastItem = [values lastObject];
                        NSRange r = [lastItem range];
                        if (r.location != NSNotFound) {
                            NSRange valueRange = [lastItem rangeAtIndex:1];
                            returnValue =  [[data substringWithRange:valueRange] doubleValue]/100.0;
                            DDLogVerbose(@"Encoder progress found data %lf",returnValue);
                        }
                    }
                    if (returnValue == -1.0) {
                        DDLogMajor(@"Encode progress with RX %@ failed for task encoder for show %@\nEncoder report: %@",percents, weakSelf, data);
                    }
                    return returnValue;
                };
            };
            encodeTask.startupHandler = ^BOOL(){
                weakSelf.processProgress = 0.0;
                if (!weakSelf.isDownloading) weakSelf.downloadStatus = @(kMTStatusEncoding);
                return YES;
            };
        }
    }

    [encodeTask setArguments:encoderArgs];
    DDLogDetail(@"encoderArgs: %@",encoderArgs);
    _encodeTask = encodeTask;
    return _encodeTask;
}

-(void) fixupSRTsDueToCommercialSkipping {
//  do this if we ever reuse captions
//	if ([self isCompleteCTiVoFile:self.captionFilePath forFileType:@"srt"]) return;
    NSArray *srtEntries = [NSArray getFromSRTFile:self.captionFilePath];
    NSArray *edlEntries = self.show.edlList;
    if (srtEntries.count && edlEntries.count) {
        NSArray *correctedSrts = [srtEntries processWithEDLs:edlEntries];
        if ([[NSUserDefaults standardUserDefaults] boolForKey:kMTSaveTmpFiles]) {
            NSString *oldCaptionPath = [[self.captionFilePath stringByDeletingPathExtension] stringByAppendingString:@"-deleted.srt"];
            [[NSFileManager defaultManager] moveItemAtPath:self.captionFilePath toPath:oldCaptionPath error:nil];
        }
        if (correctedSrts.count) {
            [correctedSrts writeToSRTFilePath:self.captionFilePath];
            [self markCompleteCTiVoFile:self.captionFilePath];
        }
    }
}

-(MTTask *)captionTask { //Captioning is done in parallel with download so no progress indicators are needed.
	NSAssert(self.exportSubtitles.boolValue,@"captionTask not requested");
    if (_captionTask) {
        return _captionTask;
    }
	if (!self.tempCaptionFilePath) {

#ifdef SANDBOX
		NSString * directory =self.tmpDirectory;
#else
		NSString * directory =self.downloadDirectory;
#endif
		self.tempCaptionFilePath = [NSString stringWithFormat:@"%@/%@.srt",directory,
 									self.baseFileName];
	}
    MTTask *captionTask = [MTTask taskWithName:@"caption" download:self completionHandler:nil];
    [captionTask setLaunchPath:[[NSBundle mainBundle] pathForAuxiliaryExecutable:@"ccextractor" ]];
    captionTask.requiresOutputPipe = NO;
    captionTask.shouldReschedule  = NO;  //If captioning fails continue, just without captioning
	__weak __typeof__(self) weakSelf = self;

    if (self.downloadingShowFromMPGFile) {
		NSUInteger showLength = self.show.showLength ?: 120*60;
        captionTask.progressCalc = ^double(NSString *data){
            NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"\\d+:\\d\\d" options:NSRegularExpressionCaseInsensitive error:nil];
            NSArray *values = nil;
			double returnValue = -1.0;
            if (data) {
                values = [regex matchesInString:data options:NSMatchingWithoutAnchoringBounds range:NSMakeRange(0, data.length)];
            }
            if (values && values.count) {
                NSTextCheckingResult *lastItem = [values lastObject];
				NSRange r = [lastItem range];
				if (r.location != NSNotFound) {
					NSRange valueRange = [lastItem rangeAtIndex:0];
					NSString *timeString = [data substringWithRange:valueRange];
					NSArray *components = [timeString componentsSeparatedByString:@":"];
					double currentTimeOffset = [components[0] doubleValue] * 60.0 + [components[1] doubleValue];
					returnValue = (currentTimeOffset/showLength);
				}
				
            }
			if (returnValue == -1.0){
                DDLogMajor(@"Track progress with Rx failed for task caption for show %@: %@",self, data);
            }
			return returnValue;
        };
        if (!self.encodeFormat.canSimulEncode) {
            captionTask.startupHandler = ^BOOL(){
                weakSelf.processProgress = 0.0;
                weakSelf.downloadStatus = @(kMTStatusCaptioning);
                return YES;
            };
        }
    }

	__weak __typeof__(MTTask *) weakCaption = captionTask;

    captionTask.completionHandler = ^BOOL(){
//        [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationCaptionDidFinish object:nil];
		__typeof__(self) strongSelf = weakSelf;
        //commercial or caption might finish first.
#ifdef SANDBOX
		NSError * error = nil;
		if (! [[NSFileManager defaultManager] moveItemAtPath:strongSelf.tempCaptionFilePath
													  toPath:strongSelf.captionFilePath
													   error: &error] ) {
			DDLogReport(@" %@ caption complete, but could not transfer file %@ to destination directory: %@ Error: %@",strongSelf, strongSelf.tempCaptionFilePath, strongSelf.captionFilePath, error.localizedDescription);
			return NO;
		}
#endif
        if ( strongSelf.skipCommercials && strongSelf.show.edlList.count ) {
            [strongSelf fixupSRTsDueToCommercialSkipping];
        }
		return YES;
    };
    
    captionTask.cleanupHandler = ^(){
		__typeof__(self) strongSelf = weakSelf;
		if (strongSelf.isCanceled) {
			if (![[NSUserDefaults standardUserDefaults] boolForKey:kMTSaveTmpFiles]) {
				if ([[NSFileManager defaultManager] fileExistsAtPath:strongSelf.tempCaptionFilePath]) {
					[[NSFileManager defaultManager] removeItemAtPath:strongSelf.tempCaptionFilePath error:nil];
				}
				strongSelf.tempCaptionFilePath = nil;
				strongSelf.captionFilePath = nil;
			}
		} else if (weakCaption.taskFailed) {
            [strongSelf notifyUserWithTitle:@"Detecting Captions Failed" subTitle:@"Not including captions" ];
        }
		if (strongSelf.taskFlowType == kMTTaskFlowSimuSubtitles &&
			strongSelf->_encodeTask.successfulExit) {
				[strongSelf finishUpPostEncodeProcessing];
		} else if (strongSelf.downloadStatus.intValue == kMTStatusCaptioning) {
			if ((strongSelf.taskFlowType == kMTTaskFlowSkipcomSubtitles) ||
			    (strongSelf.taskFlowType == kMTTaskFlowSimuSkipcomSubtitles)) {
				//strongSelf.downloadStatus = @(kMTStatusCommercialing); commercial startup sets this
			} else if (strongSelf.taskFlowType == kMTTaskFlowMarkcomSubtitles) {
				//strongSelf.downloadStatus = @(kMTStatusEncoding); //encode startup sets this
			}

		}
    };
    
    NSMutableArray * captionArgs = [NSMutableArray array];
    
    [self addArguments:self.encodeFormat.captionOptions toArray:captionArgs];
    
    // [captionArgs addObject:@"-bi"]; messes with most recent version of ccextractor
    [captionArgs addObject:@"-utf8"];
    [captionArgs addObject:@"-s"];
    //[captionArgs addObject:@"-debug"];
    [captionArgs addObject:@"-"];
    [captionArgs addObject:@"-o"];
    [captionArgs addObject:self.tempCaptionFilePath];
    DDLogVerbose(@"ccExtractorArgs: %@",captionArgs);
    [captionTask setArguments:captionArgs];
    DDLogVerbose(@"Caption Task = %@",captionTask);
    _captionTask = captionTask;
    return captionTask;
}

#ifdef DEBUG
- (void)writeAndAppendString:(NSString *)str toFile:(NSString *)fileName {
	
	NSData *data = [str dataUsingEncoding:NSUTF8StringEncoding];
	
	NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
	if (0 < [paths count]) {
		NSString *documentsDirPath = [paths objectAtIndex:0];
		NSString *filePath = [documentsDirPath stringByAppendingPathComponent:fileName];
		
		NSFileManager *fileManager = [NSFileManager defaultManager];
		if ([fileManager fileExistsAtPath:filePath]) {
			// Add the text at the end of the file.
			NSFileHandle *fileHandler = [NSFileHandle fileHandleForUpdatingAtPath:filePath];
			[fileHandler seekToEndOfFile];
			[fileHandler writeData:data];
			[fileHandler closeFile];
		} else {
			// Create the file and write text to it.
			[data writeToFile:filePath atomically:YES];
		}
	}
}
#endif

-(MTTask *)commercialTask
{
	BOOL postCommercialing = self.downloadStatus.intValue == kMTStatusAwaitingPostCommercial; //this is a stand-alone commercialing due to not eventually getting a SkipMode list
    NSAssert(self.runComskipNow || (postCommercialing) ,@"Commercial Task not requested?");

    if (_commercialTask) {
        return _commercialTask;
    }
    MTTask *commercialTask = [MTTask taskWithName:@"commercial" download:self completionHandler:nil];
  	[commercialTask setLaunchPath:[[NSBundle mainBundle] pathForAuxiliaryExecutable:@"comskip" ]];
    commercialTask.successfulExitCodes = @[@0, @1];
    commercialTask.requiresOutputPipe = NO;
    commercialTask.requiresInputPipe = NO;
    commercialTask.shouldReschedule  = NO;  //If comskip fails continue just without commercial inputs
    [commercialTask setStandardError:commercialTask.logFileWriteHandle];  //progress data is in err output
    
	__weak __typeof__(self) weakSelf = self;
	__weak __typeof__(MTTask *) weakCommercial = commercialTask;

    commercialTask.cleanupHandler = ^(){
		__typeof__(self) strongSelf = weakSelf;
		__typeof__(MTTask *) strongCommercial = weakCommercial;
		if (!strongSelf || !strongCommercial) return;
        if (strongCommercial.taskFailed) {
            if ([strongSelf checkLogForAudio: strongCommercial.logFilePath]) {
				DDLogMajor(@"Due to audio-only failure, switching to Transport Stream for %@", strongSelf);
                [strongSelf handleNewTSChannel];
            } else if (!strongSelf.isCanceled && strongSelf.isInProgress){
                [strongSelf notifyUserWithTitle:@"Detecting Commercials Failed" subTitle:@"Not processing commercials" ];

                if ([[NSFileManager defaultManager] fileExistsAtPath:strongSelf.commercialFilePath]) {
                    [[NSFileManager defaultManager] removeItemAtPath:strongSelf.commercialFilePath error:nil];
                }
                NSData *zeroData = [NSData data];
                [zeroData writeToFile:strongSelf.commercialFilePath atomically:YES];
                if (strongCommercial.completionHandler) strongCommercial.completionHandler();
            }
        }
    };
	
	BOOL parallelToEncode = self.taskFlowType == kMTTaskFlowMarkcom || self.taskFlowType == kMTTaskFlowMarkcomSubtitles;
	//if parallel to encoding, commercialing doesn't do progress or download status updates
    if (postCommercialing || !parallelToEncode ) {
        commercialTask.startupHandler = ^BOOL(){
            weakSelf.processProgress = 0.0;
			weakSelf.downloadStatus = postCommercialing ?  @kMTStatusPostCommercialing :  @kMTStatusCommercialing;
            return YES;
        };

		NSRegularExpression *percents = [NSRegularExpression regularExpressionWithPattern:@"(\\d+)(?:.\\d*)?\\%" options:NSRegularExpressionCaseInsensitive error:nil];
        commercialTask.progressCalc = ^double(NSString *data){
            if (!data) return 0.0;
            NSArray *values = [percents matchesInString:data options:NSMatchingWithoutAnchoringBounds range:NSMakeRange(0, data.length)];
            NSTextCheckingResult *lastItem = [values lastObject];
            NSRange valueRange = [lastItem rangeAtIndex:1];
            return [[data substringWithRange:valueRange] doubleValue]/100.0;
        };
	}
	__weak __typeof__(MTTask *) weakCaption = _captionTask;

	commercialTask.completionHandler = ^BOOL{
		__typeof__(self) strongSelf = weakSelf;
		if (!strongSelf.isCanceled && ! [[NSFileManager defaultManager] fileExistsAtPath:strongSelf.commercialFilePath] ) {
			DDLogMajor(@"Warning: %@: File %@ not found after comskip completion", strongSelf, strongSelf.commercialFilePath );
			return NO;
		}

		DDLogMajor(@"Finished detecting commercials in %@",strongSelf);
		strongSelf.show.edlList = [NSArray getFromEDLFile:strongSelf.commercialFilePath];
#ifdef DEBUG
		if (strongSelf.show.edlList != strongSelf.show.rpcData.edlList &&
			strongSelf.show.edlList.count && strongSelf.show.rpcData.edlList.count) {
			NSString * compareEDLs = [strongSelf.show.rpcData.edlList compareEDL: strongSelf.show.edlList];
			NSString * output = [NSString stringWithFormat:@"%@\n%@",strongSelf.show.showTitle,compareEDLs];
			[strongSelf writeAndAppendString:output toFile:@"CompareEDLs"];
		}
#endif
		if (postCommercialing) {
			[NSNotificationCenter postNotificationNameOnMainThread:kMTNotificationShowDownloadDidFinish object:strongSelf];  // Free up an encoder / update UI
			[strongSelf finalFinalProcessing];
		} else {
			strongSelf.downloadStatus = @(kMTStatusCommercialed);
			if (strongSelf.skipCommercials) {
			 	//commercialing pre-encoding
				strongSelf.processProgress = 1.0;
				if (strongSelf.exportSubtitles.boolValue &&  strongSelf.tempCaptionFilePath && weakCaption.successfulExit) {
					[strongSelf fixupSRTsDueToCommercialSkipping];
				}
			} else if (strongSelf->_encodeTask.successfulExit) {
				//either parallel and finished, or post-encoding
				strongSelf.processProgress = 1.0;
				[strongSelf finishUpPostEncodeProcessing];
			} else {
				//parallel and not finished
				strongSelf.downloadStatus = @(kMTStatusEncoding);
			}
		 }
		return YES;
	};
	if (postCommercialing) {
		commercialTask.terminationHandler = ^{
		[NSNotificationCenter postNotificationNameOnMainThread:kMTNotificationShowDownloadWasCanceled object:weakSelf];  // Free up an encoder / update UI
    	};
	}

	NSMutableArray *arguments = [NSMutableArray array];
    [self addArguments:self.encodeFormat.comSkipOptions toArray:arguments];
    NSRange iniRange = [self.encodeFormat.comSkipOptions rangeOfString:@"--ini="];
//	[arguments addObject:[NSString stringWithFormat: @"--output=%@",[self.commercialFilePath stringByDeletingLastPathComponent]]];  //0.92 version
    if (iniRange.location == NSNotFound) {
        [arguments addObject:[NSString stringWithFormat: @"--ini=%@",[[NSBundle mainBundle] pathForResource:@"comskip" ofType:@"ini"]]];
    }
    
    if ((self.taskFlowType == kMTTaskFlowSimuMarkcom || self.taskFlowType == kMTTaskFlowSimuMarkcomSubtitles) && [self canPostDetectCommercials]) {
        [arguments addObject:self.tempEncodeFilePath]; //Run on the final file for these conditions: moved already?
        self.commercialFilePath = [NSString stringWithFormat:@"%@/%@.edl" ,self.tmpDirectory, self.baseFileName];  //0.92 version  (probably wrong, but not currently used)
    } else {
        [arguments addObject:self.decryptedFilePath];// Run this on the output of tivodecode
    }
	DDLogVerbose(@"comskip Path: %@",[[NSBundle mainBundle] pathForAuxiliaryExecutable:@"comskip" ]);
	DDLogVerbose(@"comskip args: %@",arguments);
	[commercialTask setArguments:arguments];
    _commercialTask = commercialTask;
    return _commercialTask;
  
}

-(MTTaskFlowType)calculateTaskFlowType
{
	BOOL runComskip = self.runComskipNow;
	return (MTTaskFlowType)
          1 * (int) self.exportSubtitles.boolValue +
          2 * (int) self.encodeFormat.canSimulEncode +
          4 * (int) (self.skipCommercials && runComskip) +
          8 * (int) (self.markCommercials && runComskip);
}

-(void)launchDownload
{
    NSUserDefaults * defaults = [NSUserDefaults standardUserDefaults];

	if (self.encodeFormat.isEncryptedDownload || self.encodeFormat.isTestPS) {
		self.skipCommercials = NO;
		self.markCommercials = NO;
		self.exportSubtitles = @NO;
		self.useSkipMode = NO;
	}
    BOOL channelCommercialsOff = [tiVoManager commercialsForChannel:self.show.stationCallsign] == NSOffState;
    if ((channelCommercialsOff) &&
        (self.skipCommercials || self.markCommercials)) {
        //this channel doesn't use commercials
        DDLogMajor(@"Channel %@ doesn't use commercials; overriding  for %@",self.show.stationCallsign, self);
        self.skipCommercials = NO;
        self.markCommercials = NO;
    }
	[self skipModeCheck];
	self.taskFlowType = [self calculateTaskFlowType];
	DDLogReport(@"Starting download (type %d) for %@; Format: %@; %@%@%@%@%@%@%@%@%@%@%@; %@",
				(int)self.taskFlowType,
				self,
				self.encodeFormat.name ,
				self.encodeFormat.canSimulEncode ?
                    @"simul encode" :
                    @"",
				self.skipCommercials ?
					@" Skip commercials" :
                    @"",
                self.markCommercials ?
					 @" Mark commercials" :
					 @"",
				self.runComskipNow ? @" with Comskip;" : @";",
				self.addToiTunesWhenEncoded ?
					@" Add to iTunes;" :
					@"",
				self.genTextMetaData.boolValue ?
					@" Generate Metadata;" :
					@"",
				self.exportSubtitles.boolValue ?
					@" Generate Subtitles;" :
					@"",
				[defaults boolForKey:kMTiTunesDelete] ?
					@"" :
					@" Keep after iTunes;",
				[defaults boolForKey:kMTSaveTmpFiles] ?
					@" Save Temp files;" :
					@"",
				[self shouldUseMemoryBuffer]?
					@"" :
					@" No Memory Buffer;",
               [defaults objectForKey:kMTDecodeBinary],
               self.useTransportStream.boolValue ? @"Transport Stream" : @"Program Stream"
				);
	self.isCanceled = NO;
	self.isRescheduled = NO;
    self.progressAt100Percent = nil;  //Reset end of progress failure delay
	//Before starting make sure we can launch.
	if (![self encoderPath]) {
		self.downloadStatus = @(kMTStatusFailed);
		self.processProgress = 1.0;
		[NSNotificationCenter postNotificationNameOnMainThread:kMTNotificationShowDownloadWasCanceled object:nil];  //Decrement num encoders right away
		return;
	}
	if ( ! [self configureFiles]) {
        DDLogReport(@"Cancelling launch");
		[self rescheduleDownloadFalseStart];
		return;
	}

	self.decryptTask = nil;
	self.encodeTask = nil;
	self.commercialTask = nil;
	self.captionTask = nil; //make sure we're not reusing an old task from previous run.
    self.activeTaskChain = [MTTaskChain new];
    self.activeTaskChain.download = self;
    if (!self.downloadingShowFromMPGFile && !self.downloadingShowFromTiVoFile) {
        NSPipe *taskInputPipe = [NSPipe pipe];
        self.activeTaskChain.dataSource = taskInputPipe;
        self.taskChainInputHandle = [taskInputPipe fileHandleForWriting];
    } else if (self.downloadingShowFromTiVoFile) {
        self.activeTaskChain.dataSource = self.tivoFilePath;
        DDLogMajor(@"Downloading from file tivo file %@",self.tivoFilePath);
//    } else if (self.downloadingShowFromMPGFile) {
//        DDLogMajor(@"Downloading from file MPG file %@",self.mpgFilePath);
//        self.activeTaskChain.dataSource = self.mpgFilePath;
    }
	if (self.hasEDL && self.shouldSkipCommercials  ){
		if (![self.show.edlList writeToEDLFile:self.commercialFilePath] ) {
			DDLogReport(@"Could not write EDLFile to disk at %@", self.commercialFilePath);
		}
	}
	
    NSMutableArray *taskArray = [NSMutableArray array];
	
	if (!self.downloadingShowFromMPGFile) {
        MTTask * decryptTask = self.decryptTask;
        if (decryptTask) {
            [taskArray addObject:@[decryptTask]];
        } else {
            [NSNotificationCenter postNotificationNameOnMainThread:kMTNotificationShowDownloadWasCanceled object:nil];  //Decrement num encoders right away
            self.downloadStatus = @(kMTStatusFailed);
            return;
        }
    }
    MTTask * encodeTask = self.encodeTask;
    if (!encodeTask) {
        [NSNotificationCenter postNotificationNameOnMainThread:kMTNotificationShowDownloadWasCanceled object:nil];  //Decrement num encoders right away
        self.downloadStatus = @(kMTStatusFailed);
        return;
    }
	MTTask * mpegTask = nil;
	if (self.shouldCheckMPEG ) {
		mpegTask = self.mpegTask;
		if (self.encodeFormat.isTestPS) {
			[taskArray addObject:@[mpegTask]];
		}
	}
	if (!self.encodeFormat.isTestPS)  //Warning: no brace and not indented due to size of block
    switch (self.taskFlowType) {
        case kMTTaskFlowNonSimu:  //Just encode with non-simul encoder
			if (mpegTask) {
				[taskArray addObject:@[[self catTask:self.decryptedFilePath],mpegTask]];
			}
			[taskArray addObject:@[encodeTask]];
			break;
			
		case kMTTaskFlowSimu: { //Just encode with simul encoder
			NSArray <MTTask *> * taskGroup = @[encodeTask];
			if (self.mayComskipInFuture && ! self.downloadingShowFromMPGFile) {
				taskGroup = [taskGroup arrayByAddingObject:[self catTask:self.decryptedFilePath]];
			}
			if (mpegTask) {
				taskGroup = [taskGroup arrayByAddingObject:mpegTask];
			}
			[taskArray addObject: taskGroup];
			break;
		}
		case kMTTaskFlowSubtitles: { //Encode with non-simul encoder and subtitles
			NSArray <MTTask *> * taskGroup = @[self.captionTask];
			if (!self.downloadingShowFromMPGFile) {
				taskGroup = [taskGroup arrayByAddingObject:[self catTask:self.decryptedFilePath]];
            }
			if (mpegTask) {
				taskGroup = [taskGroup arrayByAddingObject:mpegTask];
			}
			[taskArray addObject: taskGroup];
			[taskArray addObject:@[encodeTask]];
            break;
		}
		case kMTTaskFlowSimuSubtitles: { //Encode with simul encoder and subtitles
			NSArray <MTTask *> * taskGroup = @[encodeTask, self.captionTask];
			if ((self.mayComskipInFuture && ! self.downloadingShowFromMPGFile) || mpegTask) {
				taskGroup = [taskGroup arrayByAddingObject:[self catTask:self.decryptedFilePath]];
			}
			if (mpegTask) {
				taskGroup = [taskGroup arrayByAddingObject:mpegTask];
			}
			[taskArray addObject: taskGroup];
            break;
		}
        //the rest can't have mayComSkipInFuture
        case kMTTaskFlowSkipcom:  //Encode with non-simul encoder skipping commercials
		case kMTTaskFlowSimuSkipcom:  {//Encode with simul encoder skipping commercials
			if (mpegTask) {
				[taskArray addObject:@[[self catTask:self.decryptedFilePath],mpegTask]];
			}
			[taskArray addObject: @[self.commercialTask]];
			[taskArray addObject:@[encodeTask]];
            break;
		}
        case kMTTaskFlowSkipcomSubtitles:  //Encode with non-simul encoder skipping commercials and subtitles
		case kMTTaskFlowSimuSkipcomSubtitles: { //Encode with simul encoder skipping commercials and subtitles
			NSArray <MTTask *> * taskGroup = @[self.captionTask,[self catTask:self.decryptedFilePath]];
			if (mpegTask) {
				taskGroup = [taskGroup arrayByAddingObject:mpegTask];
			}
			[taskArray addObject: taskGroup];
			[taskArray addObject:@[self.commercialTask]];
			[taskArray addObject:@[encodeTask]];
            break;
		}
        case kMTTaskFlowMarkcom:  //Encode with non-simul encoder marking commercials
			if (mpegTask) {
				[taskArray addObject:@[mpegTask,[self catTask:self.decryptedFilePath]]];
			}
			[taskArray addObject:@[encodeTask, self.commercialTask]];
            break;
            
		case kMTTaskFlowMarkcomSubtitles: { //Encode with non-simul encoder marking commercials and subtitles
			NSArray <MTTask *> * taskGroup = @[self.captionTask];
			if (!self.downloadingShowFromMPGFile || mpegTask) {
				taskGroup = [taskGroup arrayByAddingObject:[self catTask:self.decryptedFilePath]];
				if (mpegTask) {
					taskGroup = [taskGroup arrayByAddingObject:mpegTask];
				}
			}
			[taskArray addObject: taskGroup];
			
            [taskArray addObject:@[encodeTask, self.commercialTask]];
            break;
		}
		case kMTTaskFlowSimuMarkcom: { //Encode with simul encoder marking commercials
			NSArray <MTTask *> * taskGroup = @[encodeTask];
			if ((![self canPostDetectCommercials] && ! self.downloadingShowFromMPGFile) || mpegTask) {
				taskGroup = [taskGroup arrayByAddingObject:[self catTask:self.decryptedFilePath]];
				if (mpegTask) {
					taskGroup = [taskGroup arrayByAddingObject:mpegTask];
				}
			}
			[taskArray addObject: taskGroup];
			[taskArray addObject:@[self.commercialTask]];
           break;
		}
		case kMTTaskFlowSimuMarkcomSubtitles: { //Encode with simul encoder marking commercials and subtitles
			NSArray <MTTask *> * taskGroup = @[encodeTask, self.captionTask];
			if ((![self canPostDetectCommercials] && ! self.downloadingShowFromMPGFile) || mpegTask) {
				taskGroup = [taskGroup arrayByAddingObject:[self catTask:self.decryptedFilePath]];
				if (mpegTask) {
					taskGroup = [taskGroup arrayByAddingObject:mpegTask];
				}
			}
			[taskArray addObject: taskGroup];
			[taskArray addObject:@[self.commercialTask]];
           break;
		}
        default:
            break;
    }
	self.activeTaskChain.taskArray = [NSArray arrayWithArray:taskArray];
    if(self.downloadingShowFromMPGFile)self.activeTaskChain.providesProgress = YES;
    
    self.totalDataRead = 0;
    self.totalDataDownloaded = 0;
    NSURL * downloadURL = nil;
    if (!self.downloadingShowFromTiVoFile && !self.downloadingShowFromMPGFile) {
        downloadURL = self.show.downloadURL;
        if (self.useTransportStream.boolValue) {
            NSString * downloadString = [downloadURL absoluteString];
            if (![downloadString hasSuffix:@"&Format=video/x-tivo-mpeg-ts"]) {
                if ([downloadString hasSuffix:@"&Format=video/x-tivo-mpeg"]) {
                    downloadString = [downloadString stringByAppendingString: @"-ts"];
                } else {
                    downloadString = [downloadString stringByAppendingString: @"&Format=video/x-tivo-mpeg-ts"]; //normal case
                }
            }
            downloadURL = [NSURL URLWithString:downloadString];
        }

        NSURLRequest *thisRequest = [NSURLRequest requestWithURL:downloadURL];
        self.activeURLConnection = [[NSURLConnection alloc] initWithRequest:thisRequest delegate:self startImmediately:NO] ;
    }
    self.processProgress = 0.0;
    self.previousProcessProgress = 0.0;

    if (![self.activeTaskChain run]) {
        [self rescheduleDownload];
        return;
    };
    double downloadDelay = kMTTiVoAccessDelayServerFailure - [[NSDate date] timeIntervalSinceDate:self.show.tiVo.lastDownloadEnded];
    if (downloadDelay <= 0) {
        downloadDelay = 0;
		self.downloadStatus = @(kMTStatusDownloading);
	} else {
		self.downloadStatus = @(kMTStatusWaiting);
		self.downloadDelayStart = [NSDate date];
		self.downloadDelay = downloadDelay;
		[self performSelector:@selector(updateDownloadDelay) withObject:nil afterDelay:0.2];
	}

	if (!self.downloadingShowFromTiVoFile && !self.downloadingShowFromMPGFile) {
        DDLogReport(@"Starting URL %@ for show %@ in %0.1lf seconds", downloadURL,self, downloadDelay);
		[tiVoManager preventSleep];
		[self.activeURLConnection scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSRunLoopCommonModes];
		[self.activeURLConnection performSelector:@selector(start) withObject:nil afterDelay:downloadDelay];
	}
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(checkStillActive) object:nil];
    [self performSelector:@selector(checkStillActive) withObject:nil afterDelay:[[NSUserDefaults standardUserDefaults] integerForKey: kMTMaxProgressDelay] + downloadDelay];
}

#pragma mark -
#pragma mark Post processing methods

-(void) writeTextMetaData:(NSString*) value forKey: (NSString *) key toFile: (NSFileHandle *) handle {
	if ( key.length > 0 && value.length > 0) {
		
		[handle writeData:[[NSString stringWithFormat:@"%@ : %@\n",key, value] dataUsingEncoding:NSUTF8StringEncoding]];
	}
}

-(void) writeMetaDataFiles {
	
//	if (self.genXMLMetaData.boolValue) {
//		NSString * tivoMetaPath = [[self.encodeFilePath stringByDeletingPathExtension] stringByAppendingPathExtension:@"xml"];
//		DDLogMajor(@"Writing XML to    %@",tivoMetaPath);
//		if (![[NSFileManager defaultManager] copyItemAtPath: detailFilePath toPath:tivoMetaPath error:nil]) {
//				DDLogReport(@"Couldn't write XML to file %@", tivoMetaPath);
//		}
//	}
    NSURL * detailFileURL = self.show.detailFileURL;
	if (self.genTextMetaData.boolValue && [detailFileURL fileExists]) {
		NSData * xml = [NSData dataWithContentsOfURL:detailFileURL];
		NSXMLDocument *xmldoc = [[NSXMLDocument alloc] initWithData:xml options:0 error:nil];
		NSString * xltTemplate = [[NSBundle mainBundle] pathForResource:@"pytivo_txt" ofType:@"xslt"];
		id returnxml = [xmldoc objectByApplyingXSLTAtURL:[NSURL fileURLWithPath:xltTemplate] arguments:nil error:nil	];
		if (!returnxml || ![returnxml isKindOfClass:[NSData class]] ) {
 			DDLogReport(@"Couldn't convert XML to text using %@ got %@; XML: \n %@ \n ", xltTemplate, returnxml, xml);
        } else {
           NSString *returnString = [[NSString alloc] initWithData:returnxml encoding:NSUTF8StringEncoding];
            NSString * textMetaPath = [self.encodeFilePath stringByAppendingPathExtension:@"txt"];
            if (![returnString writeToFile:textMetaPath atomically:NO encoding:NSUTF8StringEncoding error:nil]) {
                DDLogReport(@"Couldn't write pyTiVo Data to file %@", textMetaPath);
            } else {
                NSFileHandle *textMetaHandle = [NSFileHandle fileHandleForWritingAtPath:textMetaPath];
                [textMetaHandle seekToEndOfFile];
                [self writeTextMetaData:self.show.seriesId		  forKey:@"seriesId"			toFile:textMetaHandle];
                [self writeTextMetaData:self.show.channelString   forKey:@"displayMajorNumber"	toFile:textMetaHandle];
                [self writeTextMetaData:self.show.stationCallsign forKey:@"callsign"		    toFile:textMetaHandle];
                [self writeTextMetaData:self.show.programId       forKey:@"programId"       toFile:textMetaHandle];
                [textMetaHandle closeFile];
            }
        }
	}
}


-(NSString *) moveFile:(NSString *) path toITunes: (NSString *)iTunesBaseName forType:(NSString *) typeString andExtension: (NSString *) extension {
    if (!path) return nil;
    if (!iTunesBaseName) return nil;
    if (![[NSFileManager defaultManager] fileExistsAtPath:path])  return nil;
    NSString *newPath = [iTunesBaseName stringByAppendingPathExtension:extension ];
    if ([[NSFileManager defaultManager] moveItemAtPath:path toPath: newPath error:nil]) {
        DDLogDetail (@"Moved %@ (%@) file to iTunes: %@", typeString, extension, newPath);
        return newPath;
    } else {
        DDLogReport(@"Couldn't move %@ (%@) file from path %@ to iTunes %@",typeString, extension, path, newPath);
        return nil;
    }
}

-(void) deleteVideoFile {
    if ([[NSFileManager defaultManager] fileExistsAtPath:self.encodeFilePath]) {
        if (![[NSUserDefaults standardUserDefaults ] boolForKey:kMTSaveTmpFiles]) {
            if ([[NSFileManager defaultManager] removeItemAtPath:self.encodeFilePath error:nil]) {
                DDLogDetail (@"Deleting old video file %@", self.encodeFilePath);
            } else {
                DDLogReport(@"Couldn't remove file at path %@",self.encodeFilePath);
            }
        }
    }
}
#pragma mark - AppleScript calls for user download complete
- (NSAppleEventDescriptor *)downloadEventDescriptor {
	// parameters
	//success, title, filename, episode, startTime, tivo?
	//(where success = 1 if file is successful, 0, if a failed try, or -1 if final failure
	NSString * success = @"0";
	if (self.downloadStatus.intValue == kMTStatusFailed){
		success = @"-1";
	} else if (self.downloadStatus.intValue == kMTStatusDone ){
		success = @"1";
	}

	NSAppleEventDescriptor *parameters = [NSAppleEventDescriptor listDescriptor];
	// you have to love a language with indices that start at 1 instead of 0
	[parameters insertDescriptor:[NSAppleEventDescriptor descriptorWithString:success] 						atIndex:1];
	[parameters insertDescriptor:[NSAppleEventDescriptor descriptorWithString:self.show.showTitle] 			atIndex:2];
	[parameters insertDescriptor:[NSAppleEventDescriptor descriptorWithString:self.encodeFilePath] 			atIndex:3];
	[parameters insertDescriptor:[NSAppleEventDescriptor descriptorWithString:self.show.episodeNumber]  	atIndex:4];
	[parameters insertDescriptor:[NSAppleEventDescriptor descriptorWithString:self.show.startTime] 			atIndex:5];
	[parameters insertDescriptor:[NSAppleEventDescriptor descriptorWithString:self.show.tiVoName] 			atIndex:6];
	[parameters insertDescriptor:[NSAppleEventDescriptor descriptorWithString:self.show.thumbnailFile.path] atIndex:7];

	// target
	ProcessSerialNumber psn = {0, kCurrentProcess};
	NSAppleEventDescriptor *target = [NSAppleEventDescriptor descriptorWithDescriptorType:typeProcessSerialNumber bytes:&psn length:sizeof(ProcessSerialNumber)];
	
	// function
	NSAppleEventDescriptor *function = [NSAppleEventDescriptor descriptorWithString:@"downloadDone"];
	
	// event
	NSAppleEventDescriptor *event = [NSAppleEventDescriptor appleEventWithEventClass:kASAppleScriptSuite eventID:kASSubroutineEvent targetDescriptor:target returnID:kAutoGenerateReturnID transactionID:kAnyTransactionID];
	[event setParamDescriptor:function forKeyword:keyASSubroutineName];
	[event setParamDescriptor:parameters forKeyword:keyDirectObject];
	
	return event;
}

-(NSUserAppleScriptTask *) downloadAppleScriptTask {
	NSUserAppleScriptTask *result = nil;
	
	NSError *error;
	NSURL *directoryURL = [[NSFileManager defaultManager] URLForDirectory:NSApplicationScriptsDirectory inDomain:NSUserDomainMask appropriateForURL:nil create:YES error:&error]; //may only be in sandboxed version
	if (!directoryURL) directoryURL = [NSURL fileURLWithPath:@"~/Library/Application Scripts/com.cTiVo.cTiVo"];
	if (directoryURL) {
			NSURL *scriptURL = [directoryURL URLByAppendingPathComponent:@"DownloadDone.scpt"];
			result = [[NSUserAppleScriptTask alloc] initWithURL:scriptURL error:&error];
			if (result) {
				DDLogDetail(@"Found downloadDone AppleScript task");
			}
		} else {
			DDLogDetail(@"No Application Scripts folder; error = %@", error);
		}
		
		return result;
	}

- (NSString *)stringForResultEventDescriptor:(NSAppleEventDescriptor *)resultEventDescriptor {
	NSString *result = nil;
	if (resultEventDescriptor) {
		if ([resultEventDescriptor descriptorType] != kAENullEvent) {
			if ([resultEventDescriptor descriptorType] == kTXNUnicodeTextData) {
				result = [resultEventDescriptor stringValue];
			}
		}
	}
	return result;
}

-(void) launchUserScript {
	NSUserAppleScriptTask *downloadAppleScriptTask = [self downloadAppleScriptTask];
	if (downloadAppleScriptTask) {
		NSAppleEventDescriptor *event = [self downloadEventDescriptor];
		__weak __typeof__(self) weakSelf = self;
		[downloadAppleScriptTask executeWithAppleEvent:event completionHandler:^(NSAppleEventDescriptor *resultEventDescriptor, NSError *error) {
			if (! resultEventDescriptor) {
				DDLogReport(@"Failure on AppleScript task; error = %@", error);
			} else {
				NSString * result = [weakSelf stringForResultEventDescriptor:resultEventDescriptor];
				if (result.length > 0) {
					DDLogReport(@"For %@, User task returned: \n%@", weakSelf, result);
				}
			}
		}];
	}
}
#pragma mark - Post Processing
-(void) finalFinalProcessing {
	//allows for delayed Marking of commercials
	self.processProgress = 1.0;
	[self writeMetaDataFiles];
    if (self.exportSubtitles ) {
	//dispose of 3-character (BOM) subtitle files
        unsigned long long fileSize =  [[NSFileManager defaultManager] attributesOfItemAtPath:self.captionFilePath error:nil].fileSize;
        if ( fileSize <= 3) {
            DDLogMajor(@"Empty caption file for %@", self);
            if ( ![[NSUserDefaults standardUserDefaults] boolForKey:kMTSaveTmpFiles] ) {
                [[NSFileManager defaultManager] removeItemAtPath:self.captionFilePath error:nil];
            }
            self.captionFilePath = nil;
        }
    }
	if (self.shouldMarkCommercials || self.encodeFormat.canAcceptMetaData || self.shouldEmbedSubtitles) {
		MP4FileHandle *encodedFile = MP4Modify([self.encodeFilePath cStringUsingEncoding:NSUTF8StringEncoding],0);
		NSArray <MTEdl *> *edls = self.show.edlList;
		if (edls.count > 0 && (self.shouldMarkCommercials || self.shouldSkipCommercials)) {
			[edls addAsChaptersToMP4File: encodedFile forShow: self.show.showTitle withLength: self.show.showLength keepingCommercials: !self.shouldSkipCommercials ];
		}
		if (self.shouldEmbedSubtitles && self.captionFilePath) {
			NSArray * srtEntries = [NSArray getFromSRTFile:self.captionFilePath];
			if (srtEntries.count > 0) {
				[srtEntries embedSubtitlesInMP4File:encodedFile forLanguage:[MTSrt languageFromFileName:self.captionFilePath]];
			}
			if ( ! ([[NSUserDefaults standardUserDefaults] boolForKey:kMTKeepSRTs]  ||
					[[NSUserDefaults standardUserDefaults] boolForKey:kMTSaveTmpFiles] )) {
				[[NSFileManager defaultManager] removeItemAtPath:self.captionFilePath error:nil];
			}
		}
		if (self.encodeFormat.canAcceptMetaData) {
			[self.show addExtendedMetaDataToFile:encodedFile withImage:self.show.artWorkImage];
		}
		
		MP4Close(encodedFile, MP4_CLOSE_DO_NOT_COMPUTE_BITRATE);
	}

	if (self.addToiTunesWhenEncoded) {
		self.downloadStatus = @(kMTStatusAddingToItunes);
		DDLogMajor(@"Adding to iTunes %@", self);
		__weak __typeof__(self) weakSelf = self;
		dispatch_async(dispatch_get_global_queue( DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(void){
			MTiTunes *iTunes = [[MTiTunes alloc] init];
			NSString * iTunesPath = [iTunes importIntoiTunes:weakSelf withArt:weakSelf.show.artWorkImage] ;
			NSString * path = weakSelf.encodeFilePath;
			if (!iTunesPath) {
				DDLogMajor(@"Nil from iTunes; problem adding %@ at %@?", weakSelf, path);
			} else if ( [iTunesPath isEqualToString: path]) {
				DDLogMajor(@"Added %@ to iTunes at %@", self, path);
			} else {
				DDLogMajor(@"Copied %@ to iTunes from %@ to %@", weakSelf, path, iTunesPath);
			}
			dispatch_async(dispatch_get_main_queue(), ^{
				__typeof__(self) strongSelf = weakSelf;
				if (iTunesPath && ![iTunesPath isEqualToString: strongSelf.encodeFilePath]) {
					//apparently iTunes created new file
					if ([[NSUserDefaults standardUserDefaults] boolForKey:kMTiTunesDelete ]) {
                        DDLogDetail(@"Deleting %@", path);
						[strongSelf deleteVideoFile];
						//move caption, commercial, and pytivo metadata files along with video
						NSString * iTunesBaseName = [iTunesPath stringByDeletingPathExtension];
						if (strongSelf.shouldEmbedSubtitles && strongSelf.captionFilePath) {
							strongSelf.captionFilePath = [strongSelf moveFile:strongSelf.captionFilePath toITunes:iTunesBaseName forType:@"caption" andExtension: @"srt"] ?: strongSelf.captionFilePath;
						}
						if (strongSelf.genTextMetaData.boolValue) {
							NSString * textMetaPath = [strongSelf.encodeFilePath stringByAppendingPathExtension:@"txt"];
							NSString * doubleExtension = [[strongSelf.encodeFilePath pathExtension] stringByAppendingString:@".txt"];
							[strongSelf moveFile:textMetaPath toITunes:iTunesBaseName forType:@"metadata" andExtension:doubleExtension];
						}
						//deleted our original, so remember new iTunes file for future processing
						strongSelf.encodeFilePath= iTunesPath;
					} else {
						//keeping both old file and iTunes one
						//So, need to add xattrs to iTunes copy as well
						[tiVoManager addShow: strongSelf.show onDiskAtPath: iTunesPath];
					}
				}
				[tiVoManager addShow: self.show onDiskAtPath:self.encodeFilePath];
				[strongSelf notifyAndCleanUp];
			});
		});
	} else {
		[tiVoManager addShow: self.show onDiskAtPath:self.encodeFilePath];
		[self notifyAndCleanUp];
		
	}
}

-(void) notifyAndCleanUp {
#ifndef DEBUG
	NSInteger retries = ([[NSUserDefaults standardUserDefaults] integerForKey:kMTNumDownloadRetries] - self.numRetriesRemaining) ;
	NSString * retryString = [NSString stringWithFormat:@"%d",(int) retries];
	[Answers logCustomEventWithName:@"Success"
				   customAttributes:@{@"Format" : self.encodeFormat.name,
									  @"Type" : [NSString stringWithFormat:@"%d",(int)[self taskFlowType]],
									  @"Retries" : retryString }];
#endif
	[self notifyUserWithTitle:@"TiVo show transferred." subTitle:nil ];
	if (self.deleteAfterDownload.boolValue) {
		DDLogReport(@"Deleting %@ from TiVo after successful download",self);
		[self.show.tiVo deleteTiVoShows:@[self.show] ];
	}
	[self cleanupFiles];
	self.downloadStatus = @(kMTStatusDone);
	[self launchUserScript];
}

-(void) addEDLtoFilesOnDisk {
	if (self.show.edlList.count == 0) return;
	MTTiVoShow * show = self.show;
	for (NSString * filename in show.copiesOnDisk) {
		MP4FileHandle *encodedFile = MP4Modify([filename cStringUsingEncoding:NSUTF8StringEncoding],0);
		BOOL added = [show.edlList addAsChaptersToMP4File: encodedFile forShow: show.showTitle withLength: show.showLength keepingCommercials: YES ];
		if (added) DDLogMajor(@"Retroactively added commercial info to download %@ in file %@", self, filename);
		MP4Close(encodedFile, MP4_CLOSE_DO_NOT_COMPUTE_BITRATE);
	}
}

-(void) skipModeUpdated: (NSNotification *) notification {
	if (notification.object == self || notification.object == self.show ) {
		DDLogDetail(@"Possible SkipMode Info change for %@", self);
		[self skipModeCheck];
	}
}

-(void) skipModeCheck {
	if ([self.show.protectedShow boolValue]) return;
	if (self.downloadStatus.intValue == kMTStatusRemovedFromQueue) return; //we've been deleted
	NSInteger commStrategy = [[NSUserDefaults standardUserDefaults] integerForKey:@"CommercialStrategy"];
	//check for contradiction between userDefaults and this download
	if (self.useSkipMode) {
		if (commStrategy == 0) commStrategy = 3;
	} else  {
		if (commStrategy  > 0) commStrategy = 0;
	}
	
	BOOL needEDLNow = ( self.isNew && self.shouldSkipCommercials) ||
					  ( self.downloadStatus.intValue == kMTStatusSkipModeWaitEnd && self.shouldMarkCommercials);
	if (self.show.hasSkipModeList || commStrategy == 0 || ! needEDLNow) {
		//ready to go to next step
		[self stopWaitSkipModeTimer];
		switch (self.downloadStatus.intValue) {
			case kMTStatusNew:
				[self checkQueue];
				break;
			case kMTStatusSkipModeWaitInitial:
				DDLogMajor(@"%@ was waiting for SkipMode, but now launching; commStrategy = %d", self, (int)commStrategy);
				if (self.shouldSkipCommercials && !self.show.hasSkipModeList) { //otherwise we're good to go
					switch (commStrategy) {
						case 0:						//comskip only, so proceed
							break;
						case 1: 					//SkipMode only, so give up
							self.skipCommercials = NO;
							self.markCommercials = NO;
							break;
						case 2: 					//skipMode => comskip
							_useSkipMode = NO;
							break;
						case 3:						//skipMode => comskip mark only
							_useSkipMode = NO;
							self.skipCommercials = NO;
							if (self.canMarkCommercials) self.markCommercials = YES;
							break;
						default:
							break;
					}
				}
				self.downloadStatus = @(kMTStatusNew);
				[self checkQueue];
				break;
			case kMTStatusSkipModeWaitEnd:
				if (self.show.hasSkipModeList) {
					DDLogMajor(@"Got EDL for %@: %@", self, self.show.edlList);
					[self addEDLtoFilesOnDisk];
					[self finalFinalProcessing];
				} else if ( !self.shouldMarkCommercials) {
					DDLogMajor(@"Was waiting for SkipMode Mark, but it's not coming, and user disabled mark for %@", self);
					[self finalFinalProcessing];
				} else if (commStrategy == 1) {
					DDLogMajor(@"Was waiting for SkipMode Mark, but it's not coming for %@, and user requested no comskip", self);
					[self finalFinalProcessing];
				} else {
					DDLogMajor(@"Was waiting for SkipMode Mark, but user disabled for %@; launching comskip", self);
					self.downloadStatus = @kMTStatusAwaitingPostCommercial ;
					[self checkQueue];
				}
				break;
			case kMTStatusAwaitingPostCommercial:
				if (!self.shouldMarkCommercials) { //looks like user changed their mind
					[self finalFinalProcessing];
				}
				break;
			default:
				break;
		}
	} else if (!self.show.mightHaveSkipModeInfo) {
		//skip mode never coming
		[self stopWaitSkipModeTimer];
		if (self.show.skipModeFailed) {
			DDLogReport(@"Got Invalid EDL for %@", self);
		} else {
			DDLogMajor(@"Not waiting any more for SkipMode for %@", self);
		}
		_useSkipMode = NO;  //switch to comskip, but avoid recursion
		if (self.downloadStatus.intValue == kMTStatusSkipModeWaitInitial ||
			self.downloadStatus.intValue == kMTStatusNew) {
			if (commStrategy == 1) { 					//SkipMode only, so give up
				self.skipCommercials = NO;
				self.markCommercials = NO;
			} else if (commStrategy == 3 && self.skipCommercials) {						//skipMode => comskip mark only
				self.skipCommercials = NO;
				if (self.canMarkCommercials) self.markCommercials = YES;
			}
			self.downloadStatus = @(kMTStatusNew);
			[self checkQueue];
		} else if (self.downloadStatus.intValue == kMTStatusSkipModeWaitEnd) {
			if (commStrategy == 1) { //skipMode only
				[self finalFinalProcessing];
			} else if (commStrategy == 2 || commStrategy == 3) { //already at mark; fallback to comskip Mark
				DDLogMajor(@"Launching comskip post-processing %@", self);
				self.downloadStatus = @kMTStatusAwaitingPostCommercial ;
			}
			[self checkQueue];
		}
	} else {
		//SkipMode list not here yet, but still expected, so need to wait
		if (self.downloadStatus.intValue == kMTStatusNew) {
			self.downloadStatus = @(kMTStatusSkipModeWaitInitial);
			//will recurse to update timers
		} else if (self.show.hasSkipModeInfo) {
			//now we want the skipmode EDL, but it hasn't been pulled over yet
			[self stopWaitSkipModeTimer];
			DDLogDetail(@"Now Waiting for SkipMode EDL %@", self);
			[tiVoManager getSkipModeEDLWhenPossible:self];
		} else {
			[self startWaitSkipModeTimer];
		}
	}
}

-(void) skipModeExpired: (NSTimer *) timer {
	//called if timer expires on downloading show info
	BOOL firstTime = ((NSNumber *)timer.userInfo).boolValue;
	DDLogMajor(@"%@ SkipModeTimer went off for %@, which ended at %@", firstTime ? @"Initial" : @"Final", self, self.show.stopTime);
	[self stopWaitSkipModeTimer];
	if (!self.useSkipMode) return;
	if (firstTime) {
		if (self.show.hasSkipModeInfo || self.show.hasSkipModeList) {
			DDLogReport(@"SkipModeTimer went off, but we have SkipMode info?? %@",self);
			[self skipModeCheck];
			return; //shouldn't be here
		}
		//one last try, but make sure we eventually move forward.
		[self.show.tiVo loadSkipModeInfoForShow: self.show ];
		self.waitForSkipModeInfoTimer = [MTWeakTimer scheduledTimerWithTimeInterval:30 target:self selector:@selector(skipModeExpired:) userInfo:@NO repeats:NO]; //@NO = second try
	} else {
		DDLogMajor(@"Backup SkipModeTimer went off for %@",self);
		[self skipModeCheck];
	}
}

-(void) startWaitSkipModeTimer {
	if (!self.waitForSkipModeInfoTimer) {
		NSTimeInterval waitTime = self.show.timeLeftTillRPCInfoWontCome+10;
		if (waitTime > 0) {
			DDLogMajor(@"Setting skipModeTimer at %0.1f minutes for %@", waitTime/60.0, self );
			self.waitForSkipModeInfoTimer = [MTWeakTimer scheduledTimerWithTimeInterval:waitTime target:self selector:@selector(skipModeExpired:) userInfo:@YES repeats:NO]; //@YES = first try
		}
	}
}

-(void) stopWaitSkipModeTimer {
	[self.waitForSkipModeInfoTimer invalidate]; self.waitForSkipModeInfoTimer = nil;
}

-(void) finishUpPostEncodeProcessing {
	//This is called from Completion routines of tasks. Let them finish up before final pass
	[self performSelector:@selector(finishUpPostEncodeProcessingDelayed) withObject:nil afterDelay:0.1];
}

-(void) finishUpPostEncodeProcessingDelayed {
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(finishUpPostEncodeProcessingDelayed) object:nil];
    if (_decryptTask.isRunning ||
        _encodeTask.isRunning ||
        _commercialTask.isRunning ||
        _captionTask.isRunning)  {
        //if any of the tasks exist and are still running, then let them finish; checkStillActive will eventually fail them if no progress
        DDLogMajor(@"Finishing up, but processes still running for %@", self);
        [self performSelector:@selector(finishUpPostEncodeProcessingDelayed) withObject:nil afterDelay:0.5];
        return;
    }
	NSDate *startTime = [NSDate date];
    DDLogMajor(@"Starting finishing @ %@",startTime);
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(checkStillActive) object:nil];
    if (self.encodeFormat.isTestPS) {
		self.downloadStatus = @(kMTStatusDone);
	} else {
        if ((_decryptTask && !_decryptTask.successfulExit) ||
			(_encodeTask && !_encodeTask.successfulExit)) {
            DDLogReport(@"Strange: thought we were finished, but later %@ failure", _decryptTask.successfulExit ? @"encode" : @"decrypt");
            [self cancel]; //just in case
            self.downloadStatus = @(kMTStatusFailed);
            return;
        }
        DDLogVerbose(@"Took %lf seconds to complete for show %@",[[NSDate date] timeIntervalSinceDate:startTime], self);
    }
	if (self.markCommercials && self.useSkipMode) {
		self.downloadStatus = @(kMTStatusSkipModeWaitEnd);
		[self skipModeCheck];
	} else {
		[self finalFinalProcessing];
	}
    [NSNotificationCenter postNotificationNameOnMainThread:kMTNotificationShowDownloadDidFinish object:self];  //Currently Free up an encoder/ notify subscription module / update UI
    self.processProgress = 1.0;

    //Reset tasks
	self.decryptTask = nil;
	self.captionTask = nil;
	self.commercialTask = nil;
	self.encodeTask  = nil;
}

-(void)launchPostCommercial {
	//used when we are waiting for skipMode, and realize it's never coming.
	//called from TiVoManager right after incrementing numencoders or when user turns off comskip
	if (!self.decryptedFilePath) {
		//should never happen
		DDLogReport(@"No decrypted file! %@", self);
		[self rescheduleDownload];
		[NSNotificationCenter postNotificationNameOnMainThread:kMTNotificationShowDownloadWasCanceled object:nil];  //Decrement num encoders right away
		return;
	}
	DDLogMajor(@"Starting post-processing comskip for %@; Format: %@", self, self.encodeFormat.name);
	
	self.progressAt100Percent = nil;  //Reset end of progress failure delay
	//Before starting make sure we can launch.
	
	self.commercialTask = nil;
	
	self.activeTaskChain = [MTTaskChain new];
	self.activeTaskChain.download = self;
	DDLogMajor(@"Post-Commercialing for MPG file %@",self.decryptedFilePath);
	MTTask * commercialTask = self.commercialTask;
	if (commercialTask) {
		self.activeTaskChain.taskArray = @ [@[commercialTask]] ; 
	} else {
		self.activeTaskChain = nil;
	}
	self.processProgress = 0.0;
	if (![self.activeTaskChain run]) {
		DDLogReport(@"Could not launch post-processing comskip %@; Format: %@", self, self.encodeFormat.name);
		[self rescheduleDownload];
	};
}

#pragma mark - Download Termination or Rescheduling

// There are three a download can finish: success, failure, or canceled.
// If successful, call finishUpPostEncodeProcessing.
// 		If it doesn't needs SkipCom Marking, this will call finalFinalProcessing.
// 		If it does, then eventually skipModeCheck will call finalFinalProcessing.
// If failed download, call RescheduleDownload, which has two variants: RescheduleDownload decrements retries. RescheduleDownloadFalseStart is for non-download-specific cases (e.g. Server is Busy, or Access Forbidden or we found out this was a Transport Stream, so need to start over)., and decrements the startupRetries (which user doesn't have control over).
// To cancel download in the middle, (e.g user specifies Reschedule), normally call preparefordownload, which resets retry count and DL status to new. PrepareForDownload is also used before adding to queue, by user or subscription. If you want to cancel and never retry, just call cancel directly, then set DL status to failure.

// Cancel makes sure all connections/processes have ceased, called by both prepareForDownload and Reschedule. Does not update DL or retry status.

// 	Note that either finishUpPostEncodeProcessing and cancel must eventually be called to notify Tivo that any show has finished (freeing up an "encoder" for another show). Cancel will only call for an In-progress show.

-(void)cleanupFiles {
	BOOL deleteFiles = ![[NSUserDefaults standardUserDefaults] boolForKey:kMTSaveTmpFiles];
	NSFileManager *fm = [NSFileManager defaultManager];
	DDLogDetail(@"%@ cleaningup files",self);
	if (self.nameLockFilePath) {
		if (deleteFiles) {
			DDLogVerbose(@"deleting Lockfile %@",self.nameLockFilePath);
			[fm removeItemAtPath:self.nameLockFilePath error:nil];
		}
	}
	if (self.encodeFormat.isTestPS) {
		//delete final file as this was a test
		[self deleteVideoFile];
	}
	//Clean up files in TmpFilesDirectory
	NSString *tmpDir = self.tmpDirectory;
	if (deleteFiles && tmpDir && self.baseFileName) {
		NSArray *tmpFiles = [fm contentsOfDirectoryAtPath:tmpDir error:nil];
		for (NSString *file in tmpFiles) {
			NSRange tmpRange = [file rangeOfString:self.baseFileName];
			if (tmpRange.location != NSNotFound) {
				//check if we're looking at a "episodename" file versus a "episodename-n" file
				NSUInteger nextChar = NSMaxRange(tmpRange);
				if (file.length > nextChar &&
					(char)[file characterAtIndex:nextChar] == '-') {
					DDLogDetail(@"For baseFileName %@, ignoring another download's tmp file %@", self.baseFileName, file);
					continue;
				}
				DDLogDetail(@"For basename %@, deleting temp file %@", self.baseFileName, file);
				NSError * error = nil;
				NSString * tmpPath = [tmpDir stringByAppendingPathComponent:file];
				if ( ![fm removeItemAtPath:tmpPath error:&error]) {
					DDLogMajor(@"Could not delete tmp file: %@ because %@", tmpPath, error.localizedDescription ?:@"No reason found");
				}
			}
		}
	}
}

-(void) rescheduleDownload {
	if (![NSThread isMainThread]) {
		[self performSelectorOnMainThread:@selector(rescheduleDownload) withObject:nil waitUntilDone:YES];
	} else {
		[self rescheduleDownload:NO];
	}
}

-(void) rescheduleDownloadFalseStart {
	if (![NSThread isMainThread]) {
		[self performSelectorOnMainThread:@selector(rescheduleDownloadFalseStart) withObject:nil waitUntilDone:YES];
	} else {
		[self rescheduleDownload:YES];
	}
}

-(void)rescheduleDownload:(BOOL) falseStart {
    if (self.isRescheduled) {
        return;
    }
    self.isRescheduled = YES;
    if (self.isDownloading) {
        DDLogMajor(@"%@ downloaded %ldK of %0.0f KB; %0.1f%% processed",self,self.totalDataDownloaded/1000, self.show.fileSize/1000, self.processProgress*100);
    }
    if (self.encodeFormat.isTestPS) {
        //if it was a test, then we knew it would fail whether it's audio-only OR no video encoder, so everything's good
        if (!self.isDone) {
            //test failed without triggering a audiocheck!
            DDLogReport(@"Failure during PS Test for %@", self );
			[self cancel];
            self.downloadStatus = @(kMTStatusFailed);
        }
        self.processProgress = 1.0;
    } else {
        DDLogMajor(@"Stopping at %@, %@ download of %@ with progress at %lf with previous check at %@",self.showStatus,(self.numRetriesRemaining > 0) ? @"restarting":@"canceled",  self, self.processProgress, self.previousCheck );
        [self cancel];
		self.baseFileName = nil;
        if (self.downloadStatus.intValue == kMTStatusDeleted) {
            self.numRetriesRemaining = 0;
            self.processProgress = 1.0;
            [self notifyUserWithTitle: @"TiVo deleted program."
                             subTitle:@"Download cancelled"];
        } else if ((!falseStart && self.numRetriesRemaining        <= 0) ||
                   ( falseStart && self.numStartupRetriesRemaining <= 0)) {
            self.downloadStatus = @(kMTStatusFailed);
            self.processProgress = 1.0;
#ifndef DEBUG
           [Answers logCustomEventWithName:@"Failure"
                           customAttributes:@{ @"Format" : self.encodeFormat.name,
                                               @"Type" : [NSString stringWithFormat:@"%d",(int)[self taskFlowType]]}];
#endif
            [self notifyUserWithTitle: @"TiVo show failed."
                             subTitle:@"Retries Cancelled"];
			[self launchUserScript];
        } else {
            if (falseStart) {
				self.numStartupRetriesRemaining--;
				DDLogDetail(@"Decrementing startup retries to %@",@(self.numStartupRetriesRemaining));
			} else {
				self.numRetriesRemaining--;
                [self notifyUserWithTitle:@"TiVo show failed" subTitle:@"Retrying" ];
#ifndef DEBUG
                [Answers logCustomEventWithName:@"Retry"
                               customAttributes:@{ @"Format" : self.encodeFormat.name,
                                                   @"Type" : [NSString stringWithFormat:@"%d",(int)[self taskFlowType]]}];
#endif
                DDLogMajor(@"Decrementing retries to %ld",(long)self.numRetriesRemaining);
				[self launchUserScript];
            }
            self.downloadStatus = @(kMTStatusNew);
        }
    }
	[self checkQueue];
}

-(void) cancel {
    if (self.isCanceled || self.isNew || self.isCompletelyDone) {
        return;
    }
    self.isCanceled = YES;
    DDLogMajor(@"Canceling of %@", self);
//    NSFileManager *fm = [NSFileManager defaultManager];
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    if (self.activeURLConnection) {
        [self.activeURLConnection cancel];
        self.activeURLConnection = nil;
		if (self.downloadStatus.intValue == kMTStatusDownloading) {
			self.show.tiVo.lastDownloadEnded = [NSDate date];
		}
	}
    if (self.activeTaskChain.isRunning) {
        [self.activeTaskChain cancel];
    }
	[self cancelPerformanceTimer];
    self.activeTaskChain = nil;
//    [[NSNotificationCenter defaultCenter] removeObserver:self name:NSFileHandleReadCompletionNotification object:bufferFileReadHandle];
    if ( self.isInProgress ) { //tests are already marked for success/failure
        [NSNotificationCenter postNotificationNameOnMainThread:kMTNotificationShowDownloadWasCanceled object:nil];
    }
	self.decryptTask = nil;
	self.captionTask = nil;
	self.commercialTask = nil;
	self.encodeTask  = nil;
    
	NSDate *now = [NSDate date];
    while (self.writingData && (-1.0 * [now timeIntervalSinceNow]) < 5.0){ //Wait for no more than 5 seconds.
        sleep(0.01);
        //Block until latest write data is complete - should stop quickly because isCanceled is set
        //self.writingData = NO;
    } //Wait for pipe out to complete
    DDLogMajor(@"Waiting %lf seconds for write data to complete during cancel", (-1.0 * [now timeIntervalSinceNow]) );
    
    [self cleanupFiles]; //Everything but the final file
    if (self.downloadStatus.intValue == kMTStatusDone) {
        self.baseFileName = nil;  //Force new file for rescheduled, complete show.
    }
    self.processProgress = 0.0;
}

#pragma mark - Video manipulation methods

-(NSURL *) URLExists: (NSString *) path {
	if (!path) return nil;
	path = [path stringByExpandingTildeInPath];
	if ([[NSFileManager defaultManager] fileExistsAtPath:path] ){
		return [NSURL fileURLWithPath: path];
	} else {
		return nil;
	}
}

-(NSURL *) videoFileURLWithEncrypted: (BOOL) encrypted {
	NSURL *   URL = nil;
	if (self.isDone) {
		URL =  [self URLExists: self.encodeFilePath];
		if (!URL) {
			URL = [self URLExists:self.decryptedFilePath];
		}
		if (!URL && encrypted) {
			if ([self.bufferFilePath contains:@".tivo"]){ //not just a buffer
				URL= [self URLExists: self.bufferFilePath];
			}
		}
	}
	if (!URL) {
		NSArray <NSString *> * paths = self.show.copiesOnDisk;
		if (paths.count > 0) {
			URL = [NSURL fileURLWithPath: paths[0]];
		}
	}
	return URL;
}

-(BOOL) canPlayVideo {
	return	self.isDone && [self videoFileURLWithEncrypted:NO];
}

-(BOOL) playVideo {
	if (self.isDone ) {
		NSURL * showURL =[self videoFileURLWithEncrypted:NO];
		if (showURL) {
			DDLogMajor(@"Playing video %@ ", showURL);
			return [[NSWorkspace sharedWorkspace] openURL:showURL];
		}
	}
	return [self.show playVideo];
}

#pragma mark - Background routines

-(void)checkStillActive {
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(checkStillActive) object:nil];
	if (self.isCanceled || !self.isInProgress) {
		return;
	}
	
	BOOL reschedule = NO;
	if (self.previousProcessProgress == self.processProgress) { //The process is stalled so ...
		//Cancel and restart or delete depending on number of time we've been through this
		if (self.processProgress == 1.0) {
			if (!self.progressAt100Percent) {  //This is the first time here so record as the start of 100 % period
				DDLogMajor(@"Starting extended wait for 100%% progress stall (Handbrake) for show %@",self);
				self.progressAt100Percent = [NSDate date];
			} else if ([[NSDate date] timeIntervalSinceDate:self.progressAt100Percent] > kMTProgressFailDelayAt100Percent){
				DDLogReport(@"Failed extended wait for 100%% progress stall (Handbrake) for show %@",self);
				reschedule = YES;
			} else {
				DDLogVerbose(@"In extended wait for Handbrake");
			}
		} else {
			reschedule = YES;
			DDLogMajor (@"process stalled at %0.1f%%; rescheduling show %@ ", self.processProgress*100.0, self);
		}
	} else if ([self isInProgress]){
		DDLogVerbose (@"Progress check OK for %@; %0.2f%%", self, self.processProgress*100);
		self.previousProcessProgress = self.processProgress;
	}
	if (reschedule) {
		[self rescheduleDownload];
	} else {
		[self performSelector:@selector(checkStillActive) withObject:nil afterDelay:[[NSUserDefaults standardUserDefaults] integerForKey: kMTMaxProgressDelay]];
	}
	self.previousCheck = [NSDate date];
}

-(void)writeData {
    // writeData supports getting its data from either an NSData buffer (self.urlBuffer) or a file on disk (self.bufferFilePath).  This allows cTiVo to
    // initially try to keep the dataflow off the disk, except for final products, where possible.  But, the ability to do this depends on the
    // processor being able to keep up with the data flow from the TiVo which is often not the case due to either a slow processor, fast network
    // connection, of different tasks competing for processor resources.  When the processor falls too far behind and the memory buffer will
    // become too large cTiVo will fall back to using files on the disk as a data buffer.
    @autoreleasepool {  //because run as separate thread

	//	self.writingData = YES;
    //DDLogVerbose(@"Writing data %@ : %@Connection %@", [NSThread isMainThread] ? @"Main" : @"Background", self.activeURLConnection == nil ? @"No ":@"", self.isCanceled ? @"- Cancelled" : @"");
    const long chunkSize = 65536;
    long dataRead = chunkSize; //to start loop
    while (dataRead == chunkSize && !self.isCanceled) {
        @autoreleasepool {
            NSData *data = nil;
			@try {
                 if (self.urlBuffer) {
                    @synchronized(self.urlBuffer) {
                        long sizeToWrite = self.urlBuffer.length - self.urlReadPointer;
                        if (sizeToWrite > chunkSize) {
                            sizeToWrite = chunkSize;
                        }
                        data = [self.urlBuffer subdataWithRange:NSMakeRange(self.urlReadPointer, sizeToWrite)];
                        self.urlReadPointer += sizeToWrite;
                    }
                } else {
                    data = [self.bufferFileReadHandle readDataOfLength:chunkSize];
                }
			}
			@catch (NSException *exception) {
                if (!self.isCanceled){
                    [self rescheduleDownload];
                    DDLogDetail(@"Rescheduling");
                };
				DDLogMajor(@"buffer read fail:%@; %@", exception.reason, self);
			}
			@finally {
			}
            if (self.isCanceled || data.length == 0) break;
            dataRead = data.length;
              //should just be following line, but it crashes program in the event of a bad pipe
              //@try
              //[self.taskChainInputHandle writeData:data];
              //@catch

            NSInteger numTries = 3;
            size_t bytesLeft = data.length;
            while (numTries > 0 && bytesLeft > 0) {
                ssize_t amountSent= write ([self.taskChainInputHandle fileDescriptor], [data bytes]+data.length-bytesLeft, bytesLeft);
                if (amountSent < 0) {
                    if (!self.isCanceled){
                        DDLogReport(@"write fail1 for %@; tried %lu bytes; error: %zd",self, (unsigned long)[data length], amountSent);
                    };
                    break;
                } else {
                    bytesLeft = bytesLeft- amountSent;
                    if (bytesLeft > 0) {
                        DDLogMajor(@"write pipe full, retrying; tried %lu bytes; wrote %zd", (unsigned long)[data length], amountSent);
                        sleep(1);  //probably too long, but this is quite rare
                        numTries--;
                    }
                }
            }
            if (bytesLeft > 0) {
                if (numTries == 0) {
                    DDLogReport(@"Write Fail2: couldn't write to pipe after three tries");
                }
                if (!self.isCanceled) {
					[self rescheduleDownload];
                }
            }

            @synchronized (self) {
                self.totalDataRead += dataRead;
                double newProgress = self.totalDataRead/self.show.fileSize;
                DDLogVerbose(@"For %@, read %luKB of %luKB: %0.1f%% processed", self, dataRead/1000, self.totalDataRead/1000, newProgress *100);
                self.processProgress = newProgress;
            }
         }
    }
	self.writingData = NO; //we are now committed to closing this background thread, so any further data will need new thread
	if (!self.activeURLConnection || self.isCanceled) {
		DDLogDetail(@"Writedata all done for show %@",self);
		[self.taskChainInputHandle closeFile];
		self.taskChainInputHandle = nil;
        [self.bufferFileReadHandle closeFile];
		self.bufferFileReadHandle = nil;
    }
    }//end autoreleasepool

}
#pragma mark - NSURLConnection delegate routines.

-(void) connection:(NSURLConnection *) connection didReceiveResponse:(nonnull NSURLResponse *)response {
	DDLogVerbose(@"MainURL: %@", [self.activeURLConnection.currentRequest URL]);
	DDLogVerbose(@"Headers for Request: %@", [self.activeURLConnection.currentRequest allHTTPHeaderFields]);
	NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse*)response;
	if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
		DDLogVerbose(@"Response: %@ - %@",@([httpResponse statusCode]), [NSHTTPURLResponse localizedStringForStatusCode:[httpResponse statusCode]]);
		DDLogVerbose(@"Response Headers: %@", [httpResponse allHeaderFields]);
	}
}

NSString * cTiVoDomain = @"com.ctivo.ctivo";
NSInteger diskWriteFailure = 123;

-(void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
	if (self.isCanceled) return;
	self.totalDataDownloaded += data.length;
    if (self.urlBuffer) {
        // cTiVo's URL connection supports sending its data to either an NSData buffer (self.urlBuffer) or a file on disk (self.bufferFilePath).  This allows cTiVo to 
        // initially try to keep the dataflow off the disk, except for final products, where possible.  But, the ability to do this depends on the processor 
        // being able to keep up with the data flow from the TiVo which is often not the case due to either a slow processor, fast network connection, of
        // different tasks competing for processor resources.  When the processor falls too far behind and the memory buffer will become too large
        // cTiVo will fall back to using files on the disk as a data buffer.

		@synchronized (self.urlBuffer){
			[self.urlBuffer appendData:data];
			if (self.urlBuffer.length > kMTMaxBuffSize) {
				DDLogMajor(@"self.urlBuffer length exceeded %d, switching to file based buffering",kMTMaxBuffSize);
				[[NSFileManager defaultManager] createFileAtPath:self.bufferFilePath contents:[self.urlBuffer subdataWithRange:NSMakeRange(self.urlReadPointer, self.urlBuffer.length - self.urlReadPointer)] attributes:nil];
				self.bufferFileReadHandle = [NSFileHandle fileHandleForReadingAtPath:self.bufferFilePath];
				self.bufferFileWriteHandle = [NSFileHandle fileHandleForWritingAtPath:self.bufferFilePath];
				[self.bufferFileWriteHandle seekToEndOfFile];
				self.urlBuffer = nil;
                self.urlReadPointer = 0;
			}
			if (self.urlBuffer && self.urlReadPointer > kMTMaxReadPoints) {  //Only compress the buffer occasionally for better performance.  
				[self.urlBuffer replaceBytesInRange:NSMakeRange(0, self.urlReadPointer) withBytes:NULL length:0];
				self.urlReadPointer = 0;
			}
		};
	} else {
        @try {
            [self.bufferFileWriteHandle writeData:data];
        } @catch (NSException *exception) {
            NSDictionary * info = @{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Disk write failure: %@",exception.reason],
                                     NSLocalizedRecoverySuggestionErrorKey: @"Delete some files and try again?",
                                     };
            NSError * error = [NSError errorWithDomain: cTiVoDomain code: diskWriteFailure userInfo:info];
            [self connection:connection didFailWithError:error];
            return;
        }
	}
        
    @synchronized (self) {
        if (!self.writingData && (!self.urlBuffer || self.urlBuffer.length > kMTMaxPointsBeforeWrite)) {  //Minimized thread creation as it's expensive
            self.writingData = YES;
            [self performSelectorInBackground:@selector(writeData) withObject:nil];
        }
	}
}

- (void)connection:(NSURLConnection *)connection willSendRequestForAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
{
    BOOL sendingCredential = NO;
    if (challenge.previousFailureCount == 0) {
        if (challenge.proposedCredential) {
            DDLogMajor(@"Using proposed Credential for %@",self.show.tiVoName);
            [challenge.sender useCredential:challenge.proposedCredential forAuthenticationChallenge:challenge];
            sendingCredential = YES;
        } else if (self.show.tiVo.mediaKey.length) {
            DDLogMajor(@"Sending media Key for %@",self.show.tiVoName);
            [challenge.sender useCredential:[NSURLCredential credentialWithUser:@"tivo" password:self.show.tiVo.mediaKey persistence:NSURLCredentialPersistenceForSession] forAuthenticationChallenge:challenge];
            sendingCredential = YES;
        }
    }
    if (!sendingCredential) {
        [challenge.sender cancelAuthenticationChallenge:challenge];
        BOOL noMAK = self.show.tiVo.mediaKey.length == 0;
        DDLogMajor(@"%@ MAK, so failing URL Authentication %@",noMAK ? @"No" : @"Invalid", self.show.tiVoName);
		[self rescheduleDownload];
        [NSNotificationCenter postNotificationNameOnMainThread:kMTNotificationMediaKeyNeeded object:@{@"tivo" : self.show.tiVo, @"reason" : @"incorrect"}];
    }
}

-(void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error
{
    DDLogReport(@"Download URL Connection Failed for %@ with error %@", self, [error maskMediaKeys]);
    
    if ([error.domain isEqualToString:@"com.ctivo.ctivo"] && error.code == diskWriteFailure) {
        [self notifyUserWithTitle: error.userInfo[NSLocalizedDescriptionKey] subTitle: error.userInfo[NSLocalizedRecoverySuggestionErrorKey]];
    } else {
        NSNumber * streamError = error.userInfo[@"_kCFStreamErrorCodeKey"];
        DDLogDetail(@"URL ErrorCode: %@, streamErrorCode: %@ (%@)", @(error.code), streamError, [streamError class]);
        if ([streamError isKindOfClass:[NSNumber class]] &&
            ((error.code == -1004  && streamError.intValue == 49) ||
			 (error.code == -1200  && streamError.intValue == 49) ||
             (error.code == -1005  && streamError.intValue == 57))) {
            [self notifyUserWithTitle: @"Warning: Could not reach TiVo!"
                             subTitle: @"Antivirus program may be blocking connection, or you may need to reboot TiVo"
                      ];
        }
    }
   if (self.activeURLConnection) {
        [self.activeURLConnection cancel];
        self.activeURLConnection = nil;
	   self.show.tiVo.lastDownloadEnded = [NSDate date];
   }
	[tiVoManager checkSleep:nil];
    if (self.bufferFileWriteHandle) {
		[self.bufferFileWriteHandle closeFile];
        self.bufferFileWriteHandle = nil;
	}
	[self rescheduleDownload];
}

#define kMTMinTiVoFileSize 100000
-(void)connectionDidFinishLoading:(NSURLConnection *)connection
{
	DDLogVerbose(@"Download URL Connection finished for %@", self);
	if (self.bufferFileWriteHandle) {
		[self.bufferFileWriteHandle closeFile];
        self.bufferFileWriteHandle   = nil;
	}
    if (self.isCanceled) return;
    //Make sure to flush the last of the buffer file into the pipe and close it.
    @synchronized(self) {
		[self.activeURLConnection cancel];
        self.activeURLConnection = nil;
        if (!self.writingData) {
            DDLogVerbose (@"writing last data for %@",self);
            self.writingData = YES;
            [self performSelectorInBackground:@selector(writeData) withObject:nil];
        }
    }
	[tiVoManager checkSleep:nil];
	self.show.tiVo.lastDownloadEnded = [NSDate date];
    double downloadedFileSize = self.totalDataDownloaded;
    //Check to make sure a reasonable file size in case there was a problem.
	if (downloadedFileSize < kMTMinTiVoFileSize) { //Not a good download - reschedule
        DDLogMajor(@"For show %@, only received %0.0f bytes",self, downloadedFileSize);
        NSString *dataReceived = nil;
        if (self.urlBuffer) {
            dataReceived = [[NSString alloc] initWithData:self.urlBuffer encoding:NSUTF8StringEncoding];
        } else {
            dataReceived = [NSString stringWithEndOfFile:self.bufferFilePath ];
        }
		if (dataReceived) {
			NSRange noRecording = [dataReceived rangeOfString:@"not found" options:NSCaseInsensitiveSearch];
			if (noRecording.location != NSNotFound) { //This is a missing recording
				DDLogReport(@"Deleted TiVo show; marking %@",self);
				[self cancel];
				self.downloadStatus = @(kMTStatusDeleted);
				return;
            } else {
                NSRange serverBusy = [dataReceived rangeOfString:@"Server Busy" options:NSCaseInsensitiveSearch];
                if (serverBusy.location != NSNotFound) { //TiVo is overloaded
                    [self.show.tiVo notifyUserWithTitle: @"TiVo Warning: Server Busy."
                                               subTitle: [NSString stringWithFormat:@"If this recurs, your TiVo (%@) may need to be restarted.", self.show.tiVo.tiVo.name]];
                    DDLogReport(@"Warning Server Busy %@", self);
					[self rescheduleDownloadFalseStart];
                    return;
                } else {
                    NSRange accessForbidden = [dataReceived rangeOfString:@"Access Forbidden" options:NSCaseInsensitiveSearch];
                    if (accessForbidden.location != NSNotFound) { //TiVo is not allowing video transfers
                        [self.show.tiVo notifyUserWithTitle: @"TiVo Warning: Forbidden Access."
                                           subTitle: @"Enable Video Sharing at https://www.tivo.com/tivo-mma/dvrpref.do."];
                        DDLogReport(@"Warning: Forbidden Access %@", self);
						[self rescheduleDownloadFalseStart];
                        return;
                    }
                }
            }
		}
		DDLogMajor(@"Downloaded file too small - rescheduling; File sent was %@",dataReceived);
		[self rescheduleDownloadFalseStart];
	} else {
//		NSLog(@"File size before reset %lf %lf",self.show.fileSize,downloadedFileSize);
        double filePercent = downloadedFileSize / self.show.fileSize*100;
        DDLogDetail(@"finished loading TiVo file: %0.1f of %0.1f KB expected; %0.1f%% ", downloadedFileSize/1000, self.show.fileSize/1000, filePercent);
		if (filePercent > 80.0 || (self.useTransportStream.boolValue && filePercent > 70.0 )) {
			//hmm, looks like it's big enough  (80% for PS; 70% for TS
			self.show.fileSize = downloadedFileSize;  //More accurate file size
            if ([self.bufferFileReadHandle isKindOfClass:[NSFileHandle class]]) {
                if ([[self.bufferFilePath substringFromIndex:self.bufferFilePath.length-4] compare:@"tivo"] == NSOrderedSame  && !self.isCanceled) { //We finished a complete download so mark it so
                    [self markCompleteCTiVoFile:self.bufferFilePath];
                }
            }
		}
		self.downloadStatus = [self postDownloadState];
        [NSNotificationCenter postNotificationNameOnMainThread:kMTNotificationDetailsLoaded object:self.show];
        [NSNotificationCenter postNotificationNameOnMainThread:kMTNotificationTransferDidFinish object:self.show.tiVo afterDelay:kMTTiVoAccessDelay];
	}
}

-(NSNumber *) postDownloadState {
	switch (self.taskFlowType) {
		case kMTTaskFlowNonSimu:  //Just encode with non-simul encoder
		case kMTTaskFlowSimu:  //Just encode with simul encoder
		case kMTTaskFlowSimuSubtitles:  //Encode with simul encoder and subtitles
		case kMTTaskFlowMarkcom:  //Encode with non-simul encoder marking commercials
		case kMTTaskFlowSimuMarkcom:  //Encode with simul encoder marking commercials
		case kMTTaskFlowSimuMarkcomSubtitles:  //Encode with simul encoder marking commercials and subtitles
		return @(kMTStatusEncoding);
		
		case kMTTaskFlowSubtitles:  //Encode with non-simul encoder and subtitles
		case kMTTaskFlowSkipcomSubtitles:  //Encode with non-simul encoder skipping commercials and subtitles
		case kMTTaskFlowSimuSkipcomSubtitles:  //Encode with simul encoder skipping commercials and subtitles
		case kMTTaskFlowMarkcomSubtitles:  //Encode with non-simul encoder marking commercials and subtitles
		return @(kMTStatusCaptioning);
		
		case kMTTaskFlowSkipcom:  //Encode with non-simul encoder skipping commercials
		case kMTTaskFlowSimuSkipcom:  //Encode with simul encoder skipping commercials
		return @(kMTStatusCommercialing);
			
		default:
			return @(kMTStatusEncoding); //never happens
	}
}

#pragma mark - Transport Stream detection

-(MPEGFormat)videoFileType: (NSString *) filePath {
	NSString * ffmpegPath = [[NSBundle mainBundle] pathForAuxiliaryExecutable:@"ffmpeg" ];
	if (!ffmpegPath) {
		DDLogReport(@"couldn't find ffmpeg for %@ in %@", filePath, self);
		return MPEGFormatUnknown;
	}
	NSString * ffmpegOut = [NSTask runProgram:ffmpegPath withArguments:@[@"-i", filePath]];
	if (ffmpegOut.length == 0 || [ffmpegOut contains:@"No such file"]) {
		DDLogReport(@"Invalid file %@ for %@", filePath, self);
		return MPEGFormatUnknown;
	}
	DDLogDetail(@"H264check: %@", ffmpegOut);
	if ([ffmpegOut contains:@"mpeg2video"]) {
		return MPEGFormatMPG2;
	} else if ([ffmpegOut contains:@"h264"]) {
		return MPEGFormatH264;
	} else {
		return MPEGFormatUnknown;
	}
}

-(BOOL) checkLogForAudio: (NSString *) filePath {
	if (!filePath) return NO;
	//if we find audio required, then mark channel as TS.
	//If not, then IF it was a successfulencode, then mark as not needing TS
	if ( ! self.useTransportStream.boolValue) {
		//If we did Program Stream and encoder says "I only see Audio", then probably TS required
		NSArray * audioOnlyStrings = @[
									   @"Video stream is mandatory!",       //mencoder:
									   @"No title found",                   //handbrake
									   @"no video streams",                 //ffmpeg
									   @"Stream #0:0: Audio",               //ffmpeg
									   @"Could not open video codec"        //comskip
									   ];
		NSString *log = [NSString stringWithEndOfFile:filePath ];
		if ( ! log.length) return NO;
		for (NSString * errMsg in audioOnlyStrings) {
			if ([log rangeOfString:errMsg].location != NSNotFound) {
				DDLogVerbose(@"found audio %@ in log file: %@",errMsg, [log maskMediaKeys]);
				return YES;
			}
		}
	}
	return NO;
}

-(void) markMyChannelAsPSOnly {
	NSString * channelName = self.show.stationCallsign;
	self.show.mpegFormat = MPEGFormatMPG2;
	if ( [tiVoManager failedPSForChannel:channelName] != NSOffState ) {
		DDLogMajor(@"Due to problems with %@, converting %@ to Program Stream only",self, channelName);
		BOOL notify = [tiVoManager useTSForChannel:channelName] == NSOnState;
		[tiVoManager setFailedPS:NO forChannelNamed:channelName];
		if (notify) {
			//only notify if we've been forcing TS)
			[self transientNotifyWithTitle:@"MPEG2 Channel" subTitle:[NSString stringWithFormat:@"Due to corrupted video, marking %@ as Program Stream",channelName] ];
		}
	} else {
		DDLogDetail(@"Confirmed MPEG2 in %@ on channel %@",self, channelName);
	}
}


-(void) markMyChannelAsTSOnly {
	NSString * channelName = self.show.stationCallsign;
	self.show.mpegFormat = MPEGFormatH264;
	if ( [tiVoManager failedPSForChannel:channelName] != NSOnState ) {
		DDLogMajor(@"Setting H.264 on %@ due to %@", channelName, self);
		BOOL notify = [tiVoManager useTSForChannel:channelName] == NSOffState;
		[tiVoManager setFailedPS:YES forChannelNamed:channelName];
		if (notify && !self.encodeFormat.isTestPS) {
			//only notify if we're not (testing, OR previously seen, OR forcing PS)
			[self transientNotifyWithTitle:@"H.264 Channel" subTitle:[NSString stringWithFormat:@"Marking %@ as Transport Stream",channelName] ];
		}
	} else {
		DDLogDetail(@"Confirmed H.264 in %@ on channel %@",self, channelName);

	}
}

-(void) handleNewTSChannel {
	[self markMyChannelAsTSOnly];
	//On a regular file, throw away audio-only file and try again
	[self deleteVideoFile];
	if (self.show.tiVo.supportsTransportStream) {
		self.useTransportStream = @YES;
		[self rescheduleDownloadFalseStart];
	} else {
		[self cancel];
		[self setValue:@(kMTStatusFailed) forKeyPath:@"downloadStatus"];
		[self notifyUserWithTitle: @"Warning: This channel requires Transport Stream."
						 subTitle:@"But this TiVo does not support TS." ];
	}
}

#pragma mark - Convenience methods

-(void)transientNotifyWithTitle:(NSString *) title subTitle: (NSString*) subTitle  {   //download  notification
	[tiVoManager notifyForName: self.show.showTitle
					 withTitle: title
					  subTitle: subTitle
					  isSticky: NO
	 ];
}

-(void)notifyUserWithTitle:(NSString *) title subTitle: (NSString*) subTitle   {   //download  notification
	[tiVoManager notifyForName: self.show.showTitle
					 withTitle: title
					  subTitle: subTitle
					  isSticky: YES
	 ];
}

-(BOOL) isInProgress {
	return (!(self.isNew || self.isDone));
}

-(BOOL) isDownloading {
	return ([self.downloadStatus intValue] == kMTStatusDownloading ||[self.downloadStatus intValue] == kMTStatusWaiting );
}

-(BOOL) isCompletelyDone {
	int status = [self.downloadStatus intValue];
	return (status == kMTStatusDone) ||
	(status == kMTStatusFailed) ||
	(status == kMTStatusDeleted) ||
	(status == kMTStatusRemovedFromQueue);
}

-(BOOL) isDone {
	return self.isCompletelyDone || self.downloadStatus.intValue == kMTStatusSkipModeWaitEnd || self.downloadStatus.intValue == kMTStatusAwaitingPostCommercial;
}

-(BOOL) isNew {
	return (self.downloadStatus.intValue == kMTStatusNew || self.downloadStatus.intValue == kMTStatusSkipModeWaitInitial);
}
-(BOOL) shouldSimulEncode {
	return self.encodeFormat.canSimulEncode &&
	       !(self.shouldSkipCommercials && self.runComskipNow);
	       // && !self.downloadingShowFromMPGFile);
}

-(BOOL) shouldCheckMPEG {
	BOOL useTS = self.useTransportStream.boolValue;
	return self.encodeFormat.isTestPS ||
		   (!useTS && !self.encodeFormat.testsForAudioOnly) ||
		   (useTS && ![[NSUserDefaults standardUserDefaults] boolForKey:kMTAllowMP2InTS]);
}

-(BOOL) shouldPipeFromDecrypt {
	return (self.shouldSimulEncode || self.exportSubtitles.boolValue || self.shouldCheckMPEG ) ; //ts for mpegcheck
}

-(BOOL) canSkipCommercials {
    return self.encodeFormat.comSkip.boolValue;
}

-(BOOL) shouldSkipCommercials {
    return self.canSkipCommercials &&
    	   self.skipCommercials &&
           ([tiVoManager commercialsForChannel:self.show.stationCallsign] == NSOnState);
}

-(BOOL) canMarkCommercials {
    return self.encodeFormat.canMarkCommercials;
}

-(BOOL) shouldMarkCommercials {
    return  self.canMarkCommercials &&
            self.markCommercials &&
            ([tiVoManager commercialsForChannel:self.show.stationCallsign] == NSOnState);
}

-(BOOL) canSkipModeCommercials {
	return self.show.tiVo.supportsRPC && (self.canMarkCommercials || self.canSkipCommercials);
}

-(BOOL) mayComskipInFuture {
	return self.markCommercials && self.useSkipMode && !self.hasEDL;
}

-(BOOL) runComskipNow {
	//we're launching now, so should we use comskip or not
	//Either  we want commercials but won't/can't use SkipMode, OR we want to skip but we don't have list yet. (Can add mark later)
	if (self.hasEDL) return NO;
	if (self.shouldSkipCommercials) return YES;
	if (!self.shouldMarkCommercials) return NO;
	if (self.useSkipMode) return NO;
	return YES;
}

-(BOOL) hasEDL { //from either source
	BOOL reuse = [[NSUserDefaults standardUserDefaults] boolForKey:kMTReuseEDLs];
    if (reuse) {
		return self.show.edlList.count > 0;
	} else {
		return self.show.rpcData.edlList.count > 0;
	}
}

-(BOOL) shouldEmbedSubtitles
{
    return (self.encodeFormat.canMarkCommercials && self.exportSubtitles);
}

-(BOOL) canAddToiTunes {
    return self.encodeFormat.canAddToiTunes;
}

-(BOOL) shouldAddToiTunes {
    return self.addToiTunesWhenEncoded;
}

-(BOOL) canPostDetectCommercials {
    return NO; //This is not working well right now because comskip isn't handling even these formats reliably.
//	NSArray * allowedExtensions = @[@".mp4", @".m4v", @".mpg"];
//	NSString * extension = [self.encodeFormat.filenameExtension lowercaseString];
//	return [allowedExtensions containsObject: extension];
}

#pragma mark - Custom Getters

-(NSNumber *)downloadIndex {
	NSInteger index = [tiVoManager.downloadQueue indexOfObject:self];
	return @(index+1);
}


-(NSString *) showStatus {
	switch (self.downloadStatus.intValue) {
		case  kMTStatusNew :				return @"Ready";
		case  kMTStatusSkipModeWaitInitial: return @"Waiting for SkipMode";
		case  kMTStatusWaiting :            return @"Waiting for TiVo";
        case  kMTStatusDownloading :		return @"Downloading";
		case  kMTStatusDownloaded :			return @"Downloaded";
		case  kMTStatusDecrypting :			return @"Decrypting";
		case  kMTStatusDecrypted :			return @"Decrypted";
		case  kMTStatusCommercialing :		return @"Detecting Ads";
		case  kMTStatusCommercialed :		return @"Ads Detected";
		case  kMTStatusEncoding :			return @"Encoding";
		case  kMTStatusEncoded :			return @"Encoded";
        case  kMTStatusAddingToItunes:
			if (@available(macOS 10.15, *)) {
				return @"Adding To TV";
			} else {
				return @"Adding To iTunes";
			}
		case  kMTStatusCaptioned:			return @"Subtitled";
		case  kMTStatusCaptioning:			return @"Subtitling";
        case  kMTStatusMetaDataProcessing:	return @"Adding MetaData";
		case  kMTStatusSkipModeWaitEnd :    return @"Wait SkipMode (Mark)";
		case  kMTStatusPostCommercialing :  return @"Post-Detecting Ads";
		case  kMTStatusAwaitingPostCommercial :  return @"Waiting for Ads";
        case  kMTStatusDone :				return @"Complete";
		case  kMTStatusDeleted :			return @"TiVo Deleted";
		case  kMTStatusFailed :				return @"Failed";
		case  kMTStatusRemovedFromQueue :	return @"Removed From Queue";
		default: return @"";
	}
}

-(NSInteger) downloadStatusSorter {
//used to put column in right order; sorts Done/Failed/waitEnd and Ready/Waiting together
//temporary before updating queue.
    NSInteger status = self.downloadStatus.integerValue;
	if (status == kMTStatusSkipModeWaitInitial) status = kMTStatusNew;
    if (status >= kMTStatusDone ) {
		if (status == kMTStatusSkipModeWaitEnd) {
			status = kMTStatusDone; //sort just below other Done ones
		} else {
			status = kMTStatusDone+1;
		}
    }
    return status;
}

-(NSString *) imageString {
	if (self.downloadStatus.intValue == kMTStatusDeleted) {
		return @"deleted";
	} else {
		return self.show.imageString;
	}
}

-(void) checkQueue {
	[NSNotificationCenter postNotificationNameOnMainThread:kMTNotificationDownloadQueueUpdated object:self.show.tiVo afterDelay:2.0];
}

-(void) setEncodeFormat:(MTFormat *) encodeFormat {
	if (_encodeFormat == encodeFormat ) return;
	if (encodeFormat == [tiVoManager testPSFormat]) {
		_encodeFormat = encodeFormat;
		self.exportSubtitles = @NO;
		self.skipCommercials = NO;
		self.useSkipMode = NO;
		self.markCommercials = NO;
		self.genTextMetaData = @NO;
		self.numRetriesRemaining = 0;
		self.useTransportStream = @NO;
		self.addToiTunesWhenEncoded = NO;
	} else {
		BOOL wasNil = _encodeFormat == nil;
        BOOL iTunesWasDisabled = ![self canAddToiTunes];
        BOOL skipWasDisabled = ![self canSkipCommercials];
        BOOL markWasDisabled = ![self canMarkCommercials];
		BOOL skipModeWasDisabled = ![self canSkipModeCommercials];
		
        _encodeFormat = encodeFormat;
		NSUserDefaults * defaults = [NSUserDefaults standardUserDefaults];
		if ([self canAddToiTunes]) { //newly possible, so take user default
			if (iTunesWasDisabled ) self.addToiTunesWhenEncoded = [defaults boolForKey:kMTiTunesSubmit];
		} else { //no longer possible
            self.addToiTunesWhenEncoded = NO;
        }
		if (self.canSkipCommercials) { //newly possible, so take user default
			if (skipWasDisabled ) self.skipCommercials = [defaults boolForKey:kMTSkipCommercials];
		} else { //no longer possible
            self.skipCommercials = NO;
		}
 		if (self.canMarkCommercials) { //newly possible, so take user default
			if (markWasDisabled) self.markCommercials = [defaults boolForKey:kMTMarkCommercials];
		} else { //no longer possible
			self.markCommercials = NO;
		}
		if ([self canSkipModeCommercials]) { //newly possible, so take user default
			if (skipModeWasDisabled) self.useSkipMode = [defaults integerForKey:kMTCommercialStrategy] > 0;
		} else {
			self.useSkipMode = NO;
		}
		
		if (!wasNil) { //no need at launch
			[self skipModeCheck];
		}
    }
}

-(void) setSkipCommercials:(BOOL)skipCommercials {
	_skipCommercials = skipCommercials;
	if (_skipCommercials && _markCommercials) {
		self.markCommercials = NO;
	}
}

-(void) setMarkCommercials:(BOOL)markCommercials {
	_markCommercials = markCommercials;
	if (_markCommercials && _skipCommercials) {
		self.skipCommercials = NO;
	}
}

#pragma mark - Memory Management

-(void)dealloc
{
	DDLogDetail(@"deallocing Download %@", self);
	[self stopWaitSkipModeTimer];
    if (_performanceTimer) {
        [_performanceTimer invalidate];
        _performanceTimer = nil;
    }
    [self removeObserver:self forKeyPath:@"downloadStatus"];
    [self removeObserver:self forKeyPath:@"processProgress"];
	[[NSNotificationCenter defaultCenter] removeObserver:self];
    [self deallocDownloadHandling];
	
}

-(NSString *)description {
#pragma clang diagnostic ignored "-Wdeprecated-objc-pointer-introspection"
    return [NSString stringWithFormat:@"%@-%@(%x)%@",self.show.showTitle, self.show.tiVoName, ((int)self) & 0xFFFFF,[self.show.protectedShow boolValue]?@"-Protected":@""];
}

@end

