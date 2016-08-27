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
#include <sys/xattr.h>
#include "mp4v2.h"
#include "NSNotificationCenter+Threads.h"

@interface MTDownload ()

@property (nonatomic, strong) MTTiVoShow * show;
@property (nonatomic, strong) NSString *downloadDirectory;

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

@property (nonatomic, readonly) NSString *downloadDir;
@property (strong, nonatomic) NSString *keywordPathPart; // any extra layers of directories due to keyword template

@property (nonatomic) MTTask *decryptTask, *encodeTask, *commercialTask, *captionTask;

@property (nonatomic, strong) NSDate *startTime;
@property (nonatomic, assign) double startProgress;
@property (nonatomic, strong) NSTimer * progressTimer;
@property (nonatomic, assign) int numZeroSpeeds;
@property (nonatomic, assign) BOOL useTransportStream;

@property (atomic, assign) ssize_t  totalDataRead, totalDataDownloaded;

@property (atomic, assign) double speed;

@property (atomic, assign) BOOL volatile isRescheduled, downloadingShowFromTiVoFile, downloadingShowFromMPGFile;

@property (nonatomic, strong) NSString *baseFileName,
*tivoFilePath,  //For reading .tivo file from a prev run (not implemented; reuse bufferFilePath?)
*mpgFilePath,   //For reading decoded .mpg from a prev run (not implemented; reuse decryptedFilePath?)
*bufferFilePath,  //downloaded show prior to decryption; .tivo if complete, .bin if not (due to memory buffer usage)
*decryptedFilePath, //show after decryption; .mpg
*encodeFilePath, //show after encoding (e.g. MP4)
*commercialFilePath,  //.edl after commercial processing
*nameLockFilePath, //.lck to ensure we don't save to same file name twice
*captionFilePath; //.srt after caption processing


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
#ifndef deleteXML
		_genXMLMetaData = nil;
		_includeAPMMetaData = nil;
#endif
		_exportSubtitles = nil;
        _urlReadPointer = 0;
        _useTransportStream = NO;
        _downloadStatus = @(0);
        _baseFileName = nil;
        _processProgress = 0.0;

        [self addObserver:self forKeyPath:@"downloadStatus" options:NSKeyValueObservingOptionNew context:nil];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(formatMayHaveChanged) name:kMTNotificationFormatListUpdated object:nil];
        _previousCheck = [NSDate date];
    }
    return self;
}

+(MTDownload *) downloadForShow:(MTTiVoShow *) show withFormat: (MTFormat *) format intoDirectory: (NSString *) downloadDirectory {
    MTDownload * download = [[MTDownload alloc] init];
    download.show = show;
    download.encodeFormat = format;
    download.downloadDirectory = downloadDirectory;
    return download;
}

+(MTDownload *) downloadTestPSForShow:(MTTiVoShow *) show {
    MTFormat * testFormat = [tiVoManager testPSFormat];
    MTDownload * download = [self downloadForShow:show withFormat: testFormat intoDirectory:[tiVoManager tmpFilesDirectory]];
    download.exportSubtitles = NO;
    download.skipCommercials = NO;
    download.markCommercials = NO;
    download.genTextMetaData = NO;
    download.numRetriesRemaining = 0;
    return download;
}

-(void)prepareForDownload: (BOOL) notifyTiVo {
    //set up initial parameters for download before submittal; can also be used to resubmit while still in DL queue
    if (self.downloadStatus.intValue == kMTStatusDeleted) return;
    self.show.isQueued = YES;
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
    if (!self.downloadDirectory) {
        self.downloadDirectory = tiVoManager.downloadDirectory;
    }
    if (!self.isNew){
        [self setValue:[NSNumber numberWithInt:kMTStatusNew] forKeyPath:@"downloadStatus"];
    }
    if (notifyTiVo) {
        [NSNotificationCenter postNotificationNameOnMainThread:kMTNotificationDownloadQueueUpdated object:self.show.tiVo afterDelay:4.0];
    }
}

-(void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if ([keyPath compare:@"downloadStatus"] == NSOrderedSame) {
		DDLogMajor(@"Changing DL status of %@ to %@ (%@)", object, [(MTDownload *)object showStatus], [(MTDownload *)object downloadStatus]);
        [NSNotificationCenter postNotificationNameOnMainThread:kMTNotificationDownloadRowChanged object:object];
        if (self.progressTimer) {
            //if previous scheduled either cancel or cancel/restart
            [self cancelPerformanceTimer];
        }
         if (self.isInProgress) {
             self.progressTimer = [NSTimer scheduledTimerWithTimeInterval:5 target:self selector:@selector(launchPerformanceTimer:) userInfo:nil repeats:NO];
         }
    }
}

- (void) formatMayHaveChanged{
    //if format list is updated, we need to ensure our format still exists
    //known bug: if name of current format changed, we will not find correct one
    self.encodeFormat = [tiVoManager findFormat:self.encodeFormat.name];
}

-(void) launchPerformanceTimer:(NSTimer *) timer {
    //start Timer after 5 seconds
    self.progressTimer = [NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(updatePerformance:) userInfo:nil repeats:YES];
    self.startTime = [NSDate date];
    self.startProgress = self.processProgress;
    DDLogVerbose(@"creating performance timer");
}

-(void) cancelPerformanceTimer {
    if (self.progressTimer){
        [self.progressTimer invalidate]; self.progressTimer = nil;
        self.startTime = nil;
        self.speed = 0.0;
        DDLogVerbose(@"cancelling performance timer");
    }
}

-(void) updatePerformance: (NSTimer *) timer {
    if (self.startTime == nil) {
        [self cancelPerformanceTimer];
    } else {
        NSTimeInterval timeSoFar = -[self.startTime timeIntervalSinceNow];
        double recentSpeed =  self.show.fileSize * (self.processProgress-self.startProgress)/timeSoFar;
        if (recentSpeed < 0.0) recentSpeed = 0.0;
        if (recentSpeed == 0.0) {
            self.numZeroSpeeds ++;
            if (self.numZeroSpeeds > 3) {
                //not getting much data; hide meter
                if (self.numZeroSpeeds == 4) {
                    self.speed = 0.0;
                    DDLogVerbose(@"Four measurements of zero; hide speed");
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
            self.startTime = [NSDate date];
            self.startProgress = self.processProgress;
        }
    }
}

-(NSString *) timeLeft {
    if (!self.isInProgress) return nil;
    if (self.speed == 0.0) return nil;
    NSTimeInterval actualTimeLeft = self.show.fileSize *(1-self.processProgress) /self.speed;
    if (actualTimeLeft == 0.0) return nil;
    return [NSString stringFromTimeInterval:  actualTimeLeft];
}

-(void)rescheduleShowWithDecrementRetries:(NSNumber *)decrementRetries
{
	if (self.isRescheduled) {
		return;
	}
	self.isRescheduled = YES;
    if (self.isDownloading) {
        DDLogMajor(@"%@ downloaded %ldK of %0.0f KB; %0.1f%%",self,self.totalDataDownloaded/1000, self.show.fileSize/1000, self.processProgress*100);
    }
    [self cancel];
    if (self.encodeFormat.isTestPS) {
        //if it was a test, then we knew it would fail whether it's audio-only OR no video encoder, so everything's good
        if (!self.isDone) {
            //test failed without triggering a audiocheck!
            DDLogReport(@"Failure during PS Test for %@", self.show.showTitle );
            [self setValue:[NSNumber numberWithInt:kMTStatusFailed] forKeyPath:@"downloadStatus"];
            self.processProgress = 1.0;
            [self progressUpdated];
        }
    } else {
        DDLogMajor(@"Stalled at %@, %@ download of %@ with progress at %lf with previous check at %@",self.showStatus,(self.numRetriesRemaining > 0) ? @"restarting":@"canceled",  self.show.showTitle, self.processProgress, self.previousCheck );
        if (self.downloadStatus.intValue == kMTStatusDone) {
            self.baseFileName = nil;
        }
        if (self.downloadStatus.intValue == kMTStatusDeleted) {
            self.numRetriesRemaining = 0;
            self.processProgress = 1.0;
            [self progressUpdated];
            [tiVoManager  notifyWithTitle: @"TiVo deleted program; download cancelled."
                                 subTitle:self.show.showTitle forNotification:kMTGrowlEndDownload];
        } else if (([decrementRetries boolValue] && self.numRetriesRemaining <= 0) ||
            (![decrementRetries boolValue] && self.numStartupRetriesRemaining <=0)) {
            [self setValue:[NSNumber numberWithInt:kMTStatusFailed] forKeyPath:@"downloadStatus"];
            self.processProgress = 1.0;
            [self progressUpdated];
            [tiVoManager  notifyWithTitle: @"TiVo show failed; cancelled."
                                 subTitle:self.show.showTitle forNotification:kMTGrowlEndDownload];
            
        } else {
            if ([decrementRetries boolValue]) {
                self.numRetriesRemaining--;
                [tiVoManager  notifyWithTitle:@"TiVo show failed; retrying..." subTitle:self.show.showTitle forNotification:kMTGrowlCantDownload];
                DDLogDetail(@"Decrementing retries to %ld",(long)self.numRetriesRemaining);
            } else {
                self.numStartupRetriesRemaining--;
                DDLogDetail(@"Decrementing startup retries to %@",@(self.numStartupRetriesRemaining));
            }
            [self setValue:[NSNumber numberWithInt:kMTStatusNew] forKeyPath:@"downloadStatus"];
        }
    }
    [NSNotificationCenter postNotificationNameOnMainThread:kMTNotificationDownloadQueueUpdated object:self.show.tiVo afterDelay:4.0];

}

#pragma mark - Queue encoding/decoding methods for persistent queue, copy/paste, and drag/drop

- (void) encodeWithCoder:(NSCoder *)encoder {
	//necessary for cut/paste drag/drop. Not used for persistent queue, as we like having english readable pref lists
	//keep parallel with queueRecord
	DDLogVerbose(@"encoding %@",self);
	[self.show encodeWithCoder:encoder];
	[encoder encodeObject:[NSNumber numberWithBool:self.addToiTunesWhenEncoded] forKey: kMTSubscribediTunes];
	[encoder encodeObject:@(self.skipCommercials) forKey: kMTSubscribedSkipCommercials];
	[encoder encodeObject:@(self.markCommercials) forKey: kMTSubscribedMarkCommercials];
	[encoder encodeObject:self.encodeFormat.name forKey:kMTQueueFormat];
	[encoder encodeObject:self.downloadStatus forKey: kMTQueueStatus];
	[encoder encodeObject: self.downloadDirectory forKey: kMTQueueDirectory];
	[encoder encodeObject: self.encodeFilePath forKey: kMTQueueFinalFile] ;
	[encoder encodeObject: self.genTextMetaData forKey: kMTQueueGenTextMetaData];
#ifndef deleteXML
	[encoder encodeObject: self.genXMLMetaData forKey:	kMTQueueGenXMLMetaData];
	[encoder encodeObject: self.includeAPMMetaData forKey:	kMTQueueIncludeAPMMetaData];
#endif
	[encoder encodeObject: self.exportSubtitles forKey:	kMTQueueExportSubtitles];
}

- (NSDictionary *) queueRecord {
	//used for persistent queue, as we like having english-readable pref lists
	//keep parallel with encodeWithCoder
	//need to watch out for a nil object ending the dictionary too soon.

	NSMutableDictionary *result = [NSMutableDictionary dictionaryWithObjectsAndKeys:
								   @(self.show.showID), kMTQueueID,
								   @(self.addToiTunesWhenEncoded), kMTSubscribediTunes,
								   @(self.skipCommercials), kMTSubscribedSkipCommercials,
								   @(self.markCommercials), kMTSubscribedMarkCommercials,
								   self.show.showTitle, kMTQueueTitle,
								   self.show.tiVoName, kMTQueueTivo,
								   nil];
	if (self.encodeFormat.name) [result setValue:self.encodeFormat.name forKey:kMTQueueFormat];
	if (self.downloadStatus)    [result setValue:self.downloadStatus forKey:kMTQueueStatus];
	if (self.downloadDirectory) [result setValue:self.downloadDirectory forKey:kMTQueueDirectory];
	if (self.encodeFilePath)    [result setValue:self.encodeFilePath forKey: kMTQueueFinalFile];
	if (self.genTextMetaData)   [result setValue:self.genTextMetaData forKey: kMTQueueGenTextMetaData];
#ifndef deleteXML
	if (self.genXMLMetaData) [result setValue:self.genXMLMetaData forKey: kMTQueueGenXMLMetaData];
	if (self.includeAPMMetaData) [result setValue:self.includeAPMMetaData forKey: kMTQueueIncludeAPMMetaData];
#endif
	if (self.exportSubtitles) [result setValue:self.exportSubtitles forKey: kMTQueueExportSubtitles];
	
	DDLogVerbose(@"queueRecord for %@ is %@",self,result);
	return [NSDictionary dictionaryWithDictionary: result];
}

-(BOOL) isSameAs:(NSDictionary *) queueEntry {
	NSInteger queueID = [queueEntry[kMTQueueID] integerValue];
	BOOL result = (queueID == self.show.showID) && ([self.show.tiVoName compare:queueEntry[kMTQueueTivo]] == NSOrderedSame);
	if (result && [self.show.showTitle compare:queueEntry[kMTQueueTitle]] != NSOrderedSame) {
		DDLogReport(@"Very odd, but reloading anyways: same ID: %ld same TiVo:%@ but different titles: <<%@>> vs <<%@>>",queueID, queueEntry[kMTQueueTivo], self.show.showTitle, queueEntry[kMTQueueTitle] );
	}
	return result;
	
}

+(MTDownload *) downloadFromQueue:queueEntry {

	MTTiVoShow *fakeShow = [[MTTiVoShow alloc] init];
	fakeShow.showID   = [(NSNumber *)queueEntry[kMTQueueID] intValue];
	[fakeShow setShowSeriesAndEpisodeFrom: queueEntry[kMTQueueTitle]];
	fakeShow.tempTiVoName = queueEntry[kMTQueueTivo] ;

    MTFormat * format = [tiVoManager findFormat: queueEntry[kMTQueueFormat]]; //bug here: will not be able to restore a no-longer existent format, so will substitue with first one available, which is wrong for completed/failed entries

    MTDownload *download = [MTDownload downloadForShow:fakeShow withFormat:format intoDirectory:queueEntry[kMTQueueDirectory]];
    if (format.isTestPS) {
        download.numRetriesRemaining = 0;
        download.numStartupRetriesRemaining = 0;
    } else {
        download.numRetriesRemaining = (int) [[NSUserDefaults standardUserDefaults] integerForKey:kMTNumDownloadRetries];
        download.numStartupRetriesRemaining = kMTMaxDownloadStartupRetries;
    }
	download.addToiTunesWhenEncoded = [queueEntry[kMTSubscribediTunes ]  boolValue];
	download.skipCommercials = [queueEntry[kMTSubscribedSkipCommercials ]  boolValue];
	download.markCommercials = [queueEntry[kMTSubscribedMarkCommercials ]  boolValue];
	download.downloadStatus = queueEntry[kMTQueueStatus];
	if (download.isInProgress) download.downloadStatus = @kMTStatusNew;		//until we can launch an in-progress item
	
	download.encodeFilePath = queueEntry[kMTQueueFinalFile];
	download.show.protectedShow = @YES; //until we matchup with show or not.
	download.genTextMetaData = queueEntry[kMTQueueGenTextMetaData]; if (!download.genTextMetaData) download.genTextMetaData= @(NO);
#ifndef deleteXML
	download.genXMLMetaData = queueEntry[kMTQueueGenXMLMetaData]; if (!download.genXMLMetaData) download.genXMLMetaData= @(NO);
	download.includeAPMMetaData = queueEntry[kMTQueueIncludeAPMMetaData]; if (!download.includeAPMMetaData) download.includeAPMMetaData= @(NO);
#endif
	download.exportSubtitles = queueEntry[kMTQueueExportSubtitles]; if (!download.exportSubtitles) download.exportSubtitles= @(NO);
	DDLogDetail(@"restored %@ with %@; inProgress",download, queueEntry);
    return download;
}

- (id)initWithCoder:(NSCoder *)decoder {
	//keep parallel with updateFromDecodedShow
	if ((self = [self init])) {
		//NSString *title = [decoder decodeObjectForKey:kTitleKey];
		//float rating = [decoder decodeFloatForKey:kRatingKey];
		self.show = [[MTTiVoShow alloc] initWithCoder:decoder ];
		self.downloadDirectory = [decoder decodeObjectForKey: kMTQueueDirectory];
		self.addToiTunesWhenEncoded= [[decoder decodeObjectForKey: kMTSubscribediTunes] boolValue];
//		self.simultaneousEncode	 =   [[decoder decodeObjectForKey: kMTSubscribedSimulEncode] boolValue];
		self.skipCommercials   =     [[decoder decodeObjectForKey: kMTSubscribedSkipCommercials] boolValue];
		self.markCommercials   =     [[decoder decodeObjectForKey: kMTSubscribedMarkCommercials] boolValue];
		NSString * encodeName	 = [decoder decodeObjectForKey:kMTQueueFormat];
		self.encodeFormat =	[tiVoManager findFormat: encodeName]; //minor bug here: will not be able to restore a no-longer existent format, so will substitue with first one available, which is then wrong for completed/failed entries
		self.downloadStatus		 = [decoder decodeObjectForKey: kMTQueueStatus];
		self.encodeFilePath = [decoder decodeObjectForKey:kMTQueueFinalFile];
		self.genTextMetaData = [decoder decodeObjectForKey:kMTQueueGenTextMetaData]; if (!self.genTextMetaData) self.genTextMetaData= @(NO);
#ifndef deleteXML
		self.genXMLMetaData = [decoder decodeObjectForKey:kMTQueueGenXMLMetaData]; if (!self.genXMLMetaData) self.genXMLMetaData= @(NO);
		self.includeAPMMetaData = [decoder decodeObjectForKey:kMTQueueIncludeAPMMetaData]; if (!self.includeAPMMetaData) self.includeAPMMetaData= @(NO);
#endif
		self.exportSubtitles = [decoder decodeObjectForKey:kMTQueueExportSubtitles]; if (!self.exportSubtitles) self.exportSubtitles= @(NO);
	}
	DDLogDetail(@"initWithCoder for %@",self);
	return self;
}

-(void) convertProxyToRealForShow:(MTTiVoShow *) show {
    self.show = show;
    self.show.isQueued = YES;
}

-(BOOL) isEqual:(id)object {
	if (object == self) return YES;
    if (!object || ![object isKindOfClass:MTDownload.class]) {
		return NO;
	}
	MTDownload * dl = (MTDownload *) object;
	return ([self.show isEqual:dl.show] &&
			[self.encodeFormat isEqual: dl.encodeFormat] &&
			(self.encodeFilePath == dl.encodeFilePath || [self.encodeFilePath isEqualToString:dl.encodeFilePath]) &&
			(self.downloadDirectory == dl.downloadDirectory || [self.downloadDirectory isEqualToString:dl.downloadDirectory]));
	
}

-(NSUInteger) hash {
    return [self.show hash] ^
    [self.encodeFormat hash] ^
    [self.encodeFilePath hash] ^
    [self.downloadDirectory hash];
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


#pragma mark - Download/conversion file Methods

//Method called at the beginning of the download to configure all required files and file handles

-(void)deallocDownloadHandling
{
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

-(void)cleanupFiles
{
	BOOL deleteFiles = ![[NSUserDefaults standardUserDefaults] boolForKey:kMTSaveTmpFiles];
    NSFileManager *fm = [NSFileManager defaultManager];
    DDLogDetail(@"%@ cleaningup files",self.show.showTitle);
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
	if (deleteFiles && self.baseFileName) {
		NSArray *tmpFiles = [fm contentsOfDirectoryAtPath:tiVoManager.tmpFilesDirectory error:nil];
		[fm changeCurrentDirectoryPath:tiVoManager.tmpFilesDirectory];
		for(NSString *file in tmpFiles){
			NSRange tmpRange = [file rangeOfString:self.baseFileName];
			if(tmpRange.location != NSNotFound) {
				DDLogVerbose(@"Deleting tmp file %@", file);
                NSError * error = nil;
                if ( ![fm removeItemAtPath:file error:&error]) {
                    DDLogMajor(@"Could not delete tmp file: %@/%@ because %@", tiVoManager.tmpFilesDirectory, file, error.localizedDescription ?:@"No reason found");
                }
			}
		}
	}
}

-(NSString *) directoryForShowInDirectory:(NSString*) tryDirectory  {
	//Check that download directory (including show directory) exists.  If create it.  If unsuccessful return nil
	tryDirectory = [tryDirectory stringByAppendingPathComponent:self.keywordPathPart];
	if ([[NSUserDefaults standardUserDefaults] boolForKey:kMTMakeSubDirs]) {
		NSString *whichFolder = ([self.show isMovie])  ? @"Movies"  : self.show.seriesTitle;
		if ( ! [tryDirectory.lastPathComponent isEqualToString:whichFolder]){
			tryDirectory = [tryDirectory stringByAppendingPathComponent:whichFolder];
			DDLogVerbose(@"Using sub folder %@",tryDirectory);
		}
	}
	if (![[NSFileManager defaultManager] fileExistsAtPath: tryDirectory]) { // try to create it
		DDLogDetail(@"Creating folder %@",tryDirectory);
		if (![[NSFileManager defaultManager] createDirectoryAtPath:tryDirectory withIntermediateDirectories:YES attributes:nil error:nil]) {
			DDLogDetail(@"Couldn't create folder %@",tryDirectory);
			return nil;
		}
	}
	return tryDirectory;
}
#pragma mark - Keyword Processing:
/*
 From KMTTG:
 [title] = The Big Bang Theory – The Loobenfeld Decay
 [mainTitle] = The Big Bang Theory
 [episodeTitle] = The Loobenfeld Decay
 [channelNum] = 702
 [channel] = KCBSDT
 [min] = 00
 [hour] = 20
 [wday] = Mon
 [mday] = 24
 [month] = Mar
 [monthNum] = 03
 [year] = 2008
 [originalAirDate] = 2007-11-20
 [EpisodeNumber] = 302
 [tivoName]
 [/]
 
 
 By request some more advanced keyword processing was introduced to allow for conditional text.
 
 You can define multiple space-separated fields within square brackets.
 Fields surrounded by quotes are treated as literal text.
 A single field with no quotes should be supplied which represents a conditional keyword
 If that keyword is available for the show in question then the keyword value along with any literal text surrounding it will be included in file name.
 If the keyword evaluates to null then the entire advanced keyword becomes null.
 For example:
 [mainTitle]["_Ep#" EpisodeNumber]_[wday]_[month]_[mday]
 The advanced keyword is highlighted in bold and signifies only include “_Ep#xxx” if EpisodeNumber exists for the show in question. “_Ep#” is literal string to which the evaluated contents of EpisodeNumber keyword are appended. If EpisodeNumber does not exist then the whole advanced keyword evaluates to empty string.
 
 Added to KMTTG: 
startTime
 seriesEpNumber
 TivoName
 TVDBSeriesID
 plexID
	OR (|) option, uses second keyword if first is empty
	Embedded optional values [ this option [with this embedded option] ]


 */

//test routines moved to Advanced Preferences

- (NSString *) replacementForKeyword:(NSString *) key usingDictionary: (NSDictionary*) keys {
	NSMutableString * outStr = [NSMutableString string];

	NSScanner *scanner = [NSScanner scannerWithString:key];
	[scanner setCharactersToBeSkipped:nil];
    NSCharacterSet * whitespaceSet = [NSCharacterSet whitespaceCharacterSet];
    NSCharacterSet * brackets = [NSCharacterSet characterSetWithCharactersInString:@"[]"];
    BOOL skipOne = NO;  //have we found a good alternative, so skip the rest?
    NSString * foundKey;

	while (![scanner isAtEnd]) {
		[scanner scanCharactersFromSet:whitespaceSet intoString:nil];
		//get any literal characters
		if ([scanner scanString:@"\"" intoString:nil]) {
			NSString * tempString;
			if ([scanner scanUpToString: @"\"" intoString:&tempString]) {
                if (skipOne) {
                    skipOne = NO;
                } else {
                    [outStr appendString:tempString];
                }
			} //else no chars scanned before quote (or end of line), so ignore this quote
			[scanner scanString:@"\"" intoString:nil];
			[scanner scanCharactersFromSet:whitespaceSet intoString:nil];
		} else if ([scanner scanString:@"[" intoString:nil]) {
            //get any recursive fields
            NSString * tempString;
            int numBrackets = 1;
            NSMutableString *bracketedString = [NSMutableString string];
            tempString = @"";
            while (numBrackets > 0) {
                [bracketedString appendString:tempString];  //get recursive [ if any
                if ([scanner scanUpToCharactersFromSet:brackets intoString:&tempString]) {
                    [bracketedString appendString:tempString];
                }
                if ([scanner scanString:@"[" intoString:&tempString]) {
                    numBrackets++;
                } else if ([scanner scanString:@"]" intoString:&tempString]) {
                    numBrackets--;
                }
            }
            [scanner scanCharactersFromSet:whitespaceSet intoString:nil];
            if (skipOne) {
                skipOne = NO;
            } else {
                [outStr appendString: [self replacementForKeyword:bracketedString usingDictionary:keys]];
            }
       } else if ([scanner scanString:@"|" intoString:nil]) {
            //got an alternative, but previous one must have been good (or we'd have eaten this)
            skipOne = YES;
        } else  {
            //not space, quote, alternative or recursive, so get keyword and replace with value from Dictionary
            if ([scanner scanUpToString:@" " intoString:&foundKey]) {
                if (skipOne) {
                    skipOne = NO;
                } else {
                    foundKey = foundKey.lowercaseString;
                    if ([keys[foundKey] length] == 0) {
                        DDLogDetail(@"No filename key: %@",foundKey);
                        //found invalid or empty key so entire conditional fails and should be empty; ignore everything else, unless there's an OR (vertical bar)
                        [scanner scanCharactersFromSet:whitespaceSet intoString:nil];
                        if ([scanner scanString:@"|" intoString:nil]) {
                            //ah, we've got an alternative, so let's keep going
                        } else {
                            return @"";
                        }
                    } else {
                        DDLogVerbose(@"Swapping key %@ with %@",foundKey, keys[foundKey]);
                        [outStr appendString:keys[foundKey]];
                    }
                }
            }
		} //else no chars scanned before ] (or end of line) so ignore this
	}
	return [NSString stringWithString:outStr];
}

NSString * twoChar(long n, BOOL allowZero) {
	if (!allowZero && n == 0) return @"";
	return [NSString stringWithFormat:@"%02ld", n];
}
NSString * fourChar(long n, BOOL allowZero) {
	if (!allowZero && n == 0) return @"";
	return [NSString stringWithFormat:@"%04ld", n];
}

#define NULLT(x) (x ?: @"")

 -(NSString *) swapKeywordsInString: (NSString *) str {
     NSDateComponents *components;
     if (self.show.showDate) {
         components = [[NSCalendar currentCalendar]
									components:NSCalendarUnitDay | NSCalendarUnitMonth | NSCalendarUnitYear |NSCalendarUnitWeekday  |
									NSCalendarUnitMinute | NSCalendarUnitHour
											fromDate:self.show.showDate];
     } else {
         components = [[NSDateComponents alloc] init];
     }
	 NSString * originalAirDate =self.show.originalAirDateNoTime;
	 if (!originalAirDate && [components year] > 0) {
		 originalAirDate = [NSString stringWithFormat:@"%@-%@-%@",
											fourChar([components year], NO),
											twoChar([components month], YES),
											twoChar([components day], YES)];
	 }
	 NSString * monthName = ([components month]> 0 && [components month] != NSUndefinedDateComponent) ?
								[[[[NSDateFormatter alloc] init] shortMonthSymbols]
													   objectAtIndex:[components month]-1] :
								@"";
	 
     NSString *TVDBseriesID = nil;
     @synchronized (tiVoManager.tvdbSeriesIdMapping) {
         TVDBseriesID = [tiVoManager.tvdbSeriesIdMapping objectForKey:self.show.seriesTitle]; // see if we've already done this
     }
	 if (!TVDBseriesID) {
         @synchronized (tiVoManager.tvdbCache) {
             NSDictionary *TVDBepisodeEntry = [tiVoManager.tvdbCache objectForKey:self.show.episodeID];
		 //could provide these ,too?
		 // NSNumber * TVDBepisodeNum = [TVDBepisodeEntry objectForKey:@"episode"];
		 //NSNumber * TVDBseasonNum = [TVDBepisodeEntry objectForKey:@"season"];
             TVDBseriesID = [TVDBepisodeEntry objectForKey:@"series"];
         };
	 }
     NSString * guests = [[self.show.guestStars.string componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]] componentsJoinedByString:@", "];
     NSString * extraEpisode = @"";
     if (self.show.episode && self.show.season &&   //if we have an SxxExx AND either a 2 hr show OR a semicolon in episode title, then it might be a double episode
         ((self.show.showLength > 115*60 && self.show.showLength < 125*60) ||
          ([self.show.episodeTitle contains:@";"]))) {
         extraEpisode = [NSString stringWithFormat:@"E%02d",self.show.episode+1];
     }
	 NSDictionary * keywords = @{  //lowercase so we can just lowercase keyword when found
		 @"/":				@"|||",						//allows [/] for subdirs
		 @"title":			NULLT(self.show.showTitle) ,
		 @"maintitle":		NULLT(self.show.seriesTitle),
		 @"episodetitle":	NULLT(self.show.episodeTitle),
		 @"channelnum":		NULLT(self.show.channelString),
		 @"channel":		NULLT(self.show.stationCallsign),
		 @"starttime":		NULLT(self.show.showTime),
		 @"min":			twoChar([components minute], YES),
		 @"hour":			twoChar([components hour], YES),
		 @"wday":			twoChar([components weekday], NO),
		 @"mday":			twoChar([components day], NO),
		 @"month":			monthName,
		 @"monthnum":		twoChar([components month], NO),
		 @"year": 			self.show.isMovie ? @"" : fourChar([components year], NO),
 		 @"originalairdate": originalAirDate,
		 @"episode":		twoChar(self.show.episode, NO),
         @"extraepisode":  NULLT(extraEpisode),
         @"season":			twoChar(self.show.season, NO),
		 @"episodenumber":	NULLT(self.show.episodeNumber),
         @"StartTime":     NULLT(self.show.startTime),
		 @"seriesepnumber": NULLT(self.show.seasonEpisode),
         @"guests":        NULLT(guests),
		 @"tivoname":		NULLT(self.show.tiVoName),
		 @"movieyear":		NULLT(self.show.movieYear),
		 @"tvdbseriesid":	NULLT(TVDBseriesID),
//         @"plexid":        [self ifString: self.show.seasonEpisode
//                                elseString: originalAirDate],
//         @"plexseason":    [self ifString: twoChar(self.show.season, NO)
//                                 elseString: fourChar([components year], NO) ]
		 };
	 NSMutableString * outStr = [NSMutableString string];
	 
	 NSScanner *scanner = [NSScanner scannerWithString:str];
	 [scanner setCharactersToBeSkipped:nil];
     NSCharacterSet * brackets = [NSCharacterSet characterSetWithCharactersInString:@"[]"];
	 while (![scanner isAtEnd]) {
		 NSString * tempString;
		 //get any literal characters
		 if ([scanner scanUpToString: @"[" intoString:&tempString]) {
			 [outStr appendString:tempString];
		 }
		 //get keyword and replace with values
		 if ([scanner scanString:@"[" intoString:nil]) {

             int numBrackets = 1;
             NSMutableString *bracketedString = [NSMutableString string];
             tempString = @"";
             while (numBrackets > 0) {
                 [bracketedString appendString:tempString];  //get recursive [ if any
                 if ([scanner scanUpToCharactersFromSet:brackets intoString:&tempString]) {
                     [bracketedString appendString:tempString];
                 }
                if ([scanner scanString:@"[" intoString:&tempString]) {
                     numBrackets++;
                } else if ([scanner scanString:@"]" intoString:&tempString]) {
                     numBrackets--;
                 }
            }
			 [outStr appendString: [self replacementForKeyword:bracketedString usingDictionary:keywords]];
		 }
	 }
     NSString * finalStr = [outStr stringByReplacingOccurrencesOfString:@"/" withString:@"-"]; //remove accidental directory markers
	 finalStr = [finalStr stringByReplacingOccurrencesOfString:@"|||" withString:@"/"];  ///insert intentional ones
	 return finalStr;
 }

//#define Null(x) x ?  x : nullString
//
#pragma mark - Configure files
-(void)configureBaseFileNameAndDirectory {
	if (!self.baseFileName) {
		// generate only once
		NSString * baseTitle  = [self.show.showTitle stringByReplacingOccurrencesOfString:@"/" withString:@"-"];
		NSString * filenamePattern = [[NSUserDefaults standardUserDefaults] objectForKey:kMTFileNameFormat];
		if (filenamePattern.length >0) {
			//we have a pattern, so generate a name that way
			NSString *keyBaseTitle = [self swapKeywordsInString:filenamePattern];
			DDLogDetail(@"With file pattern %@ for show %@, got %@", filenamePattern, self.show, keyBaseTitle);
			if (keyBaseTitle.length >0) {
				baseTitle = [keyBaseTitle lastPathComponent];
				//note that self.downloadDir depends on keywordPathPart being set
				self.keywordPathPart = [keyBaseTitle stringByDeletingLastPathComponent];
			}
		}
		if (baseTitle.length > 245) baseTitle = [baseTitle substringToIndex:245];
		baseTitle = [baseTitle stringByReplacingOccurrencesOfString:@":" withString:@"-"];
		if (LOG_DETAIL  && [baseTitle compare: self.show.showTitle ]  != NSOrderedSame) {
			DDLogDetail(@"changed filename %@ to %@",self.show.showTitle, baseTitle);
		}
		self.baseFileName = [self createUniqueBaseFileName:baseTitle inDownloadDir:self.downloadDir];
	}
}
#undef Null

-(void) markCompleteCTiVoFile:(NSString *) path {
    if (path ) {
        NSData *tiVoID = [self.show.idString dataUsingEncoding:NSUTF8StringEncoding];
        setxattr([path cStringUsingEncoding:NSASCIIStringEncoding], [kMTXATTRFileComplete UTF8String], [tiVoID bytes], tiVoID.length, 0, 0);  //This is for a checkpoint and tell us the file is complete with show ID
    }
}


-(BOOL) isCompleteCTiVoFile: (NSString *) path forFileType: (NSString *) fileType {
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:path]) {
        NSData *buffer = [NSData dataWithData:[[NSMutableData alloc] initWithLength:256]];
		ssize_t len = getxattr([path cStringUsingEncoding:NSASCIIStringEncoding], [kMTXATTRFileComplete UTF8String], (void *)[buffer bytes], 256, 0, 0);
        if (len >=0) {
            NSString *tiVoID = [[NSString alloc] initWithData:[NSData dataWithBytes:[buffer bytes] length:len] encoding:NSUTF8StringEncoding];
            if ([tiVoID compare:self.show.idString] == NSOrderedSame) {
                DDLogMajor(@"Found Complete %@ File at %@", fileType, path);
                return YES;
            }
        }
    }
    return NO;
}

-(NSString *)createUniqueBaseFileName:(NSString *)baseName inDownloadDir:(NSString *)downloadDir
{
	NSFileManager *fm = [NSFileManager defaultManager];
    NSString *trialEncodeFilePath = [NSString stringWithFormat:@"%@/%@%@",downloadDir,baseName,self.encodeFormat.filenameExtension];
	NSString *trialLockFilePath = [NSString stringWithFormat:@"%@/%@.lck" ,tiVoManager.tmpFilesDirectory,baseName];
	self.tivoFilePath = [NSString stringWithFormat:@"%@/buffer%@.tivo",tiVoManager.tmpFilesDirectory,baseName];
	self.mpgFilePath = [NSString stringWithFormat:@"%@/buffer%@.mpg",tiVoManager.tmpFilesDirectory,baseName];
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
		return [self createUniqueBaseFileName:nextBase inDownloadDir:downloadDir];
		
	} else {
		DDLogDetail(@"Using baseFileName %@",baseName);
		self.nameLockFilePath = trialLockFilePath;
		[[NSFileManager defaultManager] createFileAtPath:self.nameLockFilePath contents:[NSData data] attributes:nil];  //Creating the lock file
		return baseName;
	}
	
}

-(NSString *)downloadDir  //not valid until after configureBaseFileNameAndDirectory has been called
						  //layered on top of downloadDirectory to add subdirs and check for existence/create if necessary
						  //maybe should change to update downloadDirectory at configureFiles time to avoid reassembling subdirs?
{
		NSString *ddir = [self directoryForShowInDirectory:[self downloadDirectory]];
		
		//go to current directory if one at show scheduling time failed
		if (!ddir) {
			ddir = [self directoryForShowInDirectory:[tiVoManager downloadDirectory]];
		}
		
		//finally, go to default if not successful
		if (!ddir) {
			ddir = [self directoryForShowInDirectory:[tiVoManager defaultDownloadDirectory]];
		}
    return ddir;
}

-(void)configureFiles
{
    DDLogDetail(@"configuring files for %@",self);
	//Release all previous attached pointers
    [self deallocDownloadHandling];
    NSFileManager *fm = [NSFileManager defaultManager];
	[self configureBaseFileNameAndDirectory];
    if (!self.downloadingShowFromTiVoFile && !self.downloadingShowFromMPGFile) {  //We need to download from the TiVo
        if ([[NSUserDefaults standardUserDefaults] boolForKey:kMTUseMemoryBufferForDownload]) {
            self.bufferFilePath = [NSString stringWithFormat:@"%@/buffer%@.bin",tiVoManager.tmpFilesDirectory,self.baseFileName];
            DDLogVerbose(@"downloading to memory; buffer: %@", self.bufferFilePath);
            self.urlBuffer = [NSMutableData new];
            self.urlReadPointer = 0;
            self.bufferFileReadHandle = nil;
        } else {
            self.bufferFilePath = [NSString stringWithFormat:@"%@/buffer%@.tivo",tiVoManager.tmpFilesDirectory,self.baseFileName];
            DDLogVerbose(@"downloading to file: %@", self.bufferFilePath);
            [fm createFileAtPath:self.bufferFilePath contents:[NSData data] attributes:nil];
            self.bufferFileWriteHandle = [NSFileHandle fileHandleForWritingAtPath:self.bufferFilePath];
           self. bufferFileReadHandle = [NSFileHandle fileHandleForReadingAtPath:self.bufferFilePath];
            self.urlBuffer = nil;
        }
    }
    if (!self.downloadingShowFromMPGFile) {
        self.decryptedFilePath = [NSString stringWithFormat:@"%@/buffer%@.mpg",tiVoManager.tmpFilesDirectory,self.baseFileName];
        DDLogVerbose(@"setting decrypt path: %@", self.decryptedFilePath);
        [[NSFileManager defaultManager] createFileAtPath:self.decryptedFilePath contents:[NSData data] attributes:nil];
    }
	self.encodeFilePath = [NSString stringWithFormat:@"%@/%@%@",self.downloadDir,self.baseFileName,self.encodeFormat.filenameExtension];
	DDLogVerbose(@"setting encodepath: %@", self.encodeFilePath);
    self.captionFilePath = [NSString stringWithFormat:@"%@/%@.srt",self.downloadDir ,self.baseFileName];
    DDLogVerbose(@"setting self.captionFilePath: %@", self.captionFilePath);
    
    self.commercialFilePath = [NSString stringWithFormat:@"%@/buffer%@.edl" ,tiVoManager.tmpFilesDirectory, self.baseFileName];  //0.92 version
    DDLogVerbose(@"setting self.commercialFilePath: %@", self.commercialFilePath);
    
	if (!self.encodeFormat.isTestPS &&
        [[NSUserDefaults standardUserDefaults] boolForKey:kMTGetEpisodeArt]) {
       NSString * filename = [tiVoManager.tmpFilesDirectory stringByAppendingPathComponent:self.baseFileName];
        [self.show retrieveArtworkIntoFile:filename];
 	}
}

-(NSString *) encoderPath {
	NSString *encoderLaunchPath = [self.encodeFormat pathForExecutable];
    if (!encoderLaunchPath) {
        DDLogReport(@"Encoding of %@ failed for %@ format, encoder %@ not found",self.show.showTitle,self.encodeFormat.name,self.encodeFormat.encoderUsed);
        [self setValue:[NSNumber numberWithInt:kMTStatusFailed] forKeyPath:@"downloadStatus"];
        self.processProgress = 1.0;
        [NSNotificationCenter  postNotificationNameOnMainThread:kMTNotificationProgressUpdated object:self];
        return nil;
    } else {
        DDLogVerbose(@"using encoder: %@", encoderLaunchPath);
		return encoderLaunchPath;
	}
}

#pragma mark - Download decrypt and encode Methods


-(NSMutableArray *)getArguments:(NSString *)argString
{
	NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"([^\\s\"\']+)|\"(.*?)\"|'(.*?)'" options:NSRegularExpressionCaseInsensitive error:nil];
	NSArray *matches = [regex matchesInString:argString options:NSMatchingWithoutAnchoringBounds range:NSMakeRange(0, argString.length)];
	NSMutableArray *arguments = [NSMutableArray array];
	for (NSTextCheckingResult *tr in matches) {
		NSUInteger j;
		for ( j=1; j<tr.numberOfRanges; j++) {
			if ([tr rangeAtIndex:j].location != NSNotFound) {
				break;
			}
		}
		[arguments addObject:[argString substringWithRange:[tr rangeAtIndex:j]]];
	}
	DDLogVerbose(@"arguments: %@", [arguments maskMediaKeys]);
	return arguments;
	
}


-(NSMutableArray *)encodingArgumentsWithInputFile:(NSString *)inputFilePath outputFile:(NSString *)outputFilePath
{
	NSMutableArray *arguments = [NSMutableArray array];
    MTFormat * f = self.encodeFormat;
    if (f.outputFileFlag.length) {
        if (f.encoderEarlyVideoOptions.length) [arguments addObjectsFromArray:[self getArguments:f.encoderEarlyVideoOptions]];
        if (f.encoderEarlyAudioOptions.length) [arguments addObjectsFromArray:[self getArguments:f.encoderEarlyAudioOptions]];
        if (f.encoderEarlyOtherOptions.length) [arguments addObjectsFromArray:[self getArguments:f.encoderEarlyOtherOptions]];
        [arguments addObject:f.outputFileFlag];
        [arguments addObject:outputFilePath];
		if ([f.comSkip boolValue] && self.skipCommercials && f.edlFlag.length) {
			[arguments addObject:f.edlFlag];
			[arguments addObject:self.commercialFilePath];
		}
        if (f.inputFileFlag.length) {
            [arguments addObject:f.inputFileFlag];
			[arguments addObject:inputFilePath];
			if (f.encoderLateVideoOptions.length) [arguments addObjectsFromArray:[self getArguments:f.encoderLateVideoOptions]];
			if (f.encoderLateAudioOptions.length) [arguments addObjectsFromArray:[self getArguments:f.encoderLateAudioOptions]];
			if (f.encoderLateOtherOptions.length) [arguments addObjectsFromArray:[self getArguments:f.encoderLateOtherOptions]];
        } else {
			[arguments addObject:inputFilePath];
		}
    } else {
        if (f.encoderEarlyVideoOptions.length) [arguments addObjectsFromArray:[self getArguments:f.encoderEarlyVideoOptions]];
        if (f.encoderEarlyAudioOptions.length) [arguments addObjectsFromArray:[self getArguments:f.encoderEarlyAudioOptions]];
        if (f.encoderEarlyOtherOptions.length) [arguments addObjectsFromArray:[self getArguments:f.encoderEarlyOtherOptions]];
		if ([f.comSkip boolValue] && _skipCommercials && f.edlFlag.length) {
			[arguments addObject:f.edlFlag];
			[arguments addObject:self.commercialFilePath];
		}
        if (f.inputFileFlag.length) {
            [arguments addObject:f.inputFileFlag];
        }
        [arguments addObject:inputFilePath];
        if (f.encoderLateVideoOptions.length) [arguments addObjectsFromArray:[self getArguments:f.encoderLateVideoOptions]];
        if (f.encoderLateAudioOptions.length) [arguments addObjectsFromArray:[self getArguments:f.encoderLateAudioOptions]];
        if (f.encoderLateOtherOptions.length) [arguments addObjectsFromArray:[self getArguments:f.encoderLateOtherOptions]];
		[arguments addObject:outputFilePath];
    }
	return arguments;
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
        catTask.completionHandler = ^BOOL(){
            if (! [[NSFileManager defaultManager] fileExistsAtPath:outputFile] ) {
                DDLogReport(@"Warning: %@: File %@ not found after completion",self, outputFile );
            }
            return YES;
        };
    }
    DDLogVerbose(@"Cat task: From %@ to %@ = %@",inputFile?:@"stdIn", outputFile?:@"stdOut", catTask);
    return catTask;
}
-(void) checkDecodeLog {
    NSString *log = [NSString stringWithContentsOfFile:_decryptTask.errorFilePath encoding:NSUTF8StringEncoding error:nil];
    if (log && log.length > 25 ) {
        NSRange badMAKRange = [log rangeOfString:@"Invalid MAK"];
        if (badMAKRange.location != NSNotFound) {
            DDLogMajor(@"tivodecode failed with 'Invalid MAK' error message");
            DDLogVerbose(@"log file: %@",[log maskMediaKeys]);
            [tiVoManager  notifyWithTitle:@"Decoding Failed" subTitle:[NSString stringWithFormat:@"Decoding of tivo file failed for %@",self.show.showTitle] isSticky:YES forNotification:kMTGrowlTivodecodeFailed];
        }
    }
}

-(MTTask *)decryptTask  //Decrypting is done in parallel with download so no progress indicators are needed.
{
    if (_decryptTask) {
        return _decryptTask;
    }
    MTTask *decryptTask = [MTTask taskWithName:@"decrypt" download:self];
    NSString * decoder = [[NSUserDefaults standardUserDefaults] objectForKey:kMTDecodeBinary];
    NSString * decryptPath = nil;
    NSString * libreJar = nil;
    if ([decoder isEqualToString:@"TivoLibre"]) {
        // NSFileManager * fm = [NSFileManager defaultManager];
        decryptPath = @"/usr/bin/java";
        libreJar = [[NSBundle mainBundle] pathForAuxiliaryExecutable: @"tivo-libre.jar"];
    } else {
        decryptPath = [[NSBundle mainBundle] pathForAuxiliaryExecutable: decoder];
    }
    if (!decryptPath) { //should never happen, but did once.
        [tiVoManager  notifyWithTitle:[NSString stringWithFormat:@"Can't Find %@", decoder] subTitle:[NSString stringWithFormat:@"Please go to cTiVo site for help! %@",self.show.showTitle] isSticky:YES forNotification:kMTGrowlTivodecodeFailed];
        DDLogReport(@"Fatal Error: decoder %@ not found???", decoder);
        return nil;
    }
    [decryptTask setLaunchPath:decryptPath] ;
    decryptTask.successfulExitCodes = @[@0,@6];

    decryptTask.completionHandler = ^BOOL(){
        if (!self.shouldSimulEncode) {
            [self setValue:[NSNumber numberWithInt:kMTStatusDownloaded] forKeyPath:@"downloadStatus"];
            [NSNotificationCenter  postNotificationNameOnMainThread:kMTNotificationDecryptDidFinish object:nil];
            if (self.decryptedFilePath) {
                [self markCompleteCTiVoFile: self.decryptedFilePath ];
            }
        }

        [self checkDecodeLog];
		return YES;
    };
	
	decryptTask.terminationHandler = ^(){
        [self checkDecodeLog];
	};
    
    if (self.downloadingShowFromTiVoFile) {
        [decryptTask setStandardError:decryptTask.logFileWriteHandle];
        decryptTask.progressCalc = ^(NSString *data){
            NSArray *lines = [data componentsSeparatedByString:@"\n"];
            double position = 0.0;
            for (NSInteger lineNum =  lines.count-2; lineNum >= 0; lineNum--) {
                NSString * line = [lines objectAtIndex:lineNum];
                NSArray * words = [line componentsSeparatedByString:@":"]; //always 1
                position= [[words objectAtIndex:0] doubleValue];
                if (position  > 0) {
                    return (position/self.show.fileSize);
                }
            };
            return 0.0;
        };
    }

//    decryptTask.cleanupHandler = ^(){
//        if (![[NSUserDefaults standardUserDefaults] boolForKey:kMTSaveTmpFiles]) {
//            if ([[NSFileManager defaultManager] fileExistsAtPath:self.bufferFilePath]) {
//                [[NSFileManager defaultManager] removeItemAtPath:self.bufferFilePath error:nil];
//            }
//        }
//    };
    NSString * mediaKey = [NSString stringWithFormat:
                          @"-m%@%@",
                           libreJar ? @" " : @"",
                           self.show.tiVo.mediaKey];
	NSArray *arguments = @[
						  mediaKey,
						  [NSString stringWithFormat:@"-o%@",self.decryptedFilePath],
						  @"-v",
                          @"-"
                          ];
    if (libreJar) {
        arguments = @[
                      @"-jar",
                      libreJar,
                      mediaKey,
                      @"-d",
                      [NSString stringWithFormat:@"-o %@",self.decryptedFilePath],
                      ];
    }
    decryptTask.requiresOutputPipe = NO;
    if (self.exportSubtitles.boolValue || self.shouldSimulEncode) {  //use stdout to pipe to captions  or simultaneous encoding
        arguments =@[
                     mediaKey,
                     @"-v",
                     @"--",
                     @"-"
                     ];
        if (libreJar) {
            arguments = @[
                          @"-jar",
                          libreJar,
                          mediaKey,
                          @"-d"
                          ];
        }
        decryptTask.requiresOutputPipe = YES;
        //Not using the filebuffer so remove so it can act as a flag upon completion.
        if (!self.skipCommercials && !self.exportSubtitles.boolValue && !self.markCommercials) {
            if (![[NSUserDefaults standardUserDefaults] boolForKey:kMTSaveTmpFiles]) {
                [[NSFileManager defaultManager] removeItemAtPath:self.decryptedFilePath error:nil];
            };
            self.decryptedFilePath = nil;
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
    NSArray * encoderArgs = nil;

    encodeTask.completionHandler = ^BOOL(){
        [self setValue:[NSNumber numberWithInt:kMTStatusEncoded] forKeyPath:@"downloadStatus"];
        //        [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationEncodeDidFinish object:nil];
        self.processProgress = 1.0;
        [self progressUpdated];
        if (! [[NSFileManager defaultManager] fileExistsAtPath:self.encodeFilePath] ) {
            DDLogReport(@" %@ File %@ not found after encoding complete",self, self.encodeFilePath );
            [self rescheduleShowWithDecrementRetries:@(YES)];
            return NO;

        } else if (self.taskFlowType != kMTTaskFlowSimuMarkcom && self.taskFlowType != kMTTaskFlowSimuMarkcomSubtitles) {
            [self writeMetaDataFiles];
            //            if ( ! (self.includeAPMMetaData.boolValue && self.encodeFormat.canAcceptMetaData) ) {
            [self finishUpPostEncodeProcessing];
            //            }
        }
        return YES;
    };

    encodeTask.cleanupHandler = ^(){
        if (self.activeURLConnection || ! self.shouldSimulEncode) {  //else we've already checked
            [self checkLogForAudio: self.encodeTask.errorFilePath];
        }
       if (self.isCanceled) {
           [self deleteVideoFile];
       }
    };

    encodeTask.terminationHandler = nil;
    
    encoderArgs = [self encodingArgumentsWithInputFile:@"-" outputFile:self.encodeFilePath];

    if (!self.shouldSimulEncode)  {
        if (self.encodeFormat.canSimulEncode) {  //Need to setup up the startup for sequential processing to use the writeData progress tracking
            encodeTask.requiresInputPipe = YES;
            __block NSPipe *encodePipe = [NSPipe new];
            [encodeTask setStandardInput:encodePipe];
            encodeTask.startupHandler = ^BOOL(){
                if ([self isCompleteCTiVoFile:self.encodeFilePath forFileType:@"Encoded"]){
                    return NO;
                }

                if (self.bufferFileReadHandle) {
                    [self.bufferFileReadHandle closeFile];
                }
                self.bufferFileReadHandle = [NSFileHandle fileHandleForReadingAtPath:self.decryptedFilePath];
                self.urlBuffer = nil;
                self.taskChainInputHandle = [encodePipe fileHandleForWriting];
                self.processProgress = 0.0;
                self.previousProcessProgress = 0.0;
                self.totalDataRead = 0.0;
                [self progressUpdated];
                [self setValue:[NSNumber numberWithInt:kMTStatusEncoding] forKeyPath:@"downloadStatus"];
                [self performSelectorInBackground:@selector(writeData) withObject:nil];
                return YES;
            };

        } else {
            encoderArgs = [self encodingArgumentsWithInputFile:self.decryptedFilePath outputFile:self.encodeFilePath];
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
                        DDLogMajor(@"Encode progress with RX %@ failed for task encoder for show %@\nEncoder report: %@",percents, self.show.showTitle, data);

                    }
                    return returnValue;
                };
            };
            encodeTask.startupHandler = ^BOOL(){
                self.processProgress = 0.0;
                [self progressUpdated];
                [self setValue:[NSNumber numberWithInt:kMTStatusEncoding] forKeyPath:@"downloadStatus"];
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
    NSArray *srtEntries = [NSArray getFromSRTFile:self.captionFilePath];
    NSArray *edlEntries = [NSArray getFromEDLFile:self.commercialFilePath];
    if (srtEntries && edlEntries) {
        NSArray *correctedSrts = [srtEntries processWithEDLs:edlEntries];
        if ([[NSUserDefaults standardUserDefaults] boolForKey:kMTSaveTmpFiles]) {
            NSString *oldCaptionPath = [[self.captionFilePath stringByDeletingPathExtension] stringByAppendingString:@"2.srt"];
            [[NSFileManager defaultManager] moveItemAtPath:self.captionFilePath toPath:oldCaptionPath error:nil];
        }
        if (correctedSrts) {
            [correctedSrts writeToSRTFilePath:self.captionFilePath];
            [self markCompleteCTiVoFile:self.captionFilePath];
        }
    }
}

-(MTTask *)captionTask  //Captioning is done in parallel with download so no progress indicators are needed.
{
    NSAssert(self.exportSubtitles.boolValue,@"captionTask not requested");
    if (_captionTask) {
        return _captionTask;
    }
    MTTask *captionTask = [MTTask taskWithName:@"caption" download:self completionHandler:nil];
    [captionTask setLaunchPath:[[NSBundle mainBundle] pathForAuxiliaryExecutable:@"ccextractor" ]];
    captionTask.requiresOutputPipe = NO;
    captionTask.shouldReschedule  = NO;  //If captioning fails continue, just without captioning

    if (self.downloadingShowFromMPGFile) {
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
					returnValue = (currentTimeOffset/self.show.showLength);
				}
                
            }
			if (returnValue == -1.0){
                DDLogMajor(@"Track progress with Rx failed for task caption for show %@: %@",self.show.showTitle, data);
            }
			return returnValue;
        };
        if (!self.encodeFormat.canSimulEncode) {
            captionTask.startupHandler = ^BOOL(){
                self.processProgress = 0.0;
                [self setValue:[NSNumber numberWithInt:kMTStatusCaptioning] forKeyPath:@"downloadStatus"];
                [self progressUpdated];
                return YES;
            };
        }
    }

    
    captionTask.completionHandler = ^BOOL(){
//        [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationCaptionDidFinish object:nil];
        if ( self.skipCommercials && _commercialTask.successfulExit) {
            [self fixupSRTsDueToCommercialSkipping];
        }
        [self markCompleteCTiVoFile:self.captionFilePath];
		return YES;
    };
    
    captionTask.cleanupHandler = ^(){
        if (_captionTask.taskFailed) {
            [tiVoManager  notifyWithTitle:@"Detecting Captions Failed" subTitle:[NSString stringWithFormat:@"Not including captions for %@",self.show.showTitle] isSticky:YES forNotification:kMTGrowlCommercialDetFailed];
        }
        if (![[NSUserDefaults standardUserDefaults] boolForKey:kMTSaveTmpFiles] &&
            (_captionTask.taskFailed || self.isCanceled)) {
            if ([[NSFileManager defaultManager] fileExistsAtPath:self.captionFilePath]) {
                [[NSFileManager defaultManager] removeItemAtPath:self.captionFilePath error:nil];
            }
            self.captionFilePath = nil;
        }
    };
    
    NSMutableArray * captionArgs = [NSMutableArray array];
    
    if (self.encodeFormat.captionOptions.length) [captionArgs addObjectsFromArray:[self getArguments:self.encodeFormat.captionOptions]];
    
    [captionArgs addObject:@"-bi"];
    [captionArgs addObject:@"-utf8"];
    [captionArgs addObject:@"-s"];
    //[captionArgs addObject:@"-debug"];
    [captionArgs addObject:@"-"];
    [captionArgs addObject:@"-o"];
    [captionArgs addObject:self.captionFilePath];
    DDLogVerbose(@"ccExtractorArgs: %@",captionArgs);
    [captionTask setArguments:captionArgs];
    DDLogVerbose(@"Caption Task = %@",captionTask);
    _captionTask = captionTask;
    return captionTask;
}

-(MTTask *)commercialTask
{
    NSAssert(self.skipCommercials || self.markCommercials ,@"Commercial Task not requested?");

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
    
    
    commercialTask.cleanupHandler = ^(){
        if (_commercialTask.taskFailed) {
            if ([self checkLogForAudio: self.commercialTask.logFilePath]) {
                [self rescheduleOnMain];
            } else {
                [tiVoManager  notifyWithTitle:@"Detecting Commercials Failed" subTitle:[NSString stringWithFormat:@"Not processing commercials for %@",self.show.showTitle] isSticky:YES forNotification:kMTGrowlCommercialDetFailed];

                if ([[NSFileManager defaultManager] fileExistsAtPath:self.commercialFilePath]) {
                    [[NSFileManager defaultManager] removeItemAtPath:self.commercialFilePath error:nil];
                }
                NSData *zeroData = [NSData data];
                [zeroData writeToFile:self.commercialFilePath atomically:YES];
                _commercialTask.completionHandler();
            }
        }
    };

    if (self.taskFlowType != kMTTaskFlowNonSimuMarkcom && self.taskFlowType != kMTTaskFlowNonSimuMarkcomSubtitles) {  // For these cases the encoding tasks is the driver
        commercialTask.startupHandler = ^BOOL(){
            self.processProgress = 0.0;
            [self setValue:[NSNumber numberWithInt:kMTStatusCommercialing] forKeyPath:@"downloadStatus"];
            return YES;
        };

        NSRegularExpression *percents = [NSRegularExpression regularExpressionWithPattern:@"(\\d+)\\%" options:NSRegularExpressionCaseInsensitive error:nil];
        commercialTask.progressCalc = ^double(NSString *data){
            if (!data) return 0.0;
            NSArray *values = [percents matchesInString:data options:NSMatchingWithoutAnchoringBounds range:NSMakeRange(0, data.length)];
            NSTextCheckingResult *lastItem = [values lastObject];
            NSRange valueRange = [lastItem rangeAtIndex:1];
            return [[data substringWithRange:valueRange] doubleValue]/100.0;
        };

    
        commercialTask.completionHandler = ^BOOL{
            DDLogMajor(@"Finished detecting commercials in %@",self.show.showTitle);
             if (self.taskFlowType != kMTTaskFlowSimuMarkcom && self.taskFlowType != kMTTaskFlowSimuMarkcomSubtitles) {
				 if (!self.shouldSimulEncode) {
					self.processProgress = 1.0;
				 }
				[self progressUpdated];
				[self setValue:[NSNumber numberWithInt:kMTStatusCommercialed] forKeyPath:@"downloadStatus"];
				if (self.exportSubtitles.boolValue && self.skipCommercials && self.captionFilePath && _captionTask.successfulExit) {
                    [self fixupSRTsDueToCommercialSkipping];
				}
             } else {
                 self.processProgress = 1.0;
                 [self progressUpdated];
                 [self setValue:[NSNumber numberWithInt:kMTStatusCommercialed] forKeyPath:@"downloadStatus"];
                 [self writeMetaDataFiles];
                 [self finishUpPostEncodeProcessing];
             }
            [self markCompleteCTiVoFile:self.commercialFilePath];
            return YES;
        };
    } else {
        commercialTask.completionHandler = ^BOOL{
            DDLogMajor(@"Finished detecting commercials in %@",self.show.showTitle);
			return YES;
        };
    }


	NSMutableArray *arguments = [NSMutableArray array];
    if (self.encodeFormat.comSkipOptions.length) [arguments addObjectsFromArray:[self getArguments:self.encodeFormat.comSkipOptions]];
    NSRange iniRange = [self.encodeFormat.comSkipOptions rangeOfString:@"--ini="];
//	[arguments addObject:[NSString stringWithFormat: @"--output=%@",[self.commercialFilePath stringByDeletingLastPathComponent]]];  //0.92 version
    if (iniRange.location == NSNotFound) {
        [arguments addObject:[NSString stringWithFormat: @"--ini=%@",[[NSBundle mainBundle] pathForResource:@"comskip" ofType:@"ini"]]];
    }
    
    if ((self.taskFlowType == kMTTaskFlowSimuMarkcom || self.taskFlowType == kMTTaskFlowSimuMarkcomSubtitles) && [self canPostDetectCommercials]) {
        [arguments addObject:self.encodeFilePath]; //Run on the final file for these conditions
        self.commercialFilePath = [NSString stringWithFormat:@"%@/%@.edl" ,tiVoManager.tmpFilesDirectory, self.baseFileName];  //0.92 version  (probably wrong, but not currently used)
    } else {
        [arguments addObject:self.decryptedFilePath];// Run this on the output of tivodecode
    }
	DDLogVerbose(@"comskip Path: %@",[[NSBundle mainBundle] pathForAuxiliaryExecutable:@"comskip" ]);
	DDLogVerbose(@"comskip args: %@",arguments);
	[commercialTask setArguments:arguments];
    _commercialTask = commercialTask;
    return _commercialTask;
  
}

//Task Flow Types
// bit 0 = Subtitle
// bit 1 = Simultaneous download/encoding
// bit 2 = Skip Com
// bit 3 = Mark Com
//no 12-15 because skipCom <==> ! markCom

typedef NS_ENUM(NSUInteger, MTTaskFlowType) {
    kMTTaskFlowNonSimu = 0,
    kMTTaskFlowNonSimuSubtitles = 1,
    kMTTaskFlowSimu = 2,
    kMTTaskFlowSimuSubtitles = 3,
    kMTTaskFlowNonSimuSkipcom = 4,
    kMTTaskFlowNonSimuSkipcomSubtitles = 5,
    kMTTaskFlowSimuSkipcom = 6,
    kMTTaskFlowSimuSkipcomSubtitles = 7,
    kMTTaskFlowNonSimuMarkcom = 8,
    kMTTaskFlowNonSimuMarkcomSubtitles = 9,
    kMTTaskFlowSimuMarkcom = 10,
    kMTTaskFlowSimuMarkcomSubtitles = 11
};

-(MTTaskFlowType)taskFlowType
{
  return (MTTaskFlowType)
          1 * (int) self.exportSubtitles.boolValue +
          2 * (int) self.encodeFormat.canSimulEncode +
          4 * (int) self.skipCommercials +
          8 * (int) self.markCommercials;
}

-(void)download
{
	NSUserDefaults * defaults = [NSUserDefaults standardUserDefaults];
    NSCellStateValue channelUsesTS = [tiVoManager useTSForChannel:self.show.stationCallsign];

    NSCellStateValue psFailed = [tiVoManager failedPSForChannel :self.show.stationCallsign];
    if (self.encodeFormat.isTestPS) {
        self.useTransportStream = NO;  //if testing whether PS is bad, naturally don't use TS
    } else { 
        self.useTransportStream =
            [defaults boolForKey:kMTDownloadTSFormat] ||  //always use TS OR
            channelUsesTS == NSOnState ||                   //user specified TS for this channel OR
            (channelUsesTS == NSMixedState && psFailed == NSOnState ); //user didn't care, but we've seen need
    }
    if (([tiVoManager commercialsForChannel:self.show.stationCallsign] == NSOffState) &&
        (self.skipCommercials || self.markCommercials)) {
        //this channel doesn't use commercials
        DDLogDetail(@"Channel %@ doesn't use commercials; overriding  for %@",self.show.stationCallsign, self.show);
        self.skipCommercials = NO;
        self.markCommercials = NO;
    }
	DDLogMajor(@"Starting %d download for %@; Format: %@; %@%@%@%@%@%@%@%@%@%@%@; %@",
				(int)self.taskFlowType,
				self,
				self.encodeFormat.name ,
				self.encodeFormat.canSimulEncode ?
                    @"simul encode" :
                    @"",
				self.skipCommercials ?
					@" Skip commercials;" :
                    @"",
                self.markCommercials ?
					 @" Mark commercials;" :
					 @"",
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
				[defaults boolForKey:kMTUseMemoryBufferForDownload]?
					@"" :
					@" No Memory Buffer;",
               [defaults boolForKey:kMTGetEpisodeArt] ?
                    @" " :
					@" No TVDB art; ",
               [defaults objectForKey:kMTDecodeBinary],
               self.useTransportStream ? @"Transport Stream" : @"Program Stream"
				);
	self.isCanceled = NO;
	self.isRescheduled = NO;
    self.downloadingShowFromTiVoFile = NO;
    self.downloadingShowFromMPGFile = NO;
    self.progressAt100Percent = nil;  //Reset end of progress failure delay
    //Before starting make sure the encoder is OK.
	if (![self encoderPath]) {
        [NSNotificationCenter postNotificationNameOnMainThread:kMTNotificationShowDownloadWasCanceled object:nil];  //Decrement num encoders right away
		return;
	}
	
    //Tivodecode is always run.  The output of the tivodecode task will always to to a file to act as a buffer for differeing download and encoding speeds.
    //The file will be a mpg file in the tmp directory (the buffer file path)
    
    [self configureFiles];
    
    //decrypt task is a special task as it is always run and always to a file due to buffering requirement for the URL connection to the Tivo.
    //It shoul not be part of the processing chain.
    
    self.activeTaskChain = [MTTaskChain new];
    self.activeTaskChain.download = self;
    if (!self.downloadingShowFromMPGFile && !self.downloadingShowFromTiVoFile) {
        NSPipe *taskInputPipe = [NSPipe pipe];
        self.activeTaskChain.dataSource = taskInputPipe;
        self.taskChainInputHandle = [taskInputPipe fileHandleForWriting];
    } else if (self.downloadingShowFromTiVoFile) {
        self.activeTaskChain.dataSource = self.tivoFilePath;
        DDLogMajor(@"Downloading from file tivo file %@",self.tivoFilePath);
    } else if (self.downloadingShowFromMPGFile) {
        DDLogMajor(@"Downloading from file MPG file %@",self.mpgFilePath);
        self.activeTaskChain.dataSource = self.mpgFilePath;
    }
	
    NSMutableArray *taskArray = [NSMutableArray array];
	
	if (!self.downloadingShowFromMPGFile) {
        MTTask * decryptTask = self.decryptTask;
        if (decryptTask) {
            [taskArray addObject:@[decryptTask]];
        } else {
            [NSNotificationCenter postNotificationNameOnMainThread:kMTNotificationShowDownloadWasCanceled object:nil];  //Decrement num encoders right away
            [self setValue:[NSNumber numberWithInt:kMTStatusFailed] forKeyPath:@"downloadStatus"];
            return;
        }
    }
    MTTask * encodeTask = self.encodeTask;
    if (!encodeTask) {
        [NSNotificationCenter postNotificationNameOnMainThread:kMTNotificationShowDownloadWasCanceled object:nil];  //Decrement num encoders right away
        [self setValue:[NSNumber numberWithInt:kMTStatusFailed] forKeyPath:@"downloadStatus"];
        return;
    }
    switch (self.taskFlowType) {
        case kMTTaskFlowNonSimu:  //Just encode with non-simul encoder
        case kMTTaskFlowSimu:  //Just encode with simul encoder
           [taskArray addObject:@[encodeTask]];
            break;
            
        case kMTTaskFlowNonSimuSubtitles:  //Encode with non-simul encoder and subtitles
            if(self.downloadingShowFromMPGFile) {
                [taskArray addObject:@[self.captionTask]];
            } else {
                [taskArray addObject:@[self.captionTask,[self catTask:self.decryptedFilePath]]];
            }
			[taskArray addObject:@[encodeTask]];
            break;
            
        case kMTTaskFlowSimuSubtitles:  //Encode with simul encoder and subtitles
            if(self.downloadingShowFromMPGFile)self.activeTaskChain.providesProgress = YES;
			[taskArray addObject:@[encodeTask,self.captionTask]];
            break;
            
        case kMTTaskFlowNonSimuSkipcom:  //Encode with non-simul encoder skipping commercials
        case kMTTaskFlowSimuSkipcom:  //Encode with simul encoder skipping commercials
			[taskArray addObject:@[self.commercialTask]];
            [taskArray addObject:@[encodeTask]];
            break;
            
        case kMTTaskFlowNonSimuSkipcomSubtitles:  //Encode with non-simul encoder skipping commercials and subtitles
        case kMTTaskFlowSimuSkipcomSubtitles:  //Encode with simul encoder skipping commercials and subtitles
			[taskArray addObject:@[self.captionTask,[self catTask:self.decryptedFilePath]]];
			[taskArray addObject:@[self.commercialTask]];
			[taskArray addObject:@[encodeTask]];
            break;
            
        case kMTTaskFlowNonSimuMarkcom:  //Encode with non-simul encoder marking commercials
            [taskArray addObject:@[encodeTask, self.commercialTask]];
            break;
            
        case kMTTaskFlowNonSimuMarkcomSubtitles:  //Encode with non-simul encoder marking commercials and subtitles
            if(self.downloadingShowFromMPGFile) {
                assert(self.captionTask);
                [taskArray addObject:@[self.captionTask]];
            } else {
                [taskArray addObject:@[self.captionTask,[self catTask:self.decryptedFilePath]]];
            }
            [taskArray addObject:@[encodeTask, self.commercialTask]];
            break;
            
        case kMTTaskFlowSimuMarkcom:  //Encode with simul encoder marking commercials
            if(self.downloadingShowFromMPGFile) {
                [taskArray addObject:@[encodeTask]];
            } else {
                if ([self canPostDetectCommercials]) {
                    [taskArray addObject:@[encodeTask]];
                } else {
                    [taskArray addObject:@[encodeTask,[self catTask:self.decryptedFilePath] ]];
                }
            }
            [taskArray addObject:@[self.commercialTask]];
           break;
            
        case kMTTaskFlowSimuMarkcomSubtitles:  //Encode with simul encoder marking commercials and subtitles
            if(self.downloadingShowFromMPGFile) {
                [taskArray addObject:@[self.captionTask,encodeTask]];
            } else {
                if ([self canPostDetectCommercials]) {
                    [taskArray addObject:@[encodeTask, self.captionTask]];
                } else {
                    [taskArray addObject:@[encodeTask, self.captionTask,[self catTask:self.decryptedFilePath]]];
                }
            }
            [taskArray addObject:@[self.commercialTask]];
           break;
            
        default:
            break;
    }
	
#ifndef deleteXML
	//	if (self.captionTask) {
//		if (self.commercialTask) {
//			[taskArray addObject:@[self.captionTask,[self catTask:self.decryptedFilePath]]];
//			[taskArray addObject:@[self.commercialTask]];
//			[taskArray addObject:@[self.encodeTask]];
//		} else if (self.encodeFormat.canSimulEncode) {
//            if(self.downloadingShowFromMPGFile)self.activeTaskChain.providesProgress = YES;
//			[taskArray addObject:@[self.encodeTask,self.captionTask]];
//		} else {
//            if(self.downloadingShowFromMPGFile) {
//                [taskArray addObject:@[self.captionTask]];
//            } else {
//                [taskArray addObject:@[self.captionTask,[self catTask:self.decryptedFilePath]]];                
//            }
//			[taskArray addObject:@[self.encodeTask]];
//		}
//	} else {
//		if (self.commercialTask) {
//			[taskArray addObject:@[self.commercialTask]];
//		}
//		[taskArray addObject:@[self.encodeTask]];
//	}
//	if (self.apmTask) {
//		[taskArray addObject:@[self.apmTask]];
//	}
#endif
	self.activeTaskChain.taskArray = [NSArray arrayWithArray:taskArray];
    
    self.totalDataRead = 0;
    self.totalDataDownloaded = 0;
    NSURL * downloadURL = nil;
    if (!self.downloadingShowFromTiVoFile && !self.downloadingShowFromMPGFile) {
        downloadURL = self.show.downloadURL;
        if (self.useTransportStream) {
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

    [self.activeTaskChain run];
    double downloadDelay = kMTTiVoAccessDelayServerFailure - [[NSDate date] timeIntervalSinceDate:self.show.tiVo.lastDownloadEnded];
    if (downloadDelay < 0) {
        downloadDelay = 0;
    }
    [self setValue:[NSNumber numberWithInt:kMTStatusWaiting] forKeyPath:@"downloadStatus"];
    [self performSelector:@selector(setDownloadStatus:) withObject:@(kMTStatusDownloading) afterDelay:downloadDelay];

	if (!self.downloadingShowFromTiVoFile && !self.downloadingShowFromMPGFile)
	{
        DDLogReport(@"Starting URL %@ for show %@ in %0.1lf seconds", downloadURL,self.show.showTitle, downloadDelay);
		[self.activeURLConnection scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSRunLoopCommonModes];
		[self.activeURLConnection performSelector:@selector(start) withObject:nil afterDelay:downloadDelay];
	}
    [self performSelector:@selector(checkStillActive) withObject:nil afterDelay:[[NSUserDefaults standardUserDefaults] integerForKey: kMTMaxProgressDelay] + downloadDelay];
}

- (NSImage *) artworkWithPrefix: (NSString *) prefix andSuffix: (NSString *) suffix InPath: (NSString *) directory {
	prefix = [prefix lowercaseString];
	suffix = [suffix lowercaseString];
    if (directory.length == 0) return nil;
	NSString * realDirectory = [directory stringByStandardizingPath];
	DDLogVerbose(@"Checking for %@_%@ artwork in %@", prefix, suffix ?:@"", realDirectory);
	NSArray *dirContents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:realDirectory error:nil];
	for (NSString *filename in dirContents) {
		NSString *lowerCaseFilename = [filename lowercaseString];
		if (!prefix || [lowerCaseFilename hasPrefix:prefix]) {
			NSString * extension = [lowerCaseFilename pathExtension];
			if ([[NSImage imageFileTypes] indexOfObject:extension] != NSNotFound) {
				NSString * base = [lowerCaseFilename stringByDeletingPathExtension];
				if (!suffix || [base hasSuffix:suffix]){
					NSString * path = [realDirectory stringByAppendingPathComponent: filename];
					DDLogDetail(@"found artwork for %@ in %@",self.show.seriesTitle, path);
					NSImage * image = [[NSImage alloc] initWithContentsOfFile:path];
					if (image) {
						return image;
					} else {
						DDLogReport(@"Couldn't load artwork for %@ from %@",self.show.seriesTitle, path);
					}
				}
			}
		}
	}
	return nil;
}

- (NSImage *) findArtWork {
	NSString *currentDir   = self.downloadDir;
    if(!currentDir) return nil;
	NSString *thumbnailDir = [currentDir stringByAppendingPathComponent:@"thumbnails"];
	NSArray * directories;
	NSString * legalSeriesName = [self.show.seriesTitle stringByReplacingOccurrencesOfString:@"/" withString:@"-"];
	legalSeriesName = [legalSeriesName stringByReplacingOccurrencesOfString:@":" withString:@"-"] ;

	NSString * userThumbnailDir = [[NSUserDefaults standardUserDefaults] stringForKey:kMTThumbnailsDirectory];
	if (userThumbnailDir) {
		directories = @[userThumbnailDir];
	} else if ([[NSUserDefaults standardUserDefaults] boolForKey:kMTMakeSubDirs]) {
		NSString *parentDir = [currentDir stringByDeletingLastPathComponent];
		NSString *parentThumbDir = [parentDir stringByAppendingPathComponent:@"thumbnails"];
		directories = @[currentDir, thumbnailDir, parentDir, parentThumbDir];
	} else {
		directories = @[currentDir, thumbnailDir];
	}
    
    if (self.show.isMovie) {
        for (NSString * dir in directories) {
            NSImage * artwork = [self artworkWithPrefix:legalSeriesName andSuffix:self.show.movieYear  InPath:dir ];
            if (artwork) return artwork;
        }
        for (NSString * dir in directories) {
            NSImage * artwork = [self artworkWithPrefix:legalSeriesName andSuffix:nil InPath:dir ];
            if (artwork) return artwork;
        }

        //then for downloaded temp art
        if (self.show.artworkFile) {
            NSImage * image = [[NSImage alloc] initWithContentsOfFile:self.show.artworkFile];
            if (image) {
                return image;
            } else {
                DDLogReport(@"Couldn't load downloaded artwork for %@ from %@",self.show.seriesTitle, self.show.artworkFile);
            }

        }
    } else 	if (self.show.season > 0) {
		//first check for user-specified, episode-specific art
		if (self.show.seasonEpisode.length > 0) {
			for (NSString * dir in directories) {
				NSImage * artwork = [self artworkWithPrefix:legalSeriesName andSuffix:self.show.seasonEpisode  InPath:dir ];
				if (artwork) return artwork;
			}
        }

        //then for season-specific art
        NSString * season = [NSString stringWithFormat:@"S%0.2d",self.show.season];
        for (NSString * dir in directories) {
            NSImage * artwork = [self artworkWithPrefix:legalSeriesName andSuffix:season InPath:dir ];
            if (artwork) return artwork;
        }
	}
	//finally for series-level art
	for (NSString * dir in directories) {
		NSImage * artwork = [self artworkWithPrefix:legalSeriesName andSuffix:nil InPath:dir ];
		if (artwork) return artwork;
	}
    //then for downloaded temp art
    if (self.show.artworkFile) {
        NSImage * image = [[NSImage alloc] initWithContentsOfFile:self.show.artworkFile];
        if (image) {
            return image;
        } else {
            DDLogReport(@"Couldn't load downloaded artwork for %@ from %@",self.show.seriesTitle, self.show.artworkFile);
        }
    }
	if (![[NSUserDefaults standardUserDefaults] boolForKey:kMTiTunesIcon]) {
		return [NSImage imageNamed:@"cTiVo.png"];  //from iTivo; use our logo for any new video files.
	}
	DDLogDetail(@"artwork for %@ not found",self.show.seriesTitle);
	return nil;
}


-(void) writeTextMetaData:(NSString*) value forKey: (NSString *) key toFile: (NSFileHandle *) handle {
	if ( key.length > 0 && value.length > 0) {
		
		[handle writeData:[[NSString stringWithFormat:@"%@ : %@\n",key, value] dataUsingEncoding:NSUTF8StringEncoding]];
	}
}

-(void) writeMetaDataFiles {
	
	NSString * detailFilePath = [NSString stringWithFormat:@"%@/%@_%d_Details.xml",kMTTmpDetailsDir,self.show.tiVoName,self.show.showID];
#ifndef deleteXML
	if (self.genXMLMetaData.boolValue) {
		NSString * tivoMetaPath = [[self.encodeFilePath stringByDeletingPathExtension] stringByAppendingPathExtension:@"xml"];
		DDLogMajor(@"Writing XML to    %@",tivoMetaPath);
		if (![[NSFileManager defaultManager] copyItemAtPath: detailFilePath toPath:tivoMetaPath error:nil]) {
				DDLogReport(@"Couldn't write XML to file %@", tivoMetaPath);
		}
	}
#endif
	if (self.genTextMetaData.boolValue && [[NSFileManager defaultManager] fileExistsAtPath:detailFilePath]) {
		NSData * xml = [NSData dataWithContentsOfFile:detailFilePath];
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

-(void) addXAttrs:(NSString *) videoFilePath {
	//Add xattrs
	NSData *tiVoName = [self.show.tiVoName dataUsingEncoding:NSUTF8StringEncoding];
	NSData *tiVoID = [self.show.idString dataUsingEncoding:NSUTF8StringEncoding];
	NSData *spotlightKeyword = [kMTSpotlightKeyword dataUsingEncoding:NSUTF8StringEncoding];
	setxattr([videoFilePath cStringUsingEncoding:NSASCIIStringEncoding], [kMTXATTRTiVoName UTF8String], [tiVoName bytes], tiVoName.length, 0, 0);
	setxattr([videoFilePath cStringUsingEncoding:NSASCIIStringEncoding], [kMTXATTRTiVoID UTF8String], [tiVoID bytes], tiVoID.length, 0, 0);
	setxattr([videoFilePath cStringUsingEncoding:NSASCIIStringEncoding], [kMTXATTRSpotlight UTF8String], [spotlightKeyword bytes], spotlightKeyword.length, 0, 0);
    
	[tiVoManager updateShowOnDisk:self.show.showKey withPath: videoFilePath];
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

-(void) finishUpPostEncodeProcessing {
    if (_decryptTask.isRunning ||
        _encodeTask.isRunning ||
        _commercialTask.isRunning ||
        _captionTask.isRunning)  {
        //if any of the tasks exist and are still running, then let them finish; checkStillActive will eventually fail them if no progress
        DDLogDetail(@"Finishing up, but processes still running");
        [self performSelector:@selector(finishUpPostEncodeProcessing) withObject:nil afterDelay:0.5];
        return;
    }
    NSDate *startTime = [NSDate date];
    DDLogMajor(@"Starting finishing @ %@",startTime);
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(checkStillActive) object:nil];
    if (!self.encodeFormat.isTestPS) {
        if (!(_decryptTask.successfulExit && _encodeTask.successfulExit)) {
            DDLogReport(@"Strange: thought we were finished, but later %@ failure", _decryptTask.successfulExit ? @"encode" : @"decrypt");
            [self cancel]; //just in case
            [self setValue:[NSNumber numberWithInt:kMTStatusFailed] forKeyPath:@"downloadStatus"];
            return;
        }
        NSImage * artwork = nil;
        if (self.encodeFormat.canAcceptMetaData || self.addToiTunesWhenEncoded) {
            //see if we can find artwork for this series
            artwork = [self findArtWork];
        }
        if (self.shouldMarkCommercials || self.encodeFormat.canAcceptMetaData || self.shouldEmbedSubtitles) {
            MP4FileHandle *encodedFile = MP4Modify([self.encodeFilePath cStringUsingEncoding:NSUTF8StringEncoding],0);
            if (self.shouldMarkCommercials) {
                if ([[NSFileManager defaultManager] fileExistsAtPath:self.commercialFilePath]) {
                    NSArray *edls = [NSArray getFromEDLFile:self.commercialFilePath];
                    if ( edls.count > 0) {
                        [edls addAsChaptersToMP4File: encodedFile forShow: self.show.showTitle withLength: self.show.showLength ];
                    }
                }
            }
            if (self.shouldEmbedSubtitles && self.captionFilePath) {
                NSArray * srtEntries = [NSArray getFromSRTFile:self.captionFilePath];
                if (srtEntries.count > 0) {
                    [srtEntries embedSubtitlesInMP4File:encodedFile forLanguage:[MTSrt languageFromFileName:self.captionFilePath]];
                }
            }
            if (self.encodeFormat.canAcceptMetaData) {
                [self.show addExtendedMetaDataToFile:encodedFile withImage:artwork];
            }
            
            MP4Close(encodedFile, 0);
        }
        if (self.addToiTunesWhenEncoded) {
            DDLogMajor(@"Adding to iTunes %@", self.show.showTitle);
            self.processProgress = 1.0;
            [self setValue:[NSNumber numberWithInt:kMTStatusAddingToItunes] forKeyPath:@"downloadStatus"];
            [self progressUpdated];
            MTiTunes *iTunes = [[MTiTunes alloc] init];
            NSString * iTunesPath = [iTunes importIntoiTunes:self withArt:artwork] ;
            
            if (iTunesPath && ![iTunesPath isEqualToString: self.encodeFilePath]) {
                //apparently iTunes created new file
                if ([[NSUserDefaults standardUserDefaults] boolForKey:kMTiTunesDelete ]) {
                    [self deleteVideoFile];
                    //move caption, commercial, and pytivo metadata files along with video
                    NSString * iTunesBaseName = [iTunesPath stringByDeletingPathExtension];
                    if (self.shouldEmbedSubtitles && self.captionFilePath) {
                         self.captionFilePath = [self moveFile:self.captionFilePath toITunes:iTunesBaseName forType:@"caption" andExtension: @"srt"] ?: self.captionFilePath;
                    }
                    if (self.genTextMetaData.boolValue) {
                        NSString * textMetaPath = [self.encodeFilePath stringByAppendingPathExtension:@"txt"];
                        NSString * doubleExtension = [[self.encodeFilePath pathExtension] stringByAppendingString:@".txt"];
                        [self moveFile:textMetaPath toITunes:iTunesBaseName forType:@"metadata" andExtension:doubleExtension];
                    }
                    //but remember new file for future processing
                    self.encodeFilePath= iTunesPath;
                } else {
                    //two copies now, so add xattrs to iTunes copy as well; leave captions/metadata/commercials with original
                    [self addXAttrs:iTunesPath];
                }
            }
        }
        [self addXAttrs:self.encodeFilePath];
    //    [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationDetailsLoaded object:self.show];
        DDLogVerbose(@"Took %lf seconds to complete for show %@",[[NSDate date] timeIntervalSinceDate:startTime], self.show.showTitle);
        [tiVoManager  notifyWithTitle:@"TiVo show transferred." subTitle:self.show.showTitle forNotification:kMTGrowlEndDownload];
    }
	[self setValue:[NSNumber numberWithInt:kMTStatusDone] forKeyPath:@"downloadStatus"];
    [NSNotificationCenter postNotificationNameOnMainThread:kMTNotificationShowDownloadDidFinish object:self];  //Currently Free up an encoder/ notify subscription module / update UI
    self.processProgress = 1.0;
	[self progressUpdated];

    [self cleanupFiles];
    //Reset tasks
    self.decryptTask = self.captionTask = self.commercialTask = self.encodeTask  = nil;
}


-(void)cancel
{
    if (self.isCanceled || !self.isInProgress) {
        return;
    }
    self.isCanceled = YES;
    DDLogMajor(@"Canceling of %@", self.show.showTitle);
//    NSFileManager *fm = [NSFileManager defaultManager];
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    if (self.activeURLConnection) {
        [self.activeURLConnection cancel];
		self.show.tiVo.lastDownloadEnded = [NSDate date];
        self.activeURLConnection = nil;
	}
    if(self.activeTaskChain.isRunning) {
        [self.activeTaskChain cancel];
        self.activeTaskChain = nil;
    }
//    [[NSNotificationCenter defaultCenter] removeObserver:self name:NSFileHandleReadCompletionNotification object:bufferFileReadHandle];
    if (!self.isNew && !self.isDone ) { //tests are already marked for success/failure
        [NSNotificationCenter postNotificationNameOnMainThread:kMTNotificationShowDownloadWasCanceled object:nil];
    }
    self.decryptTask = self.captionTask = self.commercialTask = self.encodeTask  = nil;
    
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
//    if ([self.downloadStatus intValue] == kMTStatusEncoding || (self.simultaneousEncode && self.isDownloading)) {
//        [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationEncodeWasCanceled object:self];
//    }
//    if ([self.downloadStatus intValue] == kMTStatusCaptioning) {
//        [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationCaptionWasCanceled object:self];
//    }
//    if ([self.downloadStatus intValue] == kMTStatusCommercialing) {
//        [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationCommercialWasCanceled object:self];
//    }
//    [self setValue:[NSNumber numberWithInt:kMTStatusNew] forKeyPath:@"downloadStatus"];
    if (self.processProgress != 0.0 ) {
		self.processProgress = 0.0;
        [self progressUpdated];
    }
    
}

#pragma mark - Download/Conversion  Progress Tracking

-(void)checkStillActive
{
    if (self.isCanceled || !self.isInProgress) {
        return;
    }

    if (self.previousProcessProgress == self.processProgress) { //The process is stalled so cancel and restart
		//Cancel and restart or delete depending on number of time we've been through this
        BOOL reschedule = YES;
        if (self.processProgress == 1.0) {
            reschedule = NO;
			if (!self.progressAt100Percent) {  //This is the first time here so record as the start of 100 % period
                DDLogMajor(@"Starting extended wait for 100%% progress stall (Handbrake) for show %@",self.show.showTitle);
                self.progressAt100Percent = [NSDate date];
            } else if ([[NSDate date] timeIntervalSinceDate:self.progressAt100Percent] > kMTProgressFailDelayAt100Percent){
                DDLogReport(@"Failed extended wait for 100%% progress stall (Handbrake) for show %@",self.show.showTitle);
                reschedule = YES;
            } else {
				DDLogVerbose(@"In extended wait for Handbrake");
			}
        } else {
                DDLogMajor (@"process stalled at %0.1f%%; rescheduling show %@ ", self.processProgress*100.0, self.show.showTitle);
        }
		if (reschedule) {
			[self rescheduleShowWithDecrementRetries:@(YES)];
		} else {
			[self performSelector:@selector(checkStillActive) withObject:nil afterDelay:[[NSUserDefaults standardUserDefaults] integerForKey: kMTMaxProgressDelay]];
		}
	} else if ([self isInProgress]){
        DDLogVerbose (@"process check OK; %0.2f", self.processProgress);
		self.previousProcessProgress = self.processProgress;
		[self performSelector:@selector(checkStillActive) withObject:nil afterDelay:[[NSUserDefaults standardUserDefaults] integerForKey: kMTMaxProgressDelay]];
	}
    self.previousCheck = [NSDate date];
}


-(BOOL) isInProgress {
    return (!(self.isNew || self.isDone));
}

-(BOOL) isDownloading {
	return ([self.downloadStatus intValue] == kMTStatusDownloading ||[self.downloadStatus intValue] == kMTStatusWaiting );
}

-(BOOL) isDone {
	int status = [self.downloadStatus intValue];
	return (status == kMTStatusDone) ||
	(status == kMTStatusFailed) ||
	(status == kMTStatusDeleted);
}

-(BOOL) isNew {
	return ([self.downloadStatus intValue] == kMTStatusNew);
}

-(void)progressUpdated {
    [NSNotificationCenter postNotificationNameOnMainThread:kMTNotificationProgressUpdated object:self];
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
	if (!self.isDone) return nil;
	NSURL *   URL =  [self URLExists: self.encodeFilePath];
    if (!URL) {
        URL = [self URLExists:self.decryptedFilePath];
    }
    if (!URL && encrypted) {
        if ([self.bufferFilePath contains:@".tivo"]){ //not just a buffer
            URL= [self URLExists: self.bufferFilePath];
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
	return NO;
}

-(BOOL) revealInFinder {
	NSURL * showURL =[self videoFileURLWithEncrypted:YES];
	if (showURL) {
		DDLogMajor(@"Revealing file %@ ", showURL);
		[[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:@[ showURL ]];
		return YES;
	}
	return NO;
}

#pragma mark - Background routines

-(void)rescheduleOnMain
{
//	self.isCanceled = YES;
	[self performSelectorOnMainThread:@selector(rescheduleShowWithDecrementRetries:) withObject:@YES waitUntilDone:NO];
}

-(void)writeData
{
    // writeData supports getting its data from either an NSData buffer (self.urlBuffer) or a file on disk (self.bufferFilePath).  This allows cTiVo to
    // initially try to keep the dataflow off the disk, except for final products, where possible.  But, the ability to do this depends on the
    // processor being able to keep up with the data flow from the TiVo which is often not the case due to either a slow processor, fast network
    // connection, of different tasks competing for processor resources.  When the processor falls too far behind and the memory buffer will
    // become too large cTiVo will fall back to using files on the disk as a data buffer.
    @autoreleasepool {  //because run as separate thread

	//	self.writingData = YES;
    //DDLogVerbose(@"Writing data %@ : %@Connection %@", [NSThread isMainThread] ? @"Main" : @"Background", self.activeURLConnection == nil ? @"No ":@"", self.isCanceled ? @"- Cancelled" : @"");
    const long chunkSize = 50000;
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
                    [self rescheduleOnMain];
                    DDLogDetail(@"Rescheduling");
                };
				DDLogDetail(@"buffer read fail:%@; %@", exception.reason, self.show.showTitle);
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
                        DDLogReport(@"write fail1 for %@; tried %lu bytes; error: %zd",self.show, (unsigned long)[data length], amountSent);
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
                    [self rescheduleOnMain];
                }
            }

            @synchronized (self) {
                self.totalDataRead += dataRead;
                self.processProgress = self.totalDataRead/self.show.fileSize;
            }
         }
    }
    self.writingData = NO; //we are now committed to closing this background thread, so any further data will need new thread
	if (!self.activeURLConnection || self.isCanceled) {
		DDLogDetail(@"Writedata all done for show %@",self.show.showTitle);
		[self.taskChainInputHandle closeFile];
		self.taskChainInputHandle = nil;
        [self.bufferFileReadHandle closeFile];
		self.bufferFileReadHandle = nil;
        self.urlBuffer = nil;
 	}
    }

}

#pragma mark - NSURL Delegate Methods

-(BOOL) checkLogForAudio: (NSString *) filePath {
    //if we find audio required, then mark channel as TS.
    //If not, then IF it was a successfulencode, then mark as not needing TS
    if ( ! self.useTransportStream) {
        //If we did Program Stream and encoder says "I only see Audio", then probably TS required
        NSArray * audioOnlyStrings = @[
                                       @"Video stream is mandatory!",       //mencoder:
                                       @"No title found",                   //handbrake
                                       @"no video streams",                 //ffmpeg
                                       @"Stream #0:0: Audio",               //ffmpeg
                                       @"Could not open video codec"        //comskip
                                       ];
        NSString *log = [NSString stringWithContentsOfFile:filePath encoding:NSUTF8StringEncoding error:nil];
        if ( ! log.length) return NO;
        for (NSString * errMsg in audioOnlyStrings) {
            if ([log rangeOfString:errMsg].location != NSNotFound) {
                DDLogVerbose(@"found audio %@ in log file: %@",errMsg, [log maskMediaKeys]);

                NSString * channel = self.show.stationCallsign;
                DDLogMajor(@"Found evidence of audio-only stream in %@ on %@",self.show, channel);
                if ( [tiVoManager failedPSForChannel:channel] != NSOnState ) {
                    [tiVoManager setFailedPS:YES forChannelNamed:channel];
                    if ([tiVoManager useTSForChannel:channel] == NSOffState && !self.encodeFormat.isTestPS) {
                        //only notify if we're not (testing, OR previously seen, OR forcing PS)
                        [tiVoManager  notifyWithTitle:@"H.264 Channel" subTitle:[NSString stringWithFormat:@"Marking %@ as Transport Stream",channel] isSticky:YES forNotification:kMTGrowlTivodecodeFailed];
                    }
                }
                return YES;
            }
        }
    }
    return NO;
}

-(void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data
{
    self.totalDataDownloaded += data.length;
    if (self.totalDataDownloaded > 5000000 && self.encodeFormat.isTestPS) {
        //we've gotten 5MB on our testTS run, so looks good.  Mark it and finish up...
        [tiVoManager setFailedPS:NO forChannelNamed: self.show.stationCallsign];
        [connection cancel];
        [self connectionDidFinishLoading:connection];
        return;
    }
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
		[self.bufferFileWriteHandle writeData:data];
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
    if (challenge.proposedCredential) {
        DDLogMajor(@"Using proposed Credential for %@",self.show.tiVoName);
        [challenge.sender useCredential:challenge.proposedCredential forAuthenticationChallenge:challenge];
    } else {
        if (self.show.tiVo.mediaKey.length) {
            DDLogMajor(@"Sending media Key for %@",self.show.tiVoName);
            [challenge.sender useCredential:[NSURLCredential credentialWithUser:@"tivo" password:self.show.tiVo.mediaKey persistence:NSURLCredentialPersistenceForSession] forAuthenticationChallenge:challenge];
            
        } else {
            [challenge.sender cancelAuthenticationChallenge:challenge];
            DDLogMajor(@"No MAK, so failing URL Authentication %@",self.show.tiVoName);
            if (self.activeURLConnection) {
                [self.activeURLConnection cancel];
                self.activeURLConnection = nil;
            }
            if (self.bufferFileWriteHandle) {
                [self.bufferFileWriteHandle closeFile];
                self.bufferFileWriteHandle = nil;
            }
            [self rescheduleOnMain];
        }
    }
    
}

//- (BOOL)connection:(NSURLConnection *)connection canAuthenticateAgainstProtectionSpace:(NSURLProtectionSpace *)protectionSpace {
//    return YES;
//}
//
//- (void)connection:(NSURLConnection *)connection didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge {
//    //    [challenge.sender useCredential:[NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust] forAuthenticationChallenge:challenge];
//    DDLogDetail(@"Show password check");
//    [challenge.sender useCredential:[NSURLCredential credentialWithUser:@"tivo" password:self.show.tiVo.mediaKey persistence:NSURLCredentialPersistenceForSession] forAuthenticationChallenge:challenge];
//    [challenge.sender continueWithoutCredentialForAuthenticationChallenge:challenge];
//}

-(void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error
{
    DDLogMajor(@"URL Connection Failed with error %@",[error maskMediaKeys]);
   if (self.activeURLConnection) {
        [self.activeURLConnection cancel];
        self.activeURLConnection = nil;
    }
    if (self.bufferFileWriteHandle) {
		[self.bufferFileWriteHandle closeFile];
        self.bufferFileWriteHandle = nil;
	}
	[self rescheduleOnMain];
}

#define kMTMinTiVoFileSize 100000
-(void)connectionDidFinishLoading:(NSURLConnection *)connection
{
	if (self.bufferFileWriteHandle) {
		[self.bufferFileWriteHandle closeFile];
        self.bufferFileWriteHandle   = nil;
	}
    if (self.isCanceled) return;
    //Make sure to flush the last of the buffer file into the pipe and close it.
    @synchronized(self) {
        self.activeURLConnection = nil;
        if (!self.writingData) {
            DDLogVerbose (@"writing last data for %@",self);
            self.writingData = YES;
            [self performSelectorInBackground:@selector(writeData) withObject:nil];
        }
    }
	self.show.tiVo.lastDownloadEnded = [NSDate date];
    double downloadedFileSize = self.totalDataDownloaded;
    //Check to make sure a reasonable file size in case there was a problem.
	if (downloadedFileSize < kMTMinTiVoFileSize) { //Not a good download - reschedule
        DDLogMajor(@"For show %@, only received %0.0f bytes",self.show, downloadedFileSize);
        NSString *dataReceived = nil;
        if (self.urlBuffer) {
            dataReceived = [[NSString alloc] initWithData:self.urlBuffer encoding:NSUTF8StringEncoding];
        } else {
            dataReceived = [NSString stringWithContentsOfFile:self.bufferFilePath encoding:NSUTF8StringEncoding error:nil];
        }
		if (dataReceived) {
			NSRange noRecording = [dataReceived rangeOfString:@"recording not found" options:NSCaseInsensitiveSearch];
			if (noRecording.location != NSNotFound) { //This is a missing recording
				DDLogMajor(@"Deleted TiVo show; marking %@",self);
				self.downloadStatus = [NSNumber numberWithInt: kMTStatusDeleted];
                [NSNotificationCenter postNotificationNameOnMainThread:kMTNotificationShowDownloadWasCanceled object:self.show.tiVo afterDelay:kMTTiVoAccessDelay];
                [self.show.tiVo scheduleNextUpdateAfterDelay:0];
				return;
            } else {
                NSRange serverBusy = [dataReceived rangeOfString:@"Server Busy" options:NSCaseInsensitiveSearch];
                if (serverBusy.location != NSNotFound) { //TiVo is overloaded
                    [tiVoManager  notifyWithTitle: @"TiVo Warning: Server Busy."
                                         subTitle: [NSString stringWithFormat: @"If this recurs, your TiVo (%@) may need to be restarted.", self.show.tiVoName ] forNotification:kMTGrowlPossibleProblem];
                    DDLogMajor(@"Warning Server Busy %@", self);
                    [self performSelector:@selector(rescheduleShowWithDecrementRetries:) withObject:@(NO) afterDelay:0];
                    return;
                }
            }
		}
		DDLogMajor(@"Downloaded file  too small - rescheduling; File sent was %@",dataReceived);
		[self performSelector:@selector(rescheduleShowWithDecrementRetries:) withObject:@(NO) afterDelay:0];
	} else {
//		NSLog(@"File size before reset %lf %lf",self.show.fileSize,downloadedFileSize);
        DDLogDetail(@"finished loading TiVo file");
		if ((downloadedFileSize < self.show.fileSize * 0.9f && !self.useTransportStream) ||
            downloadedFileSize < self.show.fileSize * 0.8f ) {  //hmm, doesn't look like it's big enough  (90% for PS; 80% for TS
            BOOL foundAudio = self.shouldSimulEncode ? [self checkLogForAudio: self.encodeTask.errorFilePath] : NO; //see if it's a audio-only file (i.e. trashed)
            if ( self.encodeFormat.isTestPS) {
                // if a test, then we only try once.
                if (!self.isDone) {
                    if (foundAudio) {
                        self.processProgress = 0.0;
                       [self setValue:[NSNumber numberWithInt:kMTStatusFailed] forKeyPath:@"downloadStatus"];
                    } else {
                        self.processProgress = 1.0;
                        [self setValue:[NSNumber numberWithInt:kMTStatusDone] forKeyPath:@"downloadStatus"];
                    }
                    [self progressUpdated];
                }
                [self performSelector:@selector(rescheduleShowWithDecrementRetries:) withObject:@(NO) afterDelay:0];
           } else if (foundAudio) {
                //On a regular file, throw away audio-only file and try again
               [self deleteVideoFile];
               [self performSelector:@selector(rescheduleShowWithDecrementRetries:) withObject:@(NO) afterDelay:0];
            } else {
                DDLogMajor(@"Show %@ supposed to be %0.0f bytes, actually %0.0f bytes (%0.1f%%)", self.show,self.show.fileSize, downloadedFileSize, downloadedFileSize / self.show.fileSize);
                if (self.shouldSimulEncode || self.useTransportStream) {
                    [tiVoManager  notifyWithTitle: @"Warning: Show may be damaged/incomplete."
                                 subTitle:self.show.showTitle forNotification:kMTGrowlPossibleProblem];
                    if (self.shouldSimulEncode) {
                        [self setValue:[NSNumber numberWithInt:kMTStatusEncoding] forKeyPath:@"downloadStatus"];
                    }
                }
            }
		} else {
            if (self.shouldSimulEncode ) {
                [self setValue:[NSNumber numberWithInt:kMTStatusEncoding] forKeyPath:@"downloadStatus"];
            }
			self.show.fileSize = downloadedFileSize;  //More accurate file size
            if ([self.bufferFileReadHandle isKindOfClass:[NSFileHandle class]]) {
                if ([[self.bufferFilePath substringFromIndex:self.bufferFilePath.length-4] compare:@"tivo"] == NSOrderedSame  && !self.isCanceled) { //We finished a complete download so mark it so
                    [self markCompleteCTiVoFile:self.bufferFilePath];
                }
            }
		}
        [NSNotificationCenter postNotificationNameOnMainThread:kMTNotificationDetailsLoaded object:self.show];
        //        [NSNotificationCenter postNotificationNameOnMainThread:kMTNotificationDownloadRowChanged object:self];
 //		NSLog(@"File size after reset %lf %lf",self.show.fileSize,downloadedFileSize);

        [NSNotificationCenter postNotificationNameOnMainThread:kMTNotificationTransferDidFinish object:self.show.tiVo afterDelay:kMTTiVoAccessDelay];
//        bufferFileReadHandle = nil;
	}
}


#pragma mark - Convenience methods

-(BOOL) canSimulEncode {
    return self.encodeFormat.canSimulEncode;
}

-(BOOL) shouldSimulEncode {
    return (self.encodeFormat.canSimulEncode && !self.shouldSkipCommercials);// && !self.downloadingShowFromMPGFile);
}

-(BOOL) canSkipCommercials {
    return self.encodeFormat.comSkip.boolValue;
}

-(BOOL) shouldSkipCommercials {
    return self.skipCommercials &&
    ([tiVoManager commercialsForChannel:self.show.stationCallsign] == NSOnState);
}

-(BOOL) canMarkCommercials {
    return self.encodeFormat.canMarkCommercials;
}

-(BOOL) shouldMarkCommercials
{
    return (self.encodeFormat.canMarkCommercials &&
            self.markCommercials &&
            ([tiVoManager commercialsForChannel:self.show.stationCallsign] == NSOnState));
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

-(NSNumber *)downloadIndex
{
	NSInteger index = [tiVoManager.downloadQueue indexOfObject:self];
	return [NSNumber numberWithInteger:index+1];
}


-(NSString *) showStatus {
	switch (self.downloadStatus.intValue) {
		case  kMTStatusNew :				return @"";
        case  kMTStatusWaiting :            return @"Waiting";
        case  kMTStatusDownloading :		return @"Downloading";
		case  kMTStatusDownloaded :			return @"Downloaded";
		case  kMTStatusDecrypting :			return @"Decrypting";
		case  kMTStatusDecrypted :			return @"Decrypted";
		case  kMTStatusCommercialing :		return @"Detecting Ads";
		case  kMTStatusCommercialed :		return @"Ads Detected";
		case  kMTStatusEncoding :			return @"Encoding";
		case  kMTStatusEncoded :			return @"Encoded";
        case  kMTStatusAddingToItunes:		return @"Adding To iTunes";
		case  kMTStatusDone :				return @"Complete";
		case  kMTStatusCaptioned:			return @"Subtitled";
		case  kMTStatusCaptioning:			return @"Subtitling";
		case  kMTStatusDeleted :			return @"TiVo Deleted";
		case  kMTStatusFailed :				return @"Failed";
		case  kMTStatusMetaDataProcessing:	return @"Adding MetaData";
		default: return @"";
	}
}

-(NSInteger) downloadStatusSorter {
//used to put column in right order  (hack due to adding kMTStatusWaiting as -1 to avoid fixing up queues)
//#define kMTStatusWaiting -1   //should reorder someday, but persistent queue stores these values in prefs
//#define kMTStatusNew 0
//#define kMTStatusDownloading 1
//also sorts Done/Failed together

    NSInteger status = self.downloadStatus.integerValue;
    if (status >= kMTStatusDone) {
        status = kMTStatusDone;
    }
     if (status >= kMTStatusDownloading) {
        return status+1;
    } else if (status == kMTStatusWaiting) {
        return 1;
    } else {  //new
        return status;
    }
}

-(NSString *) imageString {
	if (self.downloadStatus.intValue == kMTStatusDeleted) {
		return @"deleted";
	} else {
		return self.show.imageString;
	}
}

-(void) setEncodeFormat:(MTFormat *) encodeFormat {
    if (_encodeFormat != encodeFormat ) {
        BOOL iTunesWasDisabled = ![self canAddToiTunes];
        BOOL skipWasDisabled = ![self canSkipCommercials];
        BOOL markWasDisabled = ![self canMarkCommercials];
        _encodeFormat = encodeFormat;
        if (!self.canAddToiTunes && self.shouldAddToiTunes) {
            //no longer possible
            self.addToiTunesWhenEncoded = NO;
        } else if (iTunesWasDisabled && [self canAddToiTunes]) {
            //newly possible, so take user default
            self.addToiTunesWhenEncoded = [[NSUserDefaults standardUserDefaults] boolForKey:kMTiTunesSubmit];
        }
        if (!self.canSkipCommercials && self.shouldSkipCommercials) {
            //no longer possible
            self.skipCommercials = NO;
        } else if (skipWasDisabled && [self canSkipCommercials]) {
            //newly possible, so take user default
            self.skipCommercials = [[NSUserDefaults standardUserDefaults] boolForKey:@"RunComSkip"];
        }
        if (!self.canMarkCommercials && self.markCommercials) {
            //no longer possible
            self.markCommercials = NO;
        } else if (markWasDisabled && [self canMarkCommercials]) {
            //newly possible, so take user default
            self.markCommercials = [[NSUserDefaults standardUserDefaults] boolForKey:@"MarkCommercials"];
        }
    }
}


#pragma mark - Memory Management

-(void)dealloc
{
    self.encodeFormat = nil;
    if (_progressTimer) {
        [_progressTimer invalidate];
        _progressTimer = nil;
    }
	[self removeObserver:self forKeyPath:@"downloadStatus"];
	[[NSNotificationCenter defaultCenter] removeObserver:self];
    [self deallocDownloadHandling];
	
}

-(NSString *)description
{
    return [NSString stringWithFormat:@"%@ (%@)%@",self.show.showTitle,self.show.tiVoName,[self.show.protectedShow boolValue]?@"-Protected":@""];
}


@end

