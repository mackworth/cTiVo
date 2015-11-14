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

@interface MTDownload () {
	
	NSFileHandle  *bufferFileWriteHandle;
    id bufferFileReadHandle;
    
    NSFileHandle *taskChainInputHandle;
	
    NSString *commercialFilePath, *nameLockFilePath, *captionFilePath; //Files shared between tasks
	
	NSURLConnection *activeURLConnection;
	BOOL volatile writingData, downloadingURL;

    //these vars used for watchdog "checkStillActive"
    NSDate *previousCheck, *progressAt100Percent;
	double previousProcessProgress;

    NSMutableData *urlBuffer;
    ssize_t urlReadPointer;
	
}

@property (nonatomic, readonly) NSString *downloadDir;
@property (strong, nonatomic) NSString *keywordPathPart; // any extra layers of directories due to keyword template

@property (nonatomic) MTTask *decryptTask, *encodeTask, *commercialTask, *captionTask;

@property (nonatomic, readonly) int taskFlowType;
@property (nonatomic, strong) NSDate *startTime;
@property (nonatomic, assign) double startProgress;
@property (nonatomic, strong) NSTimer * progressTimer;
@property (nonatomic, assign) int numZeroSpeeds;

@end

@implementation MTDownload


@synthesize encodeFilePath   = _encodeFilePath,
downloadFilePath = _downloadFilePath,
bufferFilePath   = _bufferFilePath;

__DDLOGHERE__

-(id)init
{
    self = [super init];
    if (self) {
// 		decryptFilePath = nil;
        commercialFilePath = nil;
		nameLockFilePath = nil;
        captionFilePath = nil;
		_addToiTunesWhenEncoded = NO;
//        _simultaneousEncode = YES;
		writingData = NO;
		downloadingURL = NO;
		_genTextMetaData = nil;
#ifndef deleteXML
		_genXMLMetaData = nil;
		_includeAPMMetaData = nil;
#endif
		_exportSubtitles = nil;
        urlReadPointer = 0;
		
        [self addObserver:self forKeyPath:@"downloadStatus" options:NSKeyValueObservingOptionNew context:nil];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(formatMayHaveChanged) name:kMTNotificationFormatListUpdated object:nil];
        previousCheck = [NSDate date];
    }
    return self;
}

-(void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
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

-(void) launchPerformanceTimer:(NSTimer *) timer {
    //start Timer after 5 seconds
    self.progressTimer = [NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(updatePerformance:) userInfo:nil repeats:YES];
    self.startTime = [NSDate date];
    self.startProgress = self.processProgress;
    DDLogVerbose(@"creating timer");
}

-(void) cancelPerformanceTimer {
    if (self.progressTimer){
        [self.progressTimer invalidate]; self.progressTimer = nil;
        self.startTime = nil;
        DDLogVerbose(@"cancelling timer");
    }
}

-(void) updatePerformance: (NSTimer *) timer {
    if (self.startTime == nil) {
        [self cancelPerformanceTimer];
    } else {
        NSTimeInterval timeSoFar = -[self.startTime timeIntervalSinceNow];
        double recentSpeed =  self.show.fileSize * (_processProgress-self.startProgress)/timeSoFar;
        if (recentSpeed < 0.0) recentSpeed = 0.0;
        if (recentSpeed == 0.0) {
            self.numZeroSpeeds ++;
        } else {
            self.numZeroSpeeds = 0;
        }
        if (self.numZeroSpeeds > 3) {
            //not getting much data; hide meter
            _speed = 0.0;
        } else if (_speed <= 0.0) {
            _speed = recentSpeed;
        } else {
            const double kSMOOTHING_FACTOR = 0.03;
            double newSpeed = kSMOOTHING_FACTOR * recentSpeed + (1-kSMOOTHING_FACTOR) * _speed;
            DDLogVerbose(@"Speed was %0.1f; is %0.1f; ==> %0.1f",_speed/1000, recentSpeed/1000, newSpeed/1000);
            _speed = newSpeed; //exponential decay on older average
        }
        self.startTime = [NSDate date];
        self.startProgress = self.processProgress;
        [self progressUpdated];  //should this be the only one?
    }
}

-(NSTimeInterval) timeLeft {
    if (!self.isInProgress) return 0.0;
    double mySpeed = self.speed;
    if (mySpeed == 0.0) return 0.0;
    return self.show.fileSize *(1-_processProgress) /mySpeed;
}


-(void)saveCurrentLogFiles
{
    if (_downloadStatus.intValue == kMTStatusDownloading) {
        DDLogMajor(@"%@ downloaded %ld of %f bytes; %ld%%",self,totalDataDownloaded, _show.fileSize, lround(_processProgress*100));
    }
    for (NSArray *tasks in _activeTaskChain.taskArray) {
        for (MTTask *task in tasks) {
            [task saveLogFile];
        }
    }
}

//-(void) saveLogFile: (NSFileHandle *) logHandle {
//	if (ddLogLevel >= LOG_LEVEL_DETAIL) {
//		unsigned long long logFileSize = [logHandle seekToEndOfFile];
//		NSInteger backup = 2000;  //how much to log
//		if (logFileSize < backup) backup = (NSInteger)logFileSize;
//		[logHandle seekToFileOffset:(logFileSize-backup)];
//		NSData *tailOfFile = [logHandle readDataOfLength:backup];
//		if (tailOfFile.length > 0) {
//			NSString * logString = [[NSString alloc] initWithData:tailOfFile encoding:NSUTF8StringEncoding];
//			DDLogDetail(@"logFile: %@",  logString);
//		}
//	}
//}

//-(void) saveCurrentLogFile {
//	switch (_downloadStatus.intValue) {
//		case  kMTStatusDownloading : {
//			if (self.simultaneousEncode) {
//				DDLogMajor(@"%@ simul-downloaded %f of %f bytes; %ld%%",self,dataDownloaded, _show.fileSize, lround(_processProgress*100));
//				NSFileHandle * logHandle = [NSFileHandle fileHandleForReadingAtPath:encodeLogFilePath] ;
//				[self saveLogFile:logHandle];
//			} else {
//				DDLogMajor(@"%@ downloaded %f of %f bytes; %ld%%",self,dataDownloaded, _show.fileSize, lround(_processProgress*100));
//				[self saveLogFile:encodeLogFileReadHandle];
//				NSFileHandle * logHandle = [NSFileHandle fileHandleForReadingAtPath:encodeErrorFilePath] ;
//				[self saveLogFile:logHandle];
//				
//			}
//			break;
//		}
//		case  kMTStatusDecrypting : {
//			[self saveLogFile: decryptLogFileReadHandle];
//			break;
//		}
//		case  kMTStatusCommercialing :{
//			[self saveLogFile: commercialLogFileReadHandle];
//			break;
//		}
//		case  kMTStatusCaptioning :{
//			//			[self saveLogFile: captionLogFileReadHandle];
//			break;
//		}
//		case  kMTStatusEncoding :{
//			[self saveLogFile: encodeLogFileReadHandle];
//			break;
//		}
//		case  kMTStatusMetaDataProcessing :{
//			//			[self saveLogFile: apmLogFileReadHandle];
//			break;
//		}
//		default: {
//			DDLogMajor (@"%@ Strange failure;",self );
//		}
//			
//			
//	}
//}
//

-(void)rescheduleShowWithDecrementRetries:(NSNumber *)decrementRetries
{
	if (_isRescheduled) {
		return;
	}
	_isRescheduled = YES;
	[self saveCurrentLogFiles];
	[self cancel];
	DDLogMajor(@"Stalled at %@, %@ download of %@ with progress at %lf with previous check at %@",self.showStatus,(_numRetriesRemaining > 0) ? @"restarting":@"canceled",  _show.showTitle, _processProgress, previousCheck );
    if (_downloadStatus.intValue == kMTStatusDone) {
        self.baseFileName = nil;
    }
    if (_downloadStatus.intValue == kMTStatusDeleted) {
        _numRetriesRemaining = 0;
        _processProgress = 1.0;
        [self progressUpdated];
        [tiVoManager  notifyWithTitle: @"TiVo deleted program; download cancelled."
                             subTitle:self.show.showTitle forNotification:kMTGrowlEndDownload];
    } else if (([decrementRetries boolValue] && _numRetriesRemaining <= 0) ||
		(![decrementRetries boolValue] && _numStartupRetriesRemaining <=0)) {
		[self setValue:[NSNumber numberWithInt:kMTStatusFailed] forKeyPath:@"downloadStatus"];
		_processProgress = 1.0;
        [self progressUpdated];
		[tiVoManager  notifyWithTitle: @"TiVo show failed; cancelled."
							 subTitle:self.show.showTitle forNotification:kMTGrowlEndDownload];
		
	} else {
		if ([decrementRetries boolValue]) {
			_numRetriesRemaining--;
			[tiVoManager  notifyWithTitle:@"TiVo show failed; retrying..." subTitle:self.show.showTitle forNotification:kMTGrowlCantDownload];
			DDLogDetail(@"Decrementing retries to %ld",(long)_numRetriesRemaining);
		} else {
            _numStartupRetriesRemaining--;
			DDLogDetail(@"Decrementing startup retries to %@",@(_numStartupRetriesRemaining));
		}
		[self setValue:[NSNumber numberWithInt:kMTStatusNew] forKeyPath:@"downloadStatus"];
	}
    [NSNotificationCenter postNotificationNameOnMainThread:kMTNotificationDownloadQueueUpdated object:self.show.tiVo afterDelay:4.0];

}

#pragma mark - Queue encoding/decoding methods for persistent queue, copy/paste, and drag/drop

- (void) encodeWithCoder:(NSCoder *)encoder {
	//necessary for cut/paste drag/drop. Not used for persistent queue, as we like having english readable pref lists
	//keep parallel with queueRecord
	DDLogVerbose(@"encoding %@",self);
	[self.show encodeWithCoder:encoder];
	[encoder encodeObject:[NSNumber numberWithBool:_addToiTunesWhenEncoded] forKey: kMTSubscribediTunes];
//	[encoder encodeObject:[NSNumber numberWithBool:_simultaneousEncode] forKey: kMTSubscribedSimulEncode];
	[encoder encodeObject:[NSNumber numberWithBool:_skipCommercials] forKey: kMTSubscribedSkipCommercials];
	[encoder encodeObject:[NSNumber numberWithBool:_markCommercials] forKey: kMTSubscribedMarkCommercials];
	[encoder encodeObject:_encodeFormat.name forKey:kMTQueueFormat];
	[encoder encodeObject:_downloadStatus forKey: kMTQueueStatus];
	[encoder encodeObject: _downloadDirectory forKey: kMTQueueDirectory];
	[encoder encodeObject: _downloadFilePath forKey: kMTQueueDownloadFile] ;
	[encoder encodeObject: _bufferFilePath forKey: kMTQueueBufferFile] ;
	[encoder encodeObject: _encodeFilePath forKey: kMTQueueFinalFile] ;
	[encoder encodeObject: _genTextMetaData forKey: kMTQueueGenTextMetaData];
#ifndef deleteXML
	[encoder encodeObject: _genXMLMetaData forKey:	kMTQueueGenXMLMetaData];
	[encoder encodeObject: _includeAPMMetaData forKey:	kMTQueueIncludeAPMMetaData];
#endif
	[encoder encodeObject: _exportSubtitles forKey:	kMTQueueExportSubtitles];
}

- (NSDictionary *) queueRecord {
	//used for persistent queue, as we like having english-readable pref lists
	//keep parallel with encodeWithCoder
	//need to watch out for a nil object ending the dictionary too soon.
	DDLogDetail(@"queueRecord for %@",self);
	
	NSMutableDictionary *result = [NSMutableDictionary dictionaryWithObjectsAndKeys:
								   [NSNumber numberWithInteger: _show.showID], kMTQueueID,
								   [NSNumber numberWithBool:_addToiTunesWhenEncoded], kMTSubscribediTunes,
//								   [NSNumber numberWithBool:_simultaneousEncode], kMTSubscribedSimulEncode,
								   [NSNumber numberWithBool:_skipCommercials], kMTSubscribedSkipCommercials,
								   [NSNumber numberWithBool:_markCommercials], kMTSubscribedMarkCommercials,
								   _show.showTitle, kMTQueueTitle,
								   self.show.tiVoName, kMTQueueTivo,
								   nil];
	if (_encodeFormat.name) [result setValue:_encodeFormat.name forKey:kMTQueueFormat];
	if (_downloadStatus) [result setValue:_downloadStatus forKey:kMTQueueStatus];
	if (_downloadDirectory) [result setValue:_downloadDirectory forKey:kMTQueueDirectory];
	if (_downloadFilePath) [result setValue:_downloadFilePath forKey:kMTQueueDownloadFile];
	if (_bufferFilePath) [result setValue:_bufferFilePath forKey: kMTQueueBufferFile];
	if (_encodeFilePath) [result setValue:_encodeFilePath forKey: kMTQueueFinalFile];
	if (_genTextMetaData) [result setValue:_genTextMetaData forKey: kMTQueueGenTextMetaData];
#ifndef deleteXML
	if (_genXMLMetaData) [result setValue:_genXMLMetaData forKey: kMTQueueGenXMLMetaData];
	if (_includeAPMMetaData) [result setValue:_includeAPMMetaData forKey: kMTQueueIncludeAPMMetaData];
#endif
	if (_exportSubtitles) [result setValue:_exportSubtitles forKey: kMTQueueExportSubtitles];
	
	DDLogVerbose(@"queueRecord for %@ is %@",self,result);
	return [NSDictionary dictionaryWithDictionary: result];
}

-(BOOL) isSameAs:(NSDictionary *) queueEntry {
	NSInteger queueID = [queueEntry[kMTQueueID] integerValue];
	BOOL result = (queueID == _show.showID) && ([self.show.tiVoName compare:queueEntry[kMTQueueTivo]] == NSOrderedSame);
	if (result && [self.show.showTitle compare:queueEntry[kMTQueueTitle]] != NSOrderedSame) {
		DDLogReport(@"Very odd, but reloading anyways: same ID: %ld same TiVo:%@ but different titles: <<%@>> vs <<%@>>",queueID, queueEntry[kMTQueueTivo], self.show.showTitle, queueEntry[kMTQueueTitle] );
	}
	return result;
	
}

-(void) restoreDownloadData:queueEntry {
	self.show = [[MTTiVoShow alloc] init];
	self.show.showID   = [(NSNumber *)queueEntry[kMTQueueID] intValue];
	[self.show setShowSeriesAndEpisodeFrom: queueEntry[kMTQueueTitle]];
	self.show.tempTiVoName = queueEntry[kMTQueueTivo] ;
	self.encodeFormat = [tiVoManager findFormat: queueEntry[kMTQueueFormat]]; //bug here: will not be able to restore a no-longer existent format, so will substitue with first one available, which is wrong for completed/failed entries
	
	[self prepareForDownload:NO];
	_addToiTunesWhenEncoded = [queueEntry[kMTSubscribediTunes ]  boolValue];
	_skipCommercials = [queueEntry[kMTSubscribedSkipCommercials ]  boolValue];
	_markCommercials = [queueEntry[kMTSubscribedMarkCommercials ]  boolValue];
	_downloadStatus = queueEntry[kMTQueueStatus];
	if (_downloadStatus.integerValue == kMTStatusDoneOld) _downloadStatus = @kMTStatusDone; //temporary patch for old queues
	if (self.isInProgress) _downloadStatus = @kMTStatusNew;		//until we can launch an in-progress item
	
//	_simultaneousEncode = [queueEntry[kMTSimultaneousEncode] boolValue];
	self.downloadDirectory = queueEntry[kMTQueueDirectory];
	_encodeFilePath = queueEntry[kMTQueueFinalFile];
	_downloadFilePath = queueEntry[kMTQueueDownloadFile];
	_bufferFilePath = queueEntry[kMTQueueBufferFile];
	self.show.protectedShow = @YES; //until we matchup with show or not.
	_genTextMetaData = queueEntry[kMTQueueGenTextMetaData]; if (!_genTextMetaData) _genTextMetaData= @(NO);
#ifndef deleteXML
	_genXMLMetaData = queueEntry[kMTQueueGenXMLMetaData]; if (!_genXMLMetaData) _genXMLMetaData= @(NO);
	_includeAPMMetaData = queueEntry[kMTQueueIncludeAPMMetaData]; if (!_includeAPMMetaData) _includeAPMMetaData= @(NO);
#endif
	_exportSubtitles = queueEntry[kMTQueueExportSubtitles]; if (!_exportSubtitles) _exportSubtitles= @(NO);
	DDLogDetail(@"restored %@ with %@; inProgress",self, queueEntry);
}

- (id)initWithCoder:(NSCoder *)decoder {
	//keep parallel with updateFromDecodedShow
	if ((self = [self init])) {
		//NSString *title = [decoder decodeObjectForKey:kTitleKey];
		//float rating = [decoder decodeFloatForKey:kRatingKey];
		self.show = [[MTTiVoShow alloc] initWithCoder:decoder ];
		self.downloadDirectory = [decoder decodeObjectForKey: kMTQueueDirectory];
		_addToiTunesWhenEncoded= [[decoder decodeObjectForKey: kMTSubscribediTunes] boolValue];
//		_simultaneousEncode	 =   [[decoder decodeObjectForKey: kMTSubscribedSimulEncode] boolValue];
		_skipCommercials   =     [[decoder decodeObjectForKey: kMTSubscribedSkipCommercials] boolValue];
		_markCommercials   =     [[decoder decodeObjectForKey: kMTSubscribedMarkCommercials] boolValue];
		NSString * encodeName	 = [decoder decodeObjectForKey:kMTQueueFormat];
		_encodeFormat =	[tiVoManager findFormat: encodeName]; //minor bug here: will not be able to restore a no-longer existent format, so will substitue with first one available, which is then wrong for completed/failed entries
		_downloadStatus		 = [decoder decodeObjectForKey: kMTQueueStatus];
		_bufferFilePath = [decoder decodeObjectForKey:kMTQueueBufferFile];
		_downloadFilePath = [decoder decodeObjectForKey:kMTQueueDownloadFile];
		_encodeFilePath = [decoder decodeObjectForKey:kMTQueueFinalFile];
		_genTextMetaData = [decoder decodeObjectForKey:kMTQueueGenTextMetaData]; if (!_genTextMetaData) _genTextMetaData= @(NO);
#ifndef deleteXML
		_genXMLMetaData = [decoder decodeObjectForKey:kMTQueueGenXMLMetaData]; if (!_genXMLMetaData) _genXMLMetaData= @(NO);
		_includeAPMMetaData = [decoder decodeObjectForKey:kMTQueueIncludeAPMMetaData]; if (!_includeAPMMetaData) _includeAPMMetaData= @(NO);
#endif
		_exportSubtitles = [decoder decodeObjectForKey:kMTQueueExportSubtitles]; if (!_exportSubtitles) _exportSubtitles= @(NO);
	}
	DDLogDetail(@"initWithCoder for %@",self);
	return self;
}


-(BOOL) isEqual:(id)object {
	if (object == self) return YES;
    if (!object || ![object isKindOfClass:MTDownload.class]) {
		return NO;
	}
	MTDownload * dl = (MTDownload *) object;
	return ([self.show isEqual:dl.show] &&
			[self.encodeFormat isEqual: dl.encodeFormat] &&
			(self.downloadFilePath == dl.downloadFilePath || [self.downloadFilePath isEqualToString:dl.downloadFilePath]) &&
			(self.downloadDirectory == dl.downloadDirectory || [self.downloadDirectory isEqualToString:dl.downloadDirectory]));
	
}

-(NSUInteger) hash {
    return [self.show hash] ^
    [self.encodeFormat hash] ^
    [self.downloadFilePath hash] ^
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

- (void) formatMayHaveChanged{
	//if format list is updated, we need to ensure our format still exists
	//known bug: if name of current format changed, we will not find correct one
	self.encodeFormat = [tiVoManager findFormat:self.encodeFormat.name];
}

#pragma mark - Set up for queuing / reset
-(void)prepareForDownload: (BOOL) notifyTiVo {
	//set up initial parameters for download before submittal; can also be used to resubmit while still in DL queue
	self.show.isQueued = YES;
	if (self.isInProgress) {
		[self cancel];
	}
	_processProgress = 0.0;
	self.numRetriesRemaining = (int) [[NSUserDefaults standardUserDefaults] integerForKey:kMTNumDownloadRetries];
	self.numStartupRetriesRemaining = kMTMaxDownloadStartupRetries;
	if (!self.downloadDirectory) {
		self.downloadDirectory = tiVoManager.downloadDirectory;
	}
	[self setValue:[NSNumber numberWithInt:kMTStatusNew] forKeyPath:@"downloadStatus"];
	if (notifyTiVo) {
        [NSNotificationCenter postNotificationNameOnMainThread:kMTNotificationDownloadQueueUpdated object:self.show.tiVo afterDelay:4.0];
	}
}


#pragma mark - Download/conversion file Methods

//Method called at the beginning of the download to configure all required files and file handles

-(void)deallocDownloadHandling
{
    commercialFilePath = nil;
    commercialFilePath = nil;
    _encodeFilePath = nil;
    _bufferFilePath = nil;
    if (bufferFileReadHandle ) {
        if ([bufferFileReadHandle isKindOfClass:[NSFileHandle class]]) [bufferFileReadHandle closeFile];
        bufferFileReadHandle = nil;
    }
    if (bufferFileWriteHandle) {
        [bufferFileWriteHandle closeFile];
        bufferFileWriteHandle = nil;
    }
	
}

-(void)cleanupFiles
{
	BOOL deleteFiles = ![[NSUserDefaults standardUserDefaults] boolForKey:kMTSaveTmpFiles];
    NSFileManager *fm = [NSFileManager defaultManager];
    DDLogDetail(@"%@ cleaningup files",self.show.showTitle);
	if (nameLockFilePath) {
		if (deleteFiles) {
			DDLogVerbose(@"deleting Lockfile %@",nameLockFilePath);
			[fm removeItemAtPath:nameLockFilePath error:nil];
		}
		
	}
	//Clean up files in TmpFilesDirectory
	if (deleteFiles && self.baseFileName) {
		NSArray *tmpFiles = [fm contentsOfDirectoryAtPath:tiVoManager.tmpFilesDirectory error:nil];
		[fm changeCurrentDirectoryPath:tiVoManager.tmpFilesDirectory];
		for(NSString *file in tmpFiles){
			NSRange tmpRange = [file rangeOfString:self.baseFileName];
			if(tmpRange.location != NSNotFound) {
				DDLogVerbose(@"Deleting tmp file %@", file);
				[fm removeItemAtPath:file error:nil];
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
	NSDateComponents *components = [[NSCalendar currentCalendar]
									components:NSCalendarUnitDay | NSCalendarUnitMonth | NSCalendarUnitYear |NSCalendarUnitWeekday  |
									NSCalendarUnitMinute | NSCalendarUnitHour
											fromDate:self.show.showDate];
	 
	 NSString * originalAirDate =self.show.originalAirDateNoTime;
	 if (!originalAirDate && [components year] > 0) {
		 originalAirDate = [NSString stringWithFormat:@"%@-%@-%@",
											fourChar([components year], NO),
											twoChar([components month], YES),
											twoChar([components day], YES)];
	 }
	 NSString * monthName = [components month]> 0 ?
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
-(void)configureBaseFileNameAndDirectory {
	if (!self.baseFileName) {
		// generate only once
		NSString * baseTitle  = [_show.showTitle stringByReplacingOccurrencesOfString:@"/" withString:@"-"];
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
		if (LOG_DETAIL  && [baseTitle compare: _show.showTitle ]  != NSOrderedSame) {
			DDLogDetail(@"changed filename %@ to %@",_show.showTitle, baseTitle);
		}
		self.baseFileName = [self createUniqueBaseFileName:baseTitle inDownloadDir:self.downloadDir];
	}
}
#undef Null

-(void) markCompleteCTiVoFile:(NSString *) path {
    if (path ) {
        NSData *tiVoID = [_show.idString dataUsingEncoding:NSUTF8StringEncoding];
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
            if ([tiVoID compare:_show.idString] == NSOrderedSame) {
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
    NSString *trialEncodeFilePath = [NSString stringWithFormat:@"%@/%@%@",downloadDir,baseName,_encodeFormat.filenameExtension];
	NSString *trialLockFilePath = [NSString stringWithFormat:@"%@/%@.lck" ,tiVoManager.tmpFilesDirectory,baseName];
	_tivoFilePath = [NSString stringWithFormat:@"%@/buffer%@.tivo",tiVoManager.tmpFilesDirectory,baseName];
	_mpgFilePath = [NSString stringWithFormat:@"%@/buffer%@.mpg",tiVoManager.tmpFilesDirectory,baseName];
    BOOL tivoFileExists = [self isCompleteCTiVoFile:_tivoFilePath forFileType:@"TiVo"];
    
    _downloadingShowFromTiVoFile = tivoFileExists;

    BOOL mpgFileExists = [self isCompleteCTiVoFile: _mpgFilePath forFileType:@"MPEG"];
    if (mpgFileExists) {
         _downloadingShowFromTiVoFile = NO;
         _downloadingShowFromMPGFile = YES;
    }
	if (tivoFileExists || mpgFileExists) {  //we're using an exisiting file so start the next download
        [NSNotificationCenter postNotificationNameOnMainThread:kMTNotificationTransferDidFinish object:self.show.tiVo afterDelay:kMTTiVoAccessDelay];
	}
	if (([fm fileExistsAtPath:trialEncodeFilePath] || [fm fileExistsAtPath:trialLockFilePath]) && !tivoFileExists  && !mpgFileExists) { //If .tivo file exits assume we will use this and not download.
		NSString * nextBase;
		NSRegularExpression *ending = [NSRegularExpression regularExpressionWithPattern:@"(.*)-([0-9]+)$" options:NSRegularExpressionCaseInsensitive error:nil];
		NSTextCheckingResult *result = [ending firstMatchInString:baseName options:NSMatchingWithoutAnchoringBounds range:NSMakeRange(0, (baseName).length)];
		if (result) {
			int n = [[baseName substringWithRange:[result rangeAtIndex:2]] intValue];
			DDLogVerbose(@"found output file named %@, incrementing version number %d", baseName, n);
			nextBase = [[baseName substringWithRange:[result rangeAtIndex:1]] stringByAppendingFormat:@"-%d",n+1];
		} else {
			nextBase = [baseName stringByAppendingString:@"-1"];
			DDLogVerbose(@"found output file named %@, adding version number", nextBase);
		}
		return [self createUniqueBaseFileName:nextBase inDownloadDir:downloadDir];
		
	} else {
		DDLogDetail(@"Using baseFileName %@",baseName);
		nameLockFilePath = trialLockFilePath;
		[[NSFileManager defaultManager] createFileAtPath:nameLockFilePath contents:[NSData data] attributes:nil];  //Creating the lock file
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
    if (!_downloadingShowFromTiVoFile && !_downloadingShowFromMPGFile) {  //We need to download from the TiVo
        if ([[NSUserDefaults standardUserDefaults] boolForKey:kMTUseMemoryBufferForDownload]) {
            _bufferFilePath = [NSString stringWithFormat:@"%@/buffer%@.bin",tiVoManager.tmpFilesDirectory,self.baseFileName];
            DDLogVerbose(@"downloading to memory; buffer: %@", _bufferFilePath);
           urlBuffer = [NSMutableData new];
            urlReadPointer = 0;
            bufferFileReadHandle = urlBuffer;
        } else {
            _bufferFilePath = [NSString stringWithFormat:@"%@/buffer%@.tivo",tiVoManager.tmpFilesDirectory,self.baseFileName];
            DDLogVerbose(@"downloading to file: %@", _bufferFilePath);
            [fm createFileAtPath:_bufferFilePath contents:[NSData data] attributes:nil];
            bufferFileWriteHandle = [NSFileHandle fileHandleForWritingAtPath:_bufferFilePath];
            bufferFileReadHandle = [NSFileHandle fileHandleForReadingAtPath:_bufferFilePath];
        }
    }
    _decryptBufferFilePath = [NSString stringWithFormat:@"%@/buffer%@.mpg",tiVoManager.tmpFilesDirectory,self.baseFileName];
    DDLogVerbose(@"setting decrypt path: %@", _decryptBufferFilePath);
    if (!_downloadingShowFromMPGFile) {
        [[NSFileManager defaultManager] createFileAtPath:_decryptBufferFilePath contents:[NSData data] attributes:nil];
    }
	_encodeFilePath = [NSString stringWithFormat:@"%@/%@%@",self.downloadDir,self.baseFileName,_encodeFormat.filenameExtension];
	DDLogVerbose(@"setting encodepath: %@", _encodeFilePath);
    captionFilePath = [NSString stringWithFormat:@"%@/%@.srt",self.downloadDir ,self.baseFileName];
    DDLogVerbose(@"setting captionFilePath: %@", captionFilePath);
    
    commercialFilePath = [NSString stringWithFormat:@"%@/buffer%@.edl" ,tiVoManager.tmpFilesDirectory, self.baseFileName];  //0.92 version
    DDLogVerbose(@"setting commercialFilePath: %@", commercialFilePath);
    
	if ([[NSUserDefaults standardUserDefaults] boolForKey:kMTGetEpisodeArt]) {
       NSString * filename = [tiVoManager.tmpFilesDirectory stringByAppendingPathComponent:self.baseFileName];
        [self.show retrieveArtworkIntoFile:filename];
 	}
}

-(NSString *) encoderPath {
	NSString *encoderLaunchPath = [_encodeFormat pathForExecutable];
    if (!encoderLaunchPath) {
        DDLogDetail(@"Encoding of %@ failed for %@ format, encoder %@ not found",_show.showTitle,_encodeFormat.name,_encodeFormat.encoderUsed);
        [self setValue:[NSNumber numberWithInt:kMTStatusFailed] forKeyPath:@"downloadStatus"];
        _processProgress = 1.0;
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
	
    if (_encodeFormat.outputFileFlag.length) {
        if (_encodeFormat.encoderEarlyVideoOptions.length) [arguments addObjectsFromArray:[self getArguments:_encodeFormat.encoderEarlyVideoOptions]];
        if (_encodeFormat.encoderEarlyAudioOptions.length) [arguments addObjectsFromArray:[self getArguments:_encodeFormat.encoderEarlyAudioOptions]];
        if (_encodeFormat.encoderEarlyOtherOptions.length) [arguments addObjectsFromArray:[self getArguments:_encodeFormat.encoderEarlyOtherOptions]];
        [arguments addObject:_encodeFormat.outputFileFlag];
        [arguments addObject:outputFilePath];
		if ([_encodeFormat.comSkip boolValue] && _skipCommercials && _encodeFormat.edlFlag.length) {
			[arguments addObject:_encodeFormat.edlFlag];
			[arguments addObject:commercialFilePath];
		}
        if (_encodeFormat.inputFileFlag.length) {
            [arguments addObject:_encodeFormat.inputFileFlag];
			[arguments addObject:inputFilePath];
			if (_encodeFormat.encoderLateVideoOptions.length) [arguments addObjectsFromArray:[self getArguments:_encodeFormat.encoderLateVideoOptions]];
			if (_encodeFormat.encoderLateAudioOptions.length) [arguments addObjectsFromArray:[self getArguments:_encodeFormat.encoderLateAudioOptions]];
			if (_encodeFormat.encoderLateOtherOptions.length) [arguments addObjectsFromArray:[self getArguments:_encodeFormat.encoderLateOtherOptions]];
        } else {
			[arguments addObject:inputFilePath];
		}
    } else {
        if (_encodeFormat.encoderEarlyVideoOptions.length) [arguments addObjectsFromArray:[self getArguments:_encodeFormat.encoderEarlyVideoOptions]];
        if (_encodeFormat.encoderEarlyAudioOptions.length) [arguments addObjectsFromArray:[self getArguments:_encodeFormat.encoderEarlyAudioOptions]];
        if (_encodeFormat.encoderEarlyOtherOptions.length) [arguments addObjectsFromArray:[self getArguments:_encodeFormat.encoderEarlyOtherOptions]];
		if ([_encodeFormat.comSkip boolValue] && _skipCommercials && _encodeFormat.edlFlag.length) {
			[arguments addObject:_encodeFormat.edlFlag];
			[arguments addObject:commercialFilePath];
		}
        if (_encodeFormat.inputFileFlag.length) {
            [arguments addObject:_encodeFormat.inputFileFlag];
        }
        [arguments addObject:inputFilePath];
        if (_encodeFormat.encoderLateVideoOptions.length) [arguments addObjectsFromArray:[self getArguments:_encodeFormat.encoderLateVideoOptions]];
        if (_encodeFormat.encoderLateAudioOptions.length) [arguments addObjectsFromArray:[self getArguments:_encodeFormat.encoderLateAudioOptions]];
        if (_encodeFormat.encoderLateOtherOptions.length) [arguments addObjectsFromArray:[self getArguments:_encodeFormat.encoderLateOtherOptions]];
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
    NSString * decryptPath = [[NSBundle mainBundle] pathForAuxiliaryExecutable:@"tivodecode"];
    if (!decryptPath) { //should never happen, but did once.
        return nil;
    }
    [decryptTask setLaunchPath:decryptPath] ;
    decryptTask.successfulExitCodes = @[@0,@6];

    decryptTask.completionHandler = ^BOOL(){
        if (!self.shouldSimulEncode) {
            [self setValue:[NSNumber numberWithInt:kMTStatusDownloaded] forKeyPath:@"downloadStatus"];
            [NSNotificationCenter  postNotificationNameOnMainThread:kMTNotificationDecryptDidFinish object:nil];
            if (_decryptBufferFilePath) {
                [self markCompleteCTiVoFile: _decryptBufferFilePath ];
            }
        }
        
        [self checkDecodeLog];
		return YES;
    };
	
	decryptTask.terminationHandler = ^(){
        [self checkDecodeLog];
	};
    
    if (_downloadingShowFromTiVoFile) {
        [decryptTask setStandardError:decryptTask.logFileWriteHandle];
        decryptTask.progressCalc = ^(NSString *data){
            NSArray *lines = [data componentsSeparatedByString:@"\n"];
            data = [lines objectAtIndex:lines.count-2];
            lines = [data componentsSeparatedByString:@":"];
            double position = [[lines objectAtIndex:0] doubleValue];
            return (position/_show.fileSize);
        };
    }
    
//    decryptTask.cleanupHandler = ^(){
//        if (![[NSUserDefaults standardUserDefaults] boolForKey:kMTSaveTmpFiles]) {
//            if ([[NSFileManager defaultManager] fileExistsAtPath:_bufferFilePath]) {
//                [[NSFileManager defaultManager] removeItemAtPath:_bufferFilePath error:nil]; 
//            }
//        }
//    };

	NSArray *arguments = [NSArray arrayWithObjects:
						  [NSString stringWithFormat:@"-m%@",self.show.tiVo.mediaKey],
						  [NSString stringWithFormat:@"-o%@",_decryptBufferFilePath],
						  @"-v",
                          [NSString stringWithFormat:@"-"],
						  nil];
    decryptTask.requiresOutputPipe = NO;
    if (_exportSubtitles.boolValue || self.shouldSimulEncode) {  //use stdout to pipe to captions  or simultaneous encoding
        arguments = [NSMutableArray arrayWithObjects:
                     [NSString stringWithFormat:@"-m%@",_show.tiVo.mediaKey],
                     @"-v",
                     @"--",
                     @"-",
                     nil];
        decryptTask.requiresOutputPipe = YES;
        //Not using the filebuffer so remove so it can act as a flag upon completion.
        if (!_skipCommercials && !_exportSubtitles.boolValue && !_markCommercials) {
            if (![[NSUserDefaults standardUserDefaults] boolForKey:kMTSaveTmpFiles]) {
                [[NSFileManager defaultManager] removeItemAtPath:_decryptBufferFilePath error:nil];
            };
            _decryptBufferFilePath = nil;
        }
    }
    [decryptTask setArguments:arguments];
    DDLogVerbose(@"Decrypt Arguments: %@",arguments);
    _decryptTask = decryptTask;
    return _decryptTask;
}

-(MTTask *)encodeTask
{
    if (_encodeTask) {
        return _encodeTask;
    }
    MTTask *encodeTask = [MTTask taskWithName:@"encode" download:self];
    [encodeTask setLaunchPath:[self encoderPath]];
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
        if (![[NSUserDefaults standardUserDefaults] boolForKey:kMTSaveTmpFiles] && self.isCanceled) {
            if ([[NSFileManager defaultManager] fileExistsAtPath:_encodeFilePath]) {
                [[NSFileManager defaultManager] removeItemAtPath:_encodeFilePath error:nil];
            }
        }
    };
    
    encoderArgs = [self encodingArgumentsWithInputFile:@"-" outputFile:_encodeFilePath];
    
    if (!self.shouldSimulEncode)  {
        if (self.encodeFormat.canSimulEncode) {  //Need to setup up the startup for sequential processing to use the writeData progress tracking
            encodeTask.requiresInputPipe = YES;
            __block NSPipe *encodePipe = [NSPipe new];
            [encodeTask setStandardInput:encodePipe];
            encodeTask.startupHandler = ^BOOL(){
                if ([self isCompleteCTiVoFile:self.encodeFilePath forFileType:@"Encoded"]){
                    return NO;
                }
				
				if (bufferFileReadHandle && [bufferFileReadHandle isKindOfClass:[NSFileHandle class]]) {
					[bufferFileReadHandle closeFile];
				}
                bufferFileReadHandle = [NSFileHandle fileHandleForReadingAtPath:_decryptBufferFilePath];
                taskChainInputHandle = [encodePipe fileHandleForWriting];
                _processProgress = 0.0;
                previousProcessProgress = 0.0;
                totalDataRead = 0.0;
                [self progressUpdated];
                [self setValue:[NSNumber numberWithInt:kMTStatusEncoding] forKeyPath:@"downloadStatus"];
                [self performSelectorInBackground:@selector(writeData) withObject:nil];
                return YES;
            };

        } else {
            encoderArgs = [self encodingArgumentsWithInputFile:_decryptBufferFilePath outputFile:_encodeFilePath];
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
                        DDLogMajor(@"Encode progress with Rx failed for task encoder for show %@\nEncoder report: %@",self.show.showTitle, data);

                    }
                    return returnValue;
                };
            };
            encodeTask.startupHandler = ^BOOL(){
                _processProgress = 0.0;
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

-(MTTask *)captionTask  //Captioning is done in parallel with download so no progress indicators are needed.
{
    NSAssert(_exportSubtitles.boolValue,@"captionTask not requested");
    if (_captionTask) {
        return _captionTask;
    }
    MTTask *captionTask = [MTTask taskWithName:@"caption" download:self completionHandler:nil];
    [captionTask setLaunchPath:[[NSBundle mainBundle] pathForAuxiliaryExecutable:@"ccextractor" ]];
    captionTask.requiresOutputPipe = NO;
    
    if (_downloadingShowFromMPGFile) {
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
                DDLogMajor(@"Track progress with Rx failed for task caption for show %@",self.show.showTitle);
            }
			return returnValue;
        };
        if (!_encodeFormat.canSimulEncode) {
            captionTask.startupHandler = ^BOOL(){
                _processProgress = 0.0;
                [self setValue:[NSNumber numberWithInt:kMTStatusCaptioning] forKeyPath:@"downloadStatus"];
                [self progressUpdated];
                return YES;
            };
        }
    }

    
    captionTask.completionHandler = ^BOOL(){
//        [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationCaptionDidFinish object:nil];
        [self markCompleteCTiVoFile:captionFilePath];
		return YES;
    };
    
    captionTask.cleanupHandler = ^(){
        if (![[NSUserDefaults standardUserDefaults] boolForKey:kMTSaveTmpFiles] && self.isCanceled) {
            if ([[NSFileManager defaultManager] fileExistsAtPath:captionFilePath]) {
                [[NSFileManager defaultManager] removeItemAtPath:captionFilePath error:nil];
            }
        }
    };
    
    NSMutableArray * captionArgs = [NSMutableArray array];
    
    if (_encodeFormat.captionOptions.length) [captionArgs addObjectsFromArray:[self getArguments:_encodeFormat.captionOptions]];
    
    [captionArgs addObject:@"-bi"];
    [captionArgs addObject:@"-utf8"];
    [captionArgs addObject:@"-s"];
    //[captionArgs addObject:@"-debug"];
    [captionArgs addObject:@"-"];
    [captionArgs addObject:@"-o"];
    [captionArgs addObject:captionFilePath];
    DDLogVerbose(@"ccExtractorArgs: %@",captionArgs);
    [captionTask setArguments:captionArgs];
    DDLogVerbose(@"Caption Task = %@",captionTask);
    _captionTask = captionTask;
    return captionTask;
    

}

-(MTTask *)commercialTask
{
    NSAssert(_skipCommercials || _markCommercials ,@"Commercial Task not requested?");

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
			[tiVoManager  notifyWithTitle:@"Detecting Commercials Failed" subTitle:[NSString stringWithFormat:@"Not processing commercials for %@",self.show.showTitle] isSticky:YES forNotification:kMTGrowlCommercialDetFailed];

            if ([[NSFileManager defaultManager] fileExistsAtPath:commercialFilePath]) {
                [[NSFileManager defaultManager] removeItemAtPath:commercialFilePath error:nil];
            }
            NSData *zeroData = [NSData data];
            [zeroData writeToFile:commercialFilePath atomically:YES];
			_commercialTask.completionHandler();
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
				if (self.exportSubtitles.boolValue && self.skipCommercials) {
					NSArray *srtEntries = [NSArray getFromSRTFile:captionFilePath];
					NSArray *edlEntries = [NSArray getFromEDLFile:commercialFilePath];
					if (srtEntries && edlEntries) {
						NSArray *correctedSrts = [srtEntries processWithEDLs:edlEntries];
						if ([[NSUserDefaults standardUserDefaults] boolForKey:kMTSaveTmpFiles]) {
							NSString *oldCaptionPath = [[captionFilePath stringByDeletingPathExtension] stringByAppendingString:@"2.srt"];
							[[NSFileManager defaultManager] moveItemAtPath:captionFilePath toPath:oldCaptionPath error:nil];
						}
						if (correctedSrts) [correctedSrts writeToSRTFilePath:captionFilePath];
					}
				}
             } else {
                 self.processProgress = 1.0;
                 [self progressUpdated];
                 [self setValue:[NSNumber numberWithInt:kMTStatusCommercialed] forKeyPath:@"downloadStatus"];
                 [self writeMetaDataFiles];
#ifndef deleteXML
				 //                 if ( ! (self.includeAPMMetaData.boolValue && self.encodeFormat.canAcceptMetaData) ) {
#endif
                     [self finishUpPostEncodeProcessing];
//                 }
             }
            [self markCompleteCTiVoFile:captionFilePath];
            [self markCompleteCTiVoFile:commercialFilePath];
            return YES;
        };
    } else {
        commercialTask.completionHandler = ^BOOL{
            DDLogMajor(@"Finished detecting commercials in %@",self.show.showTitle);
			return YES;
        };
    }


	NSMutableArray *arguments = [NSMutableArray array];
    if (_encodeFormat.comSkipOptions.length) [arguments addObjectsFromArray:[self getArguments:_encodeFormat.comSkipOptions]];
    NSRange iniRange = [_encodeFormat.comSkipOptions rangeOfString:@"--ini="];
//	[arguments addObject:[NSString stringWithFormat: @"--output=%@",[commercialFilePath stringByDeletingLastPathComponent]]];  //0.92 version
    if (iniRange.location == NSNotFound) {
        [arguments addObject:[NSString stringWithFormat: @"--ini=%@",[[NSBundle mainBundle] pathForResource:@"comskip" ofType:@"ini"]]];
    }
    
    if ((self.taskFlowType == kMTTaskFlowSimuMarkcom || self.taskFlowType == kMTTaskFlowSimuMarkcomSubtitles) && [self canPostDetectCommercials]) {
        [arguments addObject:_encodeFilePath]; //Run on the final file for these conditions
        commercialFilePath = [NSString stringWithFormat:@"%@/%@.edl" ,tiVoManager.tmpFilesDirectory, self.baseFileName];  //0.92 version
   } else {
        [arguments addObject:_decryptBufferFilePath];// Run this on the output of tivodecode
    }
	DDLogVerbose(@"comskip Path: %@",[[NSBundle mainBundle] pathForAuxiliaryExecutable:@"comskip" ]);
	DDLogVerbose(@"comskip args: %@",arguments);
	[commercialTask setArguments:arguments];
    _commercialTask = commercialTask;
    return _commercialTask;
  
}

-(int)taskFlowType
{
  return (int)_exportSubtitles.boolValue + 2 * (int)_encodeFormat.canSimulEncode + 4 * (int) _skipCommercials + 8 * (int) _markCommercials;
}


-(void)download
{
	NSUserDefaults * defaults = [NSUserDefaults standardUserDefaults];
	DDLogMajor(@"Starting %d download for %@; Format: %@; %@%@%@%@%@%@%@%@%@%@",
				self.taskFlowType,
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
					@" No TVDB art;"				
				);
	_isCanceled = NO;
	_isRescheduled = NO;
    _downloadingShowFromTiVoFile = NO;
    _downloadingShowFromMPGFile = NO;
    progressAt100Percent = nil;  //Reset end of progress failure delay
    //Before starting make sure the encoder is OK.
	if (![self encoderPath]) {
        [NSNotificationCenter postNotificationNameOnMainThread:kMTNotificationShowDownloadWasCanceled object:nil];  //Decrement num encoders right away
		return;
	}
	DDLogVerbose(@"encoder is %@",[self encoderPath]);
	
    [self setValue:[NSNumber numberWithInt:kMTStatusDownloading] forKeyPath:@"downloadStatus"];
    
    //Tivodecode is always run.  The output of the tivodecode task will always to to a file to act as a buffer for differeing download and encoding speeds.
    //The file will be a mpg file in the tmp directory (the buffer file path)
    
    [self configureFiles];
    
    //decrypt task is a special task as it is always run and always to a file due to buffering requirement for the URL connection to the Tivo.
    //It shoul not be part of the processing chain.
    
    self.activeTaskChain = [MTTaskChain new];
    self.activeTaskChain.download = self;
    if (!_downloadingShowFromMPGFile && !_downloadingShowFromTiVoFile) {
        NSPipe *taskInputPipe = [NSPipe pipe];
        self.activeTaskChain.dataSource = taskInputPipe;
        taskChainInputHandle = [taskInputPipe fileHandleForWriting];
    } else if (_downloadingShowFromTiVoFile) {
        self.activeTaskChain.dataSource = _tivoFilePath;
        DDLogMajor(@"Downloading from file tivo file %@",_tivoFilePath);
    } else if (_downloadingShowFromMPGFile) {
        DDLogMajor(@"Downloading from file MPG file %@",_mpgFilePath);
        self.activeTaskChain.dataSource = _mpgFilePath;
    }
	
    NSMutableArray *taskArray = [NSMutableArray array];
	
	if (!_downloadingShowFromMPGFile) {
        MTTask * decryptTask = self.decryptTask;
        if (decryptTask) {
            [taskArray addObject:@[decryptTask]];
        } else {
            [tiVoManager  notifyWithTitle:@"Can't Find tivodecode" subTitle:[NSString stringWithFormat:@"Please go to cTiVo site for help! %@",self.show.showTitle] isSticky:YES forNotification:kMTGrowlTivodecodeFailed];
            DDLogReport(@"Fatal Error: tivodecode not found???");
            [NSNotificationCenter postNotificationNameOnMainThread:kMTNotificationShowDownloadWasCanceled object:nil];  //Decrement num encoders right away
            return;
        }
    }

    switch (self.taskFlowType) {
        case kMTTaskFlowNonSimu:  //Just encode with non-simul encoder
        case kMTTaskFlowSimu:  //Just encode with simul encoder
           [taskArray addObject:@[self.encodeTask]];
            break;
            
        case kMTTaskFlowNonSimuSubtitles:  //Encode with non-simul encoder and subtitles
            if(_downloadingShowFromMPGFile) {
                [taskArray addObject:@[self.captionTask]];
            } else {
                [taskArray addObject:@[self.captionTask,[self catTask:_decryptBufferFilePath]]];
            }
			[taskArray addObject:@[self.encodeTask]];
            break;
            
        case kMTTaskFlowSimuSubtitles:  //Encode with simul encoder and subtitles
            if(_downloadingShowFromMPGFile)self.activeTaskChain.providesProgress = YES;
			[taskArray addObject:@[self.encodeTask,self.captionTask]];
            break;
            
        case kMTTaskFlowNonSimuSkipcom:  //Encode with non-simul encoder skipping commercials
        case kMTTaskFlowSimuSkipcom:  //Encode with simul encoder skipping commercials
			[taskArray addObject:@[self.commercialTask]];
            [taskArray addObject:@[self.encodeTask]];
            break;
            
        case kMTTaskFlowNonSimuSkipcomSubtitles:  //Encode with non-simul encoder skipping commercials and subtitles
        case kMTTaskFlowSimuSkipcomSubtitles:  //Encode with simul encoder skipping commercials and subtitles
			[taskArray addObject:@[self.captionTask,[self catTask:_decryptBufferFilePath]]];
			[taskArray addObject:@[self.commercialTask]];
			[taskArray addObject:@[self.encodeTask]];
            break;
            
        case kMTTaskFlowNonSimuMarkcom:  //Encode with non-simul encoder marking commercials
            [taskArray addObject:@[self.encodeTask, self.commercialTask]];
            break;
            
        case kMTTaskFlowNonSimuMarkcomSubtitles:  //Encode with non-simul encoder marking commercials and subtitles
            if(_downloadingShowFromMPGFile) {
                assert(self.captionTask);
                [taskArray addObject:@[self.captionTask]];
            } else {
                [taskArray addObject:@[self.captionTask,[self catTask:_decryptBufferFilePath]]];
            }
            [taskArray addObject:@[self.encodeTask, self.commercialTask]];
            break;
            
        case kMTTaskFlowSimuMarkcom:  //Encode with simul encoder marking commercials
            if(_downloadingShowFromMPGFile) {
                [taskArray addObject:@[self.encodeTask]];
            } else {
                if ([self canPostDetectCommercials]) {
                    [taskArray addObject:@[self.encodeTask]];
                } else {
                    [taskArray addObject:@[self.encodeTask,[self catTask:_decryptBufferFilePath] ]];
                }
            }
            [taskArray addObject:@[self.commercialTask]];
           break;
            
        case kMTTaskFlowSimuMarkcomSubtitles:  //Encode with simul encoder marking commercials and subtitles
            if(_downloadingShowFromMPGFile) {
                [taskArray addObject:@[self.captionTask,self.encodeTask]];
            } else {
                if ([self canPostDetectCommercials]) {
                    [taskArray addObject:@[self.encodeTask, self.captionTask]];
                } else {
                    [taskArray addObject:@[self.encodeTask, self.captionTask,[self catTask:_decryptBufferFilePath]]];
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
//			[taskArray addObject:@[self.captionTask,[self catTask:_decryptBufferFilePath]]];
//			[taskArray addObject:@[self.commercialTask]];
//			[taskArray addObject:@[self.encodeTask]];
//		} else if (_encodeFormat.canSimulEncode) {
//            if(_downloadingShowFromMPGFile)self.activeTaskChain.providesProgress = YES;
//			[taskArray addObject:@[self.encodeTask,self.captionTask]];
//		} else {
//            if(_downloadingShowFromMPGFile) {
//                [taskArray addObject:@[self.captionTask]];
//            } else {
//                [taskArray addObject:@[self.captionTask,[self catTask:_decryptBufferFilePath]]];                
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
    
    totalDataRead = 0;
    totalDataDownloaded = 0;

    if (!_downloadingShowFromTiVoFile && !_downloadingShowFromMPGFile) {
        NSURLRequest *thisRequest = [NSURLRequest requestWithURL:self.show.downloadURL];
        activeURLConnection = [[NSURLConnection alloc] initWithRequest:thisRequest delegate:self startImmediately:NO] ;
        downloadingURL = YES;
    }
    _processProgress = 0.0;
	previousProcessProgress = 0.0;
    
	[self.activeTaskChain run];
	DDLogMajor(@"Starting URL %@ for show %@", _show.downloadURL,_show.showTitle);
	double downloadDelay = kMTTiVoAccessDelayServerFailure - [[NSDate date] timeIntervalSinceDate:self.show.tiVo.lastDownloadEnded];
	if (downloadDelay < 0) {
		downloadDelay = 0;
	}
	if (!_downloadingShowFromTiVoFile && !_downloadingShowFromMPGFile)
	{
		DDLogMajor(@"Will start download of %@ in %lf seconds",self.show.showTitle,downloadDelay);
		[activeURLConnection scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSRunLoopCommonModes];
		[activeURLConnection performSelector:@selector(start) withObject:nil afterDelay:downloadDelay];
	}
	[self performSelector:@selector(checkStillActive) withObject:nil afterDelay:[[NSUserDefaults standardUserDefaults] integerForKey: kMTMaxProgressDelay] + downloadDelay];
}

- (NSImage *) artworkWithPrefix: (NSString *) prefix andSuffix: (NSString *) suffix InPath: (NSString *) directory {
	prefix = [prefix lowercaseString];
	suffix = [suffix lowercaseString];
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
	NSData *tiVoName = [_show.tiVoName dataUsingEncoding:NSUTF8StringEncoding];
	NSData *tiVoID = [_show.idString dataUsingEncoding:NSUTF8StringEncoding];
	NSData *spotlightKeyword = [kMTSpotlightKeyword dataUsingEncoding:NSUTF8StringEncoding];
	setxattr([videoFilePath cStringUsingEncoding:NSASCIIStringEncoding], [kMTXATTRTiVoName UTF8String], [tiVoName bytes], tiVoName.length, 0, 0);
	setxattr([videoFilePath cStringUsingEncoding:NSASCIIStringEncoding], [kMTXATTRTiVoID UTF8String], [tiVoID bytes], tiVoID.length, 0, 0);
	setxattr([videoFilePath cStringUsingEncoding:NSASCIIStringEncoding], [kMTXATTRSpotlight UTF8String], [spotlightKeyword bytes], spotlightKeyword.length, 0, 0);
    
	[tiVoManager updateShowOnDisk:_show.showKey withPath: videoFilePath];
}


-(NSString *) moveFile:(NSString *) path ToiTunes: (NSString *)iTunesBaseName forType:(NSString *) typeString andExtension: (NSString *) extension {
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

-(void) finishUpPostEncodeProcessing {
	NSDate *startTime = [NSDate date];
	DDLogMajor(@"Starting finishing @ %@",startTime);
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(checkStillActive) object:nil];
	NSImage * artwork = nil;
	if (self.encodeFormat.canAcceptMetaData || _addToiTunesWhenEncoded) {
		//see if we can find artwork for this series
		artwork = [self findArtWork];
	}
    if (self.shouldMarkCommercials || self.encodeFormat.canAcceptMetaData || self.shouldEmbedSubtitles) {
        MP4FileHandle *encodedFile = MP4Modify([_encodeFilePath cStringUsingEncoding:NSUTF8StringEncoding],0);
		if (self.shouldMarkCommercials) {
			if ([[NSFileManager defaultManager] fileExistsAtPath:commercialFilePath]) {
				NSArray *edls = [NSArray getFromEDLFile:commercialFilePath];
				if ( edls.count > 0) {
					[edls addAsChaptersToMP4File: encodedFile forShow: _show.showTitle withLength: _show.showLength ];
				}
			}
		}
		if (self.shouldEmbedSubtitles) {
			NSArray * srtEntries = [NSArray getFromSRTFile:captionFilePath];
			if (srtEntries.count > 0) {
				[srtEntries embedSubtitlesInMP4File:encodedFile forLanguage:[MTSrt languageFromFileName:captionFilePath]];
			}
		}
		if (self.encodeFormat.canAcceptMetaData) {
            [self.show addExtendedMetaDataToFile:encodedFile withImage:artwork];
        }
		
		MP4Close(encodedFile, 0);
    }
	if (_addToiTunesWhenEncoded) {
		DDLogMajor(@"Adding to iTunes %@", self.show.showTitle);
        _processProgress = 1.0;
        [self setValue:[NSNumber numberWithInt:kMTStatusAddingToItunes] forKeyPath:@"downloadStatus"];
        [self progressUpdated];
		MTiTunes *iTunes = [[MTiTunes alloc] init];
		NSString * iTunesPath = [iTunes importIntoiTunes:self withArt:artwork] ;
		
		if (iTunesPath && ![iTunesPath isEqualToString: self.encodeFilePath]) {
			//apparently iTunes created new file
//			MP4FileHandle *iTunesFileHandle = MP4Modify([iTunesPath cStringUsingEncoding:NSUTF8StringEncoding],0);
//			const MP4Tags* tags2 = MP4TagsAlloc();
//			MP4TagsFetch( tags2, iTunesFileHandle );
//			uint32 iTunesContentID = *tags2->contentID;
//			if (iTunesContentID != realContentID) {
//				DDLogMajor(@"replacing iTunes ContentID: %u with %u",iTunesContentID, realContentID);
//				MP4TagsSetContentID(tags2, &realContentID);
//				MP4TagsStore(tags2, iTunesFileHandle);
//			}
//			MP4TagsFree(tags2);
//			MP4Close(iTunesFileHandle, 0);

			if ([[NSUserDefaults standardUserDefaults] boolForKey:kMTiTunesDelete ]) {
                //delete old file
				if (![[NSUserDefaults standardUserDefaults ] boolForKey:kMTSaveTmpFiles]) {
					if ([[NSFileManager defaultManager] removeItemAtPath:self.encodeFilePath error:nil]) {
						DDLogMajor (@"Deleting old video file %@", self.encodeFilePath);
					} else {
						DDLogReport(@"Couldn't remove file at path %@",self.encodeFilePath);
					}
				}
                //move caption, commercial, and pytivo metadata files along with video
                NSString * iTunesBaseName = [iTunesPath stringByDeletingPathExtension];
                if (self.shouldEmbedSubtitles) {
                     captionFilePath = [self moveFile:captionFilePath ToiTunes:iTunesBaseName forType:@"caption" andExtension: @"srt"] ?: captionFilePath;
                }
                if (self.shouldMarkCommercials) {
                    commercialFilePath = [self moveFile:commercialFilePath ToiTunes:iTunesBaseName forType:@"commercial" andExtension: @"edl"] ?: commercialFilePath;
                }
                if (self.genTextMetaData.boolValue) {
                    NSString * textMetaPath = [self.encodeFilePath stringByAppendingPathExtension:@"txt"];
                    NSString * doubleExtension = [[self.encodeFilePath pathExtension] stringByAppendingString:@".txt"];
                    [self moveFile:textMetaPath ToiTunes:iTunesBaseName forType:@"metadata" andExtension:doubleExtension];
                }
                //but remember new file for future processing
				_encodeFilePath= iTunesPath;
			} else {
				//two copies now, so add xattrs to iTunes copy as well; leave captions/metadata/commercials with original
				[self addXAttrs:iTunesPath];
			}
		}
	}
	[self addXAttrs:self.encodeFilePath];
//    [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationDetailsLoaded object:_show];
	DDLogVerbose(@"Took %lf seconds to complete for show %@",[[NSDate date] timeIntervalSinceDate:startTime], _show.showTitle);
	[self setValue:[NSNumber numberWithInt:kMTStatusDone] forKeyPath:@"downloadStatus"];
    [NSNotificationCenter postNotificationNameOnMainThread:kMTNotificationShowDownloadDidFinish object:self];  //Currently Free up an encoder/ notify subscription module / update UI
    _processProgress = 1.0;
	[self progressUpdated];
	[tiVoManager  notifyWithTitle:@"TiVo show transferred." subTitle:self.show.showTitle forNotification:kMTGrowlEndDownload];
	
	[self cleanupFiles];
    //Reset tasks
    _decryptTask = _captionTask = _commercialTask = _encodeTask  = nil;
}


-(void)cancel
{
    if (_isCanceled || !self.isInProgress) {
        return;
    }
    _isCanceled = YES;
    DDLogMajor(@"Canceling of %@", self.show.showTitle);
//    NSFileManager *fm = [NSFileManager defaultManager];
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    if (activeURLConnection) {
        [activeURLConnection cancel];
		self.show.tiVo.lastDownloadEnded = [NSDate date];
        activeURLConnection = nil;
	}
    if(self.activeTaskChain.isRunning) {
        [self.activeTaskChain cancel];
        self.activeTaskChain = nil;
    }
//    [[NSNotificationCenter defaultCenter] removeObserver:self name:NSFileHandleReadCompletionNotification object:bufferFileReadHandle];
    if (!self.isNew && !self.isDone ) {
        [NSNotificationCenter postNotificationNameOnMainThread:kMTNotificationShowDownloadWasCanceled object:nil];
    }
    self.decryptTask = self.captionTask = self.commercialTask = self.encodeTask  = nil;
    
	NSDate *now = [NSDate date];
    while (writingData && (-1.0 * [now timeIntervalSinceNow]) < 5.0){ //Wait for no more than 5 seconds.
        //Block until latest write data is complete - should stop quickly because isCanceled is set
        //writingData = NO;
    } //Wait for pipe out to complete
    DDLogMajor(@"Waiting %lf seconds for write data to complete during cancel", (-1.0 * [now timeIntervalSinceNow]) );
    
    [self cleanupFiles]; //Everything but the final file
    if (_downloadStatus.intValue == kMTStatusDone) {
        self.baseFileName = nil;  //Force new file for rescheduled, complete show.
    }
//    if ([_downloadStatus intValue] == kMTStatusEncoding || (_simultaneousEncode && self.isDownloading)) {
//        [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationEncodeWasCanceled object:self];
//    }
//    if ([_downloadStatus intValue] == kMTStatusCaptioning) {
//        [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationCaptionWasCanceled object:self];
//    }
//    if ([_downloadStatus intValue] == kMTStatusCommercialing) {
//        [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationCommercialWasCanceled object:self];
//    }
//    [self setValue:[NSNumber numberWithInt:kMTStatusNew] forKeyPath:@"downloadStatus"];
    if (_processProgress != 0.0 ) {
		_processProgress = 0.0;
        [self progressUpdated];
    }
    
}

#pragma mark - Download/Conversion  Progress Tracking

-(void)checkStillActive
{
    if (_isCanceled || !self.isInProgress) {
        return;
    }

    if (previousProcessProgress == _processProgress) { //The process is stalled so cancel and restart
		//Cancel and restart or delete depending on number of time we've been through this
        DDLogMajor (@"process stalled at %0.1f%%; rescheduling show %@ ", _processProgress*100.0, self.show.showTitle);
        BOOL reschedule = YES;
        if (_processProgress == 1.0) {
            reschedule = NO;
			if (!progressAt100Percent) {  //This is the first time here so record as the start of 100 % period
                DDLogMajor(@"Starting extended wait for 100%% progress stall (Handbrake) for show %@",self.show.showTitle);
                progressAt100Percent = [NSDate date];
            } else if ([[NSDate date] timeIntervalSinceDate:progressAt100Percent] > kMTProgressFailDelayAt100Percent){
                DDLogReport(@"Failed extended wait for 100%% progress stall (Handbrake) for show %@",self.show.showTitle);
                reschedule = YES;
            } else {
				DDLogVerbose(@"In extended wait for Handbrake");
			}
        }
		if (reschedule) {
			[self rescheduleShowWithDecrementRetries:@(YES)];
		} else {
			[self performSelector:@selector(checkStillActive) withObject:nil afterDelay:[[NSUserDefaults standardUserDefaults] integerForKey: kMTMaxProgressDelay]];
		}
	} else if ([self isInProgress]){
        DDLogVerbose (@"process check OK; %0.2f", _processProgress);
		previousProcessProgress = _processProgress;
		[self performSelector:@selector(checkStillActive) withObject:nil afterDelay:[[NSUserDefaults standardUserDefaults] integerForKey: kMTMaxProgressDelay]];
	}
    previousCheck = [NSDate date];
}


-(BOOL) isInProgress {
    return (!(self.isNew || self.isDone));
}

-(BOOL) isDownloading {
	return ([_downloadStatus intValue] == kMTStatusDownloading);
}

-(BOOL) isDone {
	int status = [_downloadStatus intValue];
	return (status == kMTStatusDone) ||
	(status == kMTStatusFailed) ||
	(status == kMTStatusDeleted);
}

-(BOOL) isNew {
	return ([_downloadStatus intValue] == kMTStatusNew);
}

-(void)progressUpdated
{
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
	NSURL *   URL =  [self URLExists: _encodeFilePath];
//	if (!URL) URL= [self URLExists: decryptFilePath];
	if (!URL && encrypted) URL = [self URLExists: _downloadFilePath];
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

#pragma mark - Misc Support Functions

-(void)rescheduleOnMain
{
//	_isCanceled = YES;
	[self performSelectorOnMainThread:@selector(rescheduleShowWithDecrementRetries:) withObject:@YES waitUntilDone:NO];
}

-(void)writeData
{
    // writeData supports getting its data from either an NSData buffer (urlBuffer) or a file on disk (_bufferFilePath).  This allows cTiVo to
    // initially try to keep the dataflow off the disk, except for final products, where possible.  But, the ability to do this depends on the
    // processor being able to keep up with the data flow from the TiVo which is often not the case due to either a slow processor, fast network
    // connection, of different tasks competing for processor resources.  When the processor falls too far behind and the memory buffer will
    // become too large cTiVo will fall back to using files on the disk as a data buffer.


	//	writingData = YES;
    const long chunkSize = 50000;
    long dataRead = chunkSize; //to start loop
    while (dataRead == chunkSize && !_isCanceled) {
        @autoreleasepool {
            NSData *data = nil;
			@try {
                 if (bufferFileReadHandle == urlBuffer) {
                    @synchronized(urlBuffer) {
                        long sizeToWrite = urlBuffer.length - urlReadPointer;
                        if (sizeToWrite > chunkSize) {
                            sizeToWrite = chunkSize;
                        }
                        data = [urlBuffer subdataWithRange:NSMakeRange(urlReadPointer, sizeToWrite)];
                        urlReadPointer += sizeToWrite;
                    }
                } else {
                    data = [bufferFileReadHandle readDataOfLength:chunkSize];
                }
			}
			@catch (NSException *exception) {
                if (!_isCanceled){
                    [self rescheduleOnMain];
                    DDLogDetail(@"Rescheduling");
                };
				DDLogDetail(@"buffer read fail:%@; %@", exception.reason, _show.showTitle);
			}
			@finally {
			}
            if (_isCanceled || data.length == 0) break;
            dataRead = data.length;
              //should just be following line, but it crashes program in the event of a bad pipe
              //@try
              //[taskChainInputHandle writeData:data];
              //@catch

            NSInteger numTries = 3;
            size_t bytesLeft = data.length;
            while (numTries > 0 && bytesLeft > 0) {
                ssize_t amountSent= write ([taskChainInputHandle fileDescriptor], [data bytes]+data.length-bytesLeft, bytesLeft);
                if (amountSent < 0) {
                    if (!_isCanceled){
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
                if (!_isCanceled) {
                    [self rescheduleOnMain];
                }
            }

            totalDataRead += dataRead;
            _processProgress = totalDataRead/_show.fileSize;
         }
    }
	if (!activeURLConnection || _isCanceled) {
		DDLogDetail(@"Closing taskChainHandle for show %@",self.show.showTitle);
		[taskChainInputHandle closeFile];
		DDLogDetail(@"closed filehandle");
		taskChainInputHandle = nil;
        if ([bufferFileReadHandle isKindOfClass:[NSFileHandle class]]) {
            [bufferFileReadHandle closeFile];
        }
		bufferFileReadHandle = nil;
//        if (self.shouldSimulEncode && !isCanceled) {
//            [self setValue:[NSNumber numberWithInt:kMTStatusEncoded] forKeyPath:@"downloadStatus"];
//        }
 	}
	writingData = NO;
}

#pragma mark - NSURL Delegate Methods

-(void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data
{
    totalDataDownloaded += data.length;
	if (urlBuffer) {
        // cTiVo's URL connection supports sending its data to either an NSData buffer (urlBuffer) or a file on disk (_bufferFilePath).  This allows cTiVo to 
        // initially try to keep the dataflow off the disk, except for final products, where possible.  But, the ability to do this depends on the processor 
        // being able to keep up with the data flow from the TiVo which is often not the case due to either a slow processor, fast network connection, of
        // different tasks competing for processor resources.  When the processor falls too far behind and the memory buffer will become too large
        // cTiVo will fall back to using files on the disk as a data buffer.

		@synchronized (urlBuffer){
			[urlBuffer appendData:data];
			if (urlBuffer.length > kMTMaxBuffSize) {
				DDLogMajor(@"URLBuffer length exceeded %d, switching to file based buffering",kMTMaxBuffSize);
				[[NSFileManager defaultManager] createFileAtPath:_bufferFilePath contents:[urlBuffer subdataWithRange:NSMakeRange(urlReadPointer, urlBuffer.length - urlReadPointer)] attributes:nil];
				bufferFileReadHandle = [NSFileHandle fileHandleForReadingAtPath:_bufferFilePath];
				bufferFileWriteHandle = [NSFileHandle fileHandleForWritingAtPath:_bufferFilePath];
				[bufferFileWriteHandle seekToEndOfFile];
				urlBuffer = nil;
                urlReadPointer = 0;
			}
			if (urlBuffer && urlReadPointer > kMTMaxReadPoints) {  //Only compress the buffer occasionally for better performance.  
				[urlBuffer replaceBytesInRange:NSMakeRange(0, urlReadPointer) withBytes:NULL length:0];
				urlReadPointer = 0;
			}
		};
	} else {
		[bufferFileWriteHandle writeData:data];
	}
        
	if (!writingData && (!urlBuffer || urlBuffer.length > kMTMaxPointsBeforeWrite)) {  //Minimized thread creation as it's expensive
		writingData = YES;
		[self performSelectorInBackground:@selector(writeData) withObject:nil];
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
            if (activeURLConnection) {
                [activeURLConnection cancel];
                activeURLConnection = nil;
            }
            if (bufferFileWriteHandle) {
                [bufferFileWriteHandle closeFile];
                bufferFileWriteHandle = nil;
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
   if (activeURLConnection) {
        [activeURLConnection cancel];
        activeURLConnection = nil;
    }
    if (bufferFileWriteHandle) {
		[bufferFileWriteHandle closeFile];
        bufferFileWriteHandle = nil;
	}
	[self rescheduleOnMain];
}

#define kMTMinTiVoFileSize 100000
-(void)connectionDidFinishLoading:(NSURLConnection *)connection
{
	if (bufferFileWriteHandle) {
		[bufferFileWriteHandle closeFile];
        bufferFileWriteHandle   = nil;
	}
	double downloadedFileSize = totalDataDownloaded;
	DDLogDetail(@"finished loading file");
    //Check to make sure a reasonable file size in case there was a problem.
    if (downloadedFileSize > kMTMinTiVoFileSize) {
        DDLogDetail(@"finished loading TiVo file");
        if (self.shouldSimulEncode) {
            [self setValue:[NSNumber numberWithInt:kMTStatusEncoding] forKeyPath:@"downloadStatus"];
        }
    }
    //Make sure to flush the last of the buffer file into the pipe and close it.
	if (!writingData) {
        DDLogVerbose (@"writing last data for %@",self);
        activeURLConnection = nil;
		writingData = YES;
		[self performSelectorInBackground:@selector(writeData) withObject:nil];
	}
	downloadingURL = NO;
	activeURLConnection = nil; //NOTE this MUST occur after the last call to writeData so that writeData doesn't exits before comletion of the downloaded buffer.
	self.show.tiVo.lastDownloadEnded = [NSDate date];
	if (downloadedFileSize < kMTMinTiVoFileSize) { //Not a good download - reschedule
        NSString *dataReceived = nil;
        if (urlBuffer) {
            dataReceived = [[NSString alloc] initWithData:urlBuffer encoding:NSUTF8StringEncoding];
        } else {
            dataReceived = [NSString stringWithContentsOfFile:_bufferFilePath encoding:NSUTF8StringEncoding error:nil];
        }
		if (dataReceived) {
			NSRange noRecording = [dataReceived rangeOfString:@"recording not found" options:NSCaseInsensitiveSearch];
			if (noRecording.location != NSNotFound) { //This is a missing recording
				DDLogMajor(@"Deleted TiVo show; marking %@",self);
				self.downloadStatus = [NSNumber numberWithInt: kMTStatusDeleted];
                [NSNotificationCenter postNotificationNameOnMainThread:kMTNotificationShowDownloadWasCanceled object:self.show.tiVo afterDelay:kMTTiVoAccessDelay];
                [self.show.tiVo scheduleNextUpdateAfterDelay:0];
				return;
			}
		}
		DDLogMajor(@"Downloaded file  too small - rescheduling; File sent was %@",dataReceived);
		[self performSelector:@selector(rescheduleShowWithDecrementRetries:) withObject:@(NO) afterDelay:kMTTiVoAccessDelay];
	} else {
//		NSLog(@"File size before reset %lf %lf",self.show.fileSize,downloadedFileSize);
		if (downloadedFileSize < self.show.fileSize * 0.85f) {  //hmm, doesn't look like it's big enough
			[tiVoManager  notifyWithTitle: @"Warning: Show may be damaged/incomplete."
								 subTitle:self.show.showTitle forNotification:kMTGrowlPossibleProblem];
			DDLogMajor(@"Show %@ supposed to be %f bytes, actually %f bytes", self.show,self.show.fileSize, downloadedFileSize);
		} else {
			self.show.fileSize = downloadedFileSize;  //More accurate file size
		}
        [NSNotificationCenter postNotificationNameOnMainThread:kMTNotificationDetailsLoaded object:self.show];
        //        [NSNotificationCenter postNotificationNameOnMainThread:kMTNotificationDownloadRowChanged object:self];
 //		NSLog(@"File size after reset %lf %lf",self.show.fileSize,downloadedFileSize);

        [NSNotificationCenter postNotificationNameOnMainThread:kMTNotificationTransferDidFinish object:self.show.tiVo afterDelay:kMTTiVoAccessDelay];
         if ([bufferFileReadHandle isKindOfClass:[NSFileHandle class]]) {
            if ([[_bufferFilePath substringFromIndex:_bufferFilePath.length-4] compare:@"tivo"] == NSOrderedSame  && !_isCanceled) { //We finished a complete download so mark it so
                [self markCompleteCTiVoFile:_bufferFilePath];
            }
        }
//        bufferFileReadHandle = nil;
	}
}


#pragma mark Convenience methods

-(BOOL) canSimulEncode {
    return self.encodeFormat.canSimulEncode;
}

-(BOOL) shouldSimulEncode {
    return (_encodeFormat.canSimulEncode && !_skipCommercials);// && !_downloadingShowFromMPGFile);
}

-(BOOL) canSkipCommercials {
    return self.encodeFormat.comSkip.boolValue;
}

-(BOOL) shouldSkipCommercials {
    return _skipCommercials;
}

-(BOOL) canMarkCommercials {
    return self.encodeFormat.canMarkCommercials;
}

-(BOOL) shouldMarkCommercials
{
    return (_encodeFormat.canMarkCommercials && _markCommercials);
}

-(BOOL) shouldEmbedSubtitles
{
    return (_encodeFormat.canMarkCommercials && _exportSubtitles);
}

-(BOOL) canAddToiTunes {
    return self.encodeFormat.canAddToiTunes;
}

-(BOOL) shouldAddToiTunes {
    return _addToiTunesWhenEncoded;
}

-(BOOL) canPostDetectCommercials {
    return NO; //This is not working well right now because comskip isn't handling even these formats reliably.
//	NSArray * allowedExtensions = @[@".mp4", @".m4v", @".mpg"];
//	NSString * extension = [_encodeFormat.filenameExtension lowercaseString];
//	return [allowedExtensions containsObject: extension];
}



#pragma mark - Custom Getters

-(NSNumber *)downloadIndex
{
	NSInteger index = [tiVoManager.downloadQueue indexOfObject:self];
	return [NSNumber numberWithInteger:index+1];
}


-(NSString *) showStatus {
	switch (_downloadStatus.intValue) {
		case  kMTStatusNew :				return @"";
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
        if (!self.canMarkCommercials && _markCommercials) {
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

