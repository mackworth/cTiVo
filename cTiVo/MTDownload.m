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
#include <sys/xattr.h>
#include "mp4v2.h"

typedef struct MP4Chapters_s {
    MP4Chapter_t *chapters;
    int count;
} MP4Chapters;


@interface MTDownload () {
	
	NSFileHandle  *bufferFileWriteHandle;
    id bufferFileReadHandle;
    
    NSFileHandle *taskChainInputHandle;
	
    NSString *commercialFilePath, *nameLockFilePath, *captionFilePath; //Files shared between tasks
	
	NSURLConnection *activeURLConnection;
	BOOL volatile writingData, downloadingURL;
    NSDate *previousCheck;
	double previousProcessProgress;
    NSMutableData *urlBuffer;
    ssize_t urlReadPointer;
	
}

@property (strong, nonatomic) NSString *downloadDir;

@property (nonatomic) MTTask *decryptTask, *encodeTask, *commercialTask, *captionTask;

@property (nonatomic) int taskFlowType;

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
		_genXMLMetaData = nil;
		_includeAPMMetaData = nil;
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
		DDLogVerbose(@"Changing DL status of %@ to %@ (%@)", object, [(MTDownload *)object showStatus], [(MTDownload *)object downloadStatus]);
        [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationDownloadStatusChanged object:nil];
    }
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
	if (_numRetriesRemaining <= 0 || _numStartupRetriesRemaining <=0) {
		[self setValue:[NSNumber numberWithInt:kMTStatusFailed] forKeyPath:@"downloadStatus"];
		_processProgress = 1.0;
		[[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationProgressUpdated object:nil];
		
		[tiVoManager  notifyWithTitle: @"TiVo show failed; cancelled."
							 subTitle:self.show.showTitle forNotification:kMTGrowlEndDownload];
		
	} else {
		if ([decrementRetries boolValue]) {
			_numRetriesRemaining--;
			[tiVoManager  notifyWithTitle:@"TiVo show failed; retrying..." subTitle:self.show.showTitle forNotification:kMTGrowlEndDownload];
			DDLogDetail(@"Decrementing retries to %d",_numRetriesRemaining);
		} else {
            _numStartupRetriesRemaining--;
			DDLogDetail(@"Decrementing startup retries to %d",_numStartupRetriesRemaining);
		}
		[self setValue:[NSNumber numberWithInt:kMTStatusNew] forKeyPath:@"downloadStatus"];
	}
    NSNotification *notification = [NSNotification notificationWithName:kMTNotificationDownloadQueueUpdated object:self.show.tiVo];
    [[NSNotificationCenter defaultCenter] performSelector:@selector(postNotification:) withObject:notification afterDelay:4.0];
	
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
	[encoder encodeObject: _genXMLMetaData forKey:	kMTQueueGenXMLMetaData];
	[encoder encodeObject: _includeAPMMetaData forKey:	kMTQueueIncludeAPMMetaData];
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
	if (_genXMLMetaData) [result setValue:_genXMLMetaData forKey: kMTQueueGenXMLMetaData];
	if (_includeAPMMetaData) [result setValue:_includeAPMMetaData forKey: kMTQueueIncludeAPMMetaData];
	if (_exportSubtitles) [result setValue:_exportSubtitles forKey: kMTQueueExportSubtitles];
	
	DDLogVerbose(@"queueRecord for %@ is %@",self,result);
	return [NSDictionary dictionaryWithDictionary: result];
}

-(BOOL) isSameAs:(NSDictionary *) queueEntry {
	NSInteger queueID = [queueEntry[kMTQueueID] integerValue];
	BOOL result = (queueID == _show.showID) && ([self.show.tiVoName compare:queueEntry[kMTQueueTivo]] == NSOrderedSame);
	if (result && [self.show.showTitle compare:queueEntry[kMTQueueTitle]] != NSOrderedSame) {
		NSLog(@"Very odd, but reloading anyways: same ID: %ld same TiVo:%@ but different titles: <<%@>> vs <<%@>>",queueID, queueEntry[kMTQueueTivo], self.show.showTitle, queueEntry[kMTQueueTitle] );
	}
	return result;
	
}

-(void) restoreDownloadData:queueEntry {
	self.show = [[MTTiVoShow alloc] init];
	self.show.showID   = [(NSNumber *)queueEntry[kMTQueueID] intValue];
	self.show.showTitle= queueEntry[kMTQueueTitle];
	self.show.tempTiVoName = queueEntry[kMTQueueTivo] ;
	
	[self prepareForDownload:NO];
	_addToiTunesWhenEncoded = [queueEntry[kMTSubscribediTunes ]  boolValue];
	_skipCommercials = [queueEntry[kMTSubscribedSkipCommercials ]  boolValue];
	_markCommercials = [queueEntry[kMTSubscribedMarkCommercials ]  boolValue];
	_downloadStatus = queueEntry[kMTQueueStatus];
	if (_downloadStatus.integerValue == kMTStatusDoneOld) _downloadStatus = @kMTStatusDone; //temporary patch for old queues
	if (self.isInProgress) _downloadStatus = @kMTStatusNew;		//until we can launch an in-progress item
	
//	_simultaneousEncode = [queueEntry[kMTSimultaneousEncode] boolValue];
	self.encodeFormat = [tiVoManager findFormat: queueEntry[kMTQueueFormat]]; //bug here: will not be able to restore a no-longer existent format, so will substitue with first one available, which is wrong for completed/failed entries
	self.downloadDirectory = queueEntry[kMTQueueDirectory];
	_encodeFilePath = queueEntry[kMTQueueFinalFile];
	_downloadFilePath = queueEntry[kMTQueueDownloadFile];
	_bufferFilePath = queueEntry[kMTQueueBufferFile];
	self.show.protectedShow = @YES; //until we matchup with show or not.
	_genTextMetaData = queueEntry[kMTQueueGenTextMetaData]; if (!_genTextMetaData) _genTextMetaData= @(NO);
	_genXMLMetaData = queueEntry[kMTQueueGenXMLMetaData]; if (!_genXMLMetaData) _genXMLMetaData= @(NO);
	_includeAPMMetaData = queueEntry[kMTQueueIncludeAPMMetaData]; if (!_includeAPMMetaData) _includeAPMMetaData= @(NO);
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
		_genXMLMetaData = [decoder decodeObjectForKey:kMTQueueGenXMLMetaData]; if (!_genXMLMetaData) _genXMLMetaData= @(NO);
		_includeAPMMetaData = [decoder decodeObjectForKey:kMTQueueIncludeAPMMetaData]; if (!_includeAPMMetaData) _includeAPMMetaData= @(NO);
		_exportSubtitles = [decoder decodeObjectForKey:kMTQueueExportSubtitles]; if (!_exportSubtitles) _exportSubtitles= @(NO);
	}
	DDLogDetail(@"initWithCoder for %@",self);
	return self;
}


-(BOOL) isEqual:(id)object {
	if (![object isKindOfClass:MTDownload.class]) {
		return NO;
	}
	MTDownload * dl = (MTDownload *) object;
	return ([self.show isEqual:dl.show] &&
			[self.encodeFormat isEqual: dl.encodeFormat] &&
			(self.downloadFilePath == dl.downloadFilePath || [self.downloadFilePath isEqual:dl.downloadFilePath]) &&
			(self.downloadDirectory == dl.downloadDirectory || [self.downloadDirectory isEqual:dl.downloadDirectory]));
	
}

- (id)pasteboardPropertyListForType:(NSString *)type {
	//	NSLog(@"QQQ:pboard Type: %@",type);
	if ([type compare:kMTDownloadPasteBoardType] ==NSOrderedSame) {
		return  [NSKeyedArchiver archivedDataWithRootObject:self];
	} else if ([type isEqualToString:(NSString *)kUTTypeFileURL] && self.encodeFilePath) {
		NSURL *URL = [NSURL fileURLWithPath:self.encodeFilePath isDirectory:NO];
		NSLog(@"file: %@ ==> pBoard URL: %@",self.encodeFilePath, URL);
		id temp =  [URL pasteboardPropertyListForType:(id)kUTTypeFileURL];
		return temp;
	} else {
		return nil;
	}
}
-(NSArray *)writableTypesForPasteboard:(NSPasteboard *)pasteboard {
	NSArray* result = [NSArray  arrayWithObjects: kMTDownloadPasteBoardType , kUTTypeFileURL, nil];  //NOT working yet
	//	NSLog(@"QQQ:writeable Type: %@",result);
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
	self.numRetriesRemaining = [[NSUserDefaults standardUserDefaults] integerForKey:kMTNumDownloadRetries];
	self.numStartupRetriesRemaining = kMTMaxDownloadStartupRetries;
	if (!self.downloadDirectory) {
		self.downloadDirectory = tiVoManager.downloadDirectory;
	}
	[self setValue:[NSNumber numberWithInt:kMTStatusNew] forKeyPath:@"downloadStatus"];
	if (notifyTiVo) {
		NSNotification *notification = [NSNotification notificationWithName:kMTNotificationDownloadQueueUpdated object:self.show.tiVo];
		[[NSNotificationCenter defaultCenter] performSelector:@selector(postNotification:) withObject:notification afterDelay:4.0];
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
				DDLogDetail(@"Deleting tmp file %@", file);
				[fm removeItemAtPath:file error:nil];
			}
		}
	}
}

-(NSString *) directoryForShowInDirectory:(NSString*) tryDirectory  {
	//Check that download directory (including show directory) exists.  If create it.  If unsuccessful return nil
	if ([[NSUserDefaults standardUserDefaults] boolForKey:kMTMakeSubDirs] && ![self.show isMovie]){
		tryDirectory = [tryDirectory stringByAppendingPathComponent:self.show.seriesTitle];
		DDLogVerbose(@"Opening Series-specific folder %@",tryDirectory);
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

/*
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
 
 
 
 -(NSString *) swapKeywordsInString: (NSString *) str {
 NSDictionary * keywords = @{
 @"[showTitle]": @"%$1$@",
 @"[series ]" : @"%$1$@"
 showTitle),				// %$1$@
 seriesTitle),			// %$2$@
 episodeTitle),			// %$3$@
 episodeNumber),			// %$4$@
 showDate),				// %$5$@
 showMediumDateString),	// %$6$@
 originalAirDate),		// %$7$@
 tiVoName),				// %$8$@
 idString),				// %$9$@
 channelString),			// %$10$@
 stationCallsign),		// %$11$@
 encodeFormat.name)		// %$12$@
 };
 for (NSString * key in [keywords allKeys]) {
 str = [str stringByReplacingOccurrencesOfString: key
 withString: keywords[key]
 options: NSCaseInsensitiveSearch
 range: NSMakeRange(0, [str length])];
 
 }
 return str;
 }
 */
#define Null(x) x ?  x : nullString

-(NSString *)makeBaseFileNameForDirectory:(NSString *) downloadDir {
	if (!self.baseFileName) {
		// generate only once
		NSString * baseTitle = _show.showTitle;
		NSString * filenamePattern = [[NSUserDefaults standardUserDefaults] objectForKey:kMTFileNameFormat];
		if (filenamePattern.length > 0) {
			NSString * nullString = [[NSUserDefaults standardUserDefaults] objectForKey:kMTFileNameFormatNull];
			if (!nullString) nullString = @"";
			baseTitle = [NSString stringWithFormat:filenamePattern,
						 Null(_show.showTitle),				// %$1$@  showTitle			Arrow: The Odyssey  or MovieTitle
						 Null(_show.seriesTitle),			// %$2$@  seriesTitle		Arrow or MovieTitle
						 Null(_show.episodeTitle),			// %$3$@  episodeTitle		The Odyssey or empty
						 Null(_show.episodeNumber),			// %$4$@  episodeNumber		S04 E05  or 53
						 Null(_show.showDate),				// %$5$@  showDate			Feb 10, 2013 8-00PM
						 Null(_show.showMediumDateString),	// %$6$@  showMedDate		2-10-13
						 Null(_show.originalAirDate),		// %$7$@  originalAirDate
						 Null(_show.tiVoName),				// %$8$@  tiVoName
						 Null(_show.idString),				// %$9$@  tiVoID
						 Null(_show.channelString),			// %$10$@ channelString
						 Null(_show.stationCallsign),			// %$11$@ stationCallsign
						 Null(self.encodeFormat.name)			// %$11$@ stationCallsign
						 ];
			//NEED Dates without times also Series ID
			if (baseTitle.length == 0) baseTitle = _show.showTitle;
			if (baseTitle.length > 245) baseTitle = [baseTitle substringToIndex:245];
		}
		NSString * safeTitle = [baseTitle stringByReplacingOccurrencesOfString:@"/" withString:@"-"];
		safeTitle = [safeTitle stringByReplacingOccurrencesOfString:@":" withString:@"-"];
		if (LOG_VERBOSE  && [safeTitle compare: _show.showTitle ]  != NSOrderedSame) {
			DDLogVerbose(@"changed filename %@ to %@",_show.showTitle, safeTitle);
		}
		self.baseFileName = [self createUniqueBaseFileName:safeTitle inDownloadDir:downloadDir];
	}
	return self.baseFileName;
}
#undef Null

-(NSString *)createUniqueBaseFileName:(NSString *)baseName inDownloadDir:(NSString *)downloadDir
{
	NSFileManager *fm = [NSFileManager defaultManager];
    NSString *trialEncodeFilePath = [NSString stringWithFormat:@"%@/%@%@",downloadDir,baseName,_encodeFormat.filenameExtension];
	NSString *trialLockFilePath = [NSString stringWithFormat:@"%@/%@.lck" ,tiVoManager.tmpFilesDirectory,baseName];
	_tivoFilePath = [NSString stringWithFormat:@"%@/buffer%@.tivo",tiVoManager.tmpFilesDirectory,baseName];
	_mpgFilePath = [NSString stringWithFormat:@"%@/buffer%@.mpg",tiVoManager.tmpFilesDirectory,baseName];
    BOOL tivoFileExists = NO;
    if ([fm fileExistsAtPath:_tivoFilePath]) {
        NSData *buffer = [NSData dataWithData:[[NSMutableData alloc] initWithLength:256]];
		ssize_t len = getxattr([_tivoFilePath cStringUsingEncoding:NSASCIIStringEncoding], [kMTXATTRFileComplete UTF8String], (void *)[buffer bytes], 256, 0, 0);
        if (len >=0) {
            DDLogReport(@"Found Complete TiVo File @ %@",_tivoFilePath);
            tivoFileExists = YES;
            _downloadingShowFromTiVoFile = YES;
        }
    }
    BOOL mpgFileExists = NO;
    if ([fm fileExistsAtPath:_mpgFilePath]) {
        NSData *buffer = [NSData dataWithData:[[NSMutableData alloc] initWithLength:256]];
		ssize_t len = getxattr([_mpgFilePath cStringUsingEncoding:NSASCIIStringEncoding], [kMTXATTRFileComplete UTF8String], (void *)[buffer bytes], 256, 0, 0);
        if (len >=0) {
            DDLogReport(@"Found Complete MPG File @ %@",_mpgFilePath);
            mpgFileExists = YES;
            _downloadingShowFromTiVoFile = NO;
            _downloadingShowFromMPGFile = YES;
        }
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
			DDLogDetail(@"found output file named %@, adding version number", nextBase);
		}
		return [self createUniqueBaseFileName:nextBase inDownloadDir:downloadDir];
		
	} else {
		DDLogDetail(@"Using baseFileName %@",baseName);
		nameLockFilePath = trialLockFilePath;
		[[NSFileManager defaultManager] createFileAtPath:nameLockFilePath contents:[NSData data] attributes:nil];  //Creating the lock file
		return baseName;
	}
	
}

-(NSString *)downloadDir
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
	self.baseFileName = [self makeBaseFileNameForDirectory:self.downloadDir];
    if (!_downloadingShowFromTiVoFile && !_downloadingShowFromMPGFile) {  //We need to download from the TiVo
        if ([[NSUserDefaults standardUserDefaults] boolForKey:kMTUseMemoryBufferForDownload]) {
            _bufferFilePath = [NSString stringWithFormat:@"%@/buffer%@.bin",tiVoManager.tmpFilesDirectory,self.baseFileName];
           urlBuffer = [NSMutableData new];
            urlReadPointer = 0;
            bufferFileReadHandle = urlBuffer;
        } else {
            _bufferFilePath = [NSString stringWithFormat:@"%@/buffer%@.tivo",tiVoManager.tmpFilesDirectory,self.baseFileName];
            [fm createFileAtPath:_bufferFilePath contents:[NSData data] attributes:nil];
            bufferFileWriteHandle = [NSFileHandle fileHandleForWritingAtPath:_bufferFilePath];
            bufferFileReadHandle = [NSFileHandle fileHandleForReadingAtPath:_bufferFilePath];
        }
    }
    _decryptBufferFilePath = [NSString stringWithFormat:@"%@/buffer%@.mpg",tiVoManager.tmpFilesDirectory,self.baseFileName];
    if (!_downloadingShowFromMPGFile) {
        [[NSFileManager defaultManager] createFileAtPath:_decryptBufferFilePath contents:[NSData data] attributes:nil];
    }
	_encodeFilePath = [NSString stringWithFormat:@"%@/%@%@",self.downloadDir,self.baseFileName,_encodeFormat.filenameExtension];
	DDLogVerbose(@"setting encodepath: %@", _encodeFilePath);
    captionFilePath = [NSString stringWithFormat:@"%@/%@.srt",self.downloadDir ,self.baseFileName];
    
    commercialFilePath = [NSString stringWithFormat:@"%@/buffer%@.edl" ,tiVoManager.tmpFilesDirectory, self.baseFileName];  //0.92 version

}

-(NSString *) encoderPath {
	NSString *encoderLaunchPath = [_encodeFormat pathForExecutable];
    if (!encoderLaunchPath) {
        DDLogDetail(@"Encoding of %@ failed for %@ format, encoder %@ not found",_show.showTitle,_encodeFormat.name,_encodeFormat.encoderUsed);
        [self setValue:[NSNumber numberWithInt:kMTStatusFailed] forKeyPath:@"downloadStatus"];
        _processProgress = 1.0;
        [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationProgressUpdated object:nil];
        return nil;
    } else {
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
		int j;
		for (j=1; j<tr.numberOfRanges; j++) {
			if ([tr rangeAtIndex:j].location != NSNotFound) {
				break;
			}
		}
		[arguments addObject:[argString substringWithRange:[tr rangeAtIndex:j]]];
	}
	DDLogVerbose(@"arguments: %@", arguments);
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
	DDLogVerbose(@"encoding arguments: %@", arguments);
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
    return catTask;
}

-(MTTask *)decryptTask  //Decrypting is done in parallel with download so no progress indicators are needed.
{
    if (_decryptTask) {
        return _decryptTask;
    }
    MTTask *decryptTask = [MTTask taskWithName:@"decrypt" download:self];
    [decryptTask setLaunchPath:[[NSBundle mainBundle] pathForResource:@"tivodecode" ofType:@""]];

    decryptTask.completionHandler = ^(){
        if (!self.shouldSimulEncode) {
            [self setValue:[NSNumber numberWithInt:kMTStatusDownloaded] forKeyPath:@"downloadStatus"];
            [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationDecryptDidFinish object:nil];
            if (_decryptBufferFilePath) {
                setxattr([_decryptBufferFilePath cStringUsingEncoding:NSASCIIStringEncoding], [kMTXATTRFileComplete UTF8String], [[NSData data] bytes], 0, 0, 0);  //This is for a checkpoint and tell us the file is complete

            }
        }
		NSString *log = [NSString stringWithContentsOfFile:_decryptTask.errorFilePath encoding:NSUTF8StringEncoding error:nil];
		NSRange badMAKRange = [log rangeOfString:@"Invalid MAK"];
		if (badMAKRange.location != NSNotFound) {
			self.show.tiVo.mediaKeyIsGood = NO;
			[[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationBadMAK object:self.show.tiVo];
		}
    };
	
	decryptTask.terminationHandler = ^(){
		NSString *log = [NSString stringWithContentsOfFile:_decryptTask.errorFilePath encoding:NSUTF8StringEncoding error:nil];
		NSRange badMAKRange = [log rangeOfString:@"Invalid MAK"];
		if (badMAKRange.location != NSNotFound) {
			self.show.tiVo.mediaKeyIsGood = NO;
			[[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationBadMAK object:self.show.tiVo];
		}
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
    
    encodeTask.completionHandler = ^(){
        [self setValue:[NSNumber numberWithInt:kMTStatusEncoded] forKeyPath:@"downloadStatus"];
//        [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationEncodeDidFinish object:nil];
        self.processProgress = 1.0;
        [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationProgressUpdated object:nil];
        if (! [[NSFileManager defaultManager] fileExistsAtPath:self.encodeFilePath] ) {
            DDLogReport(@" %@ File %@ not found after encoding complete",self, self.encodeFilePath );
            [self saveCurrentLogFiles];
            [self rescheduleShowWithDecrementRetries:@(YES)];
            
        } else if (self.taskFlowType != kMTTaskFlowSimuMarkcom && self.taskFlowType != kMTTaskFlowSimuMarkcomSubtitles) {
            [self writeMetaDataFiles];
//            if ( ! (self.includeAPMMetaData.boolValue && self.encodeFormat.canAtomicParsley) ) {
                [self finishUpPostEncodeProcessing];
//            }
        }
        
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
                if ([[NSFileManager defaultManager] fileExistsAtPath:self.encodeFilePath] ) {
                    NSData *buffer = [NSData dataWithData:[[NSMutableData alloc] initWithLength:256]];
                    ssize_t len = getxattr([self.encodeFilePath cStringUsingEncoding:NSASCIIStringEncoding], [kMTXATTRFileComplete UTF8String], (void *)[buffer bytes], 256, 0, 0);
                    if (len >=0) {
                        DDLogReport(@"Found Complete Encoded File @ %@.  Skipping encoding",self.encodeFilePath);
                        return NO;
                    }
                }

                bufferFileReadHandle = [NSFileHandle fileHandleForReadingAtPath:_decryptBufferFilePath];
                taskChainInputHandle = [encodePipe fileHandleForWriting];
                _processProgress = 0.0;
                previousProcessProgress = 0.0;
                totalDataRead = 0.0;
                [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationProgressUpdated object:nil];
                [self setValue:[NSNumber numberWithInt:kMTStatusEncoding] forKeyPath:@"downloadStatus"];
                [self performSelectorInBackground:@selector(writeData) withObject:nil];
                return YES;
            };

        } else {
            encoderArgs = [self encodingArgumentsWithInputFile:_decryptBufferFilePath outputFile:_encodeFilePath];
            encodeTask.requiresInputPipe = NO;
            __block NSRegularExpression *percents = [NSRegularExpression regularExpressionWithPattern:self.encodeFormat.regExProgress options:NSRegularExpressionCaseInsensitive error:nil];
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
						DDLogVerbose(@"Encoder progress %lf",[[data substringWithRange:valueRange] doubleValue]/100.0);
						returnValue =  [[data substringWithRange:valueRange] doubleValue]/100.0;
					}

				}
				if (returnValue == -1.0) {
					DDLogMajor(@"Encode progress with Rx failed for task encoder for show %@",self.show.showTitle);

				}
				return returnValue;
            };
            encodeTask.startupHandler = ^BOOL(){
                _processProgress = 0.0;
                [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationProgressUpdated object:nil];
                [self setValue:[NSNumber numberWithInt:kMTStatusEncoding] forKeyPath:@"downloadStatus"];
                return YES;
            };
        }
    }
    
    
    [encodeTask setArguments:encoderArgs];
    DDLogVerbose(@"encoderArgs: %@",encoderArgs);
    _encodeTask = encodeTask;
    return _encodeTask;
}

-(MTTask *)captionTask  //Captioning is done in parallel with download so no progress indicators are needed.
{
    if (!_exportSubtitles.boolValue) {
        return nil;
    }
    if (_captionTask) {
        return _captionTask;
    }
    MTTask *captionTask = [MTTask taskWithName:@"caption" download:self completionHandler:nil];
    [captionTask setLaunchPath:[[NSBundle mainBundle] pathForResource:@"ccextractor" ofType:@""]];
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
                [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationProgressUpdated object:nil];
                return YES;
            };
        }
    }

    
    captionTask.completionHandler = ^(){
//        [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationCaptionDidFinish object:nil];
        setxattr([captionFilePath cStringUsingEncoding:NSASCIIStringEncoding], [kMTXATTRFileComplete UTF8String], [[NSData data] bytes], 0, 0, 0);  //This is for a checkpoint and tell us the file is complete
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
    if (!_skipCommercials && !_markCommercials) {
        return nil;
    }
    if (_commercialTask) {
        return _commercialTask;
    }
    MTTask *commercialTask = [MTTask taskWithName:@"commercial" download:self completionHandler:nil];
  	[commercialTask setLaunchPath:[[NSBundle mainBundle] pathForResource:@"comskip" ofType:@""]];
    commercialTask.requiresOutputPipe = NO;
    commercialTask.requiresInputPipe = NO;
    [commercialTask setStandardError:commercialTask.logFileWriteHandle];  //progress data is in err output
    
    
//    commercialTask.cleanupHandler = ^(){
//        if (![[NSUserDefaults standardUserDefaults] boolForKey:kMTSaveTmpFiles]) {
//            if ([[NSFileManager defaultManager] fileExistsAtPath:commercialFilePath]) {
//                [[NSFileManager defaultManager] removeItemAtPath:commercialFilePath error:nil];
//            }
//        }
//    };
    if (self.taskFlowType != kMTTaskFlowNonSimuMarkcom && self.taskFlowType != kMTTaskFlowNonSimuMarkcomSubtitles) {  // For these cases the encoding tasks is the driver
        commercialTask.startupHandler = ^BOOL(){
            self.processProgress = 0.0;
            [self setValue:[NSNumber numberWithInt:kMTStatusCommercialing] forKeyPath:@"downloadStatus"];
            return YES;
        };

        commercialTask.progressCalc = ^double(NSString *data){
            NSRegularExpression *percents = [NSRegularExpression regularExpressionWithPattern:@"(\\d+)\\%" options:NSRegularExpressionCaseInsensitive error:nil];
            NSArray *values = [percents matchesInString:data options:NSMatchingWithoutAnchoringBounds range:NSMakeRange(0, data.length)];
            NSTextCheckingResult *lastItem = [values lastObject];
            NSRange valueRange = [lastItem rangeAtIndex:1];
            return [[data substringWithRange:valueRange] doubleValue]/100.0;
        };

    
        commercialTask.completionHandler = ^{
            DDLogMajor(@"Finished detecting commercials in %@",self.show.showTitle);
             if (self.taskFlowType != kMTTaskFlowSimuMarkcom && self.taskFlowType != kMTTaskFlowSimuMarkcomSubtitles) {
                 if (!self.shouldSimulEncode) {
                            self.processProgress = 1.0;
                        }
                        [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationProgressUpdated object:nil];
                        [self setValue:[NSNumber numberWithInt:kMTStatusCommercialed] forKeyPath:@"downloadStatus"];
                        if (self.exportSubtitles.boolValue && self.skipCommercials) {
                            NSArray *srtEntries = [self getSrt:captionFilePath];
                            NSArray *edlEntries = [self getEdl:commercialFilePath];
                            if (srtEntries && edlEntries) {
                                NSArray *correctedSrts = [self processSrts:srtEntries withEdls:edlEntries];
                                if ([[NSUserDefaults standardUserDefaults] boolForKey:kMTSaveTmpFiles]) {
                                    NSString *oldCaptionPath = [[captionFilePath stringByDeletingPathExtension] stringByAppendingString:@"2.srt"];
                                    [[NSFileManager defaultManager] moveItemAtPath:captionFilePath toPath:oldCaptionPath error:nil];
                                }
                                if (correctedSrts) [self writeSrt:correctedSrts toFilePath:captionFilePath];
                            }
                        }
             } else {
                 self.processProgress = 1.0;
                 [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationProgressUpdated object:nil];
                 [self setValue:[NSNumber numberWithInt:kMTStatusCommercialed] forKeyPath:@"downloadStatus"];
                 [self writeMetaDataFiles];
//                 if ( ! (self.includeAPMMetaData.boolValue && self.encodeFormat.canAtomicParsley) ) {
                     [self finishUpPostEncodeProcessing];
//                 }
             }
            setxattr([captionFilePath cStringUsingEncoding:NSASCIIStringEncoding], [kMTXATTRFileComplete UTF8String], [[NSData data] bytes], 0, 0, 0);  //This is for a checkpoint and tell us the file is complete
            setxattr([commercialFilePath cStringUsingEncoding:NSASCIIStringEncoding], [kMTXATTRFileComplete UTF8String], [[NSData data] bytes], 0, 0, 0);  //This is for a checkpoint and tell us the file is complete
            
        };
    } else {
        commercialTask.completionHandler = ^{
            DDLogMajor(@"Finished detecting commercials in %@",self.show.showTitle);
        };
    }


	NSMutableArray *arguments = [NSMutableArray array];
    if (_encodeFormat.comSkipOptions.length) [arguments addObjectsFromArray:[self getArguments:_encodeFormat.comSkipOptions]];
    NSRange iniRange = [_encodeFormat.comSkipOptions rangeOfString:@"--ini="];
	[arguments addObject:[NSString stringWithFormat: @"--output=%@",[commercialFilePath stringByDeletingLastPathComponent]]];  //0.92 version
    if (iniRange.location == NSNotFound) {
        [arguments addObject:[NSString stringWithFormat: @"--ini=%@",[[NSBundle mainBundle] pathForResource:@"comskip" ofType:@"ini"]]];
    }
    
    if ((self.taskFlowType == kMTTaskFlowSimuMarkcom || self.taskFlowType == kMTTaskFlowSimuMarkcomSubtitles) && [self canPostDetectCommercials]) {
        [arguments addObject:_encodeFilePath]; //Run on the final file for these conditions
        commercialFilePath = [NSString stringWithFormat:@"%@/%@.edl" ,tiVoManager.tmpFilesDirectory, self.baseFileName];  //0.92 version
   } else {
        [arguments addObject:_decryptBufferFilePath];// Run this on the output of tivodecode
    }
	DDLogVerbose(@"comskip Path: %@",[[NSBundle mainBundle] pathForResource:@"comskip" ofType:@""]);
	DDLogVerbose(@"comskip args: %@",arguments);
	[commercialTask setArguments:arguments];
    _commercialTask = commercialTask;
    return _commercialTask;
  
}

//-(MTTask *)apmTask
//{
//    if (! (self.includeAPMMetaData.boolValue && self.encodeFormat.canAtomicParsley)) {
//		return nil;
//	}
//    if (_apmTask) {
//        return _apmTask;
//    }
//	MTTask *apmTask = [MTTask taskWithName:@"apm" download:self];
//    
//    apmTask.startupHandler = ^BOOL(){
//        [self setValue:[NSNumber numberWithInt:kMTStatusMetaDataProcessing] forKeyPath:@"downloadStatus"];
//        self.processProgress = 0.0;
//        [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationProgressUpdated object:nil];
//        return YES;
//    };
//    
//    apmTask.completionHandler = ^(){[self finishUpPostEncodeProcessing];};
//    
//	[apmTask setLaunchPath:[[NSBundle mainBundle] pathForResource:@"AtomicParsley" ofType: @""] ];
//    apmTask.requiresOutputPipe = NO;
//    apmTask.requiresInputPipe = NO;
//	NSMutableArray *apmArgs =[NSMutableArray array];
//	[apmArgs addObject:_encodeFilePath];
//	[apmArgs addObjectsFromArray:[self.show apmArguments]];
//	
//	DDLogVerbose(@"APM Arguments: %@", apmArgs);
//	[apmTask setArguments:apmArgs];
//	
//	[apmTask setStandardOutput:apmTask.logFileWriteHandle];
//    apmTask.trackingRegEx = [NSRegularExpression regularExpressionWithPattern:@"(\\d+)%" options:NSRegularExpressionCaseInsensitive error:nil];
//    _apmTask = apmTask;
//    return _apmTask;
//
//}

-(int)taskFlowType
{
  return (int)_exportSubtitles.boolValue + 2.0 * (int)_encodeFormat.canSimulEncode + 4.0 * (int) _skipCommercials + 8.0 * (int) _markCommercials;
}


-(void)download
{
	DDLogDetail(@"Starting download for %@",self);
	_isCanceled = NO;
	_isRescheduled = NO;
    _downloadingShowFromTiVoFile = NO;
    _downloadingShowFromMPGFile = NO;
    //Before starting make sure the encoder is OK.
	if (![self encoderPath]) {
        [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationShowDownloadDidFinish object:nil];  //Decrement num encoders right away
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
        NSLog(@"Downloading from file tivo file %@",_tivoFilePath);
    } else if (_downloadingShowFromMPGFile) {
        NSLog(@"Downloading from file MPG file %@",_mpgFilePath);
        self.activeTaskChain.dataSource = _mpgFilePath;
    }
	
    NSMutableArray *taskArray = [NSMutableArray array];
	
	if (!_downloadingShowFromMPGFile)[taskArray addObject:@[self.decryptTask]];
    
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
	double downloadDelay = kMTTiVoAccessDelay - [[NSDate date] timeIntervalSinceDate:self.show.tiVo.lastDownloadEnded];
	if (downloadDelay < 0) {
		downloadDelay = 0;
	}
	if (!_downloadingShowFromTiVoFile && !_downloadingShowFromMPGFile)[activeURLConnection performSelector:@selector(start) withObject:nil afterDelay:downloadDelay];
	[self performSelector:@selector(checkStillActive) withObject:nil afterDelay:kMTProgressCheckDelay];
}


-(void) writeTextMetaData:(NSString*) value forKey: (NSString *) key toFile: (NSFileHandle *) handle {
	if ( key && value) {
		
		[handle writeData:[[NSString stringWithFormat:@"%@: %@\n",key, value] dataUsingEncoding:NSUTF8StringEncoding]];
	}
}

-(void) writeMetaDataFiles {
	
	if (self.genXMLMetaData.boolValue) {
		NSString * tivoMetaPath = [[self.encodeFilePath stringByDeletingPathExtension] stringByAppendingPathExtension:@"xml"];
		DDLogMajor(@"Writing XML to    %@",tivoMetaPath);
		if (![self.show.detailXML writeToFile:tivoMetaPath atomically:NO])
			DDLogReport(@"Couldn't write XML to file %@", tivoMetaPath);
	}
	if (self.genTextMetaData.boolValue) {
		NSXMLDocument *xmldoc = [[NSXMLDocument alloc] initWithData:self.show.detailXML options:0 error:nil];
		NSString * xltTemplate = [[NSBundle mainBundle] pathForResource:@"pytivo_txt" ofType:@"xslt"];
		id returnxml = [xmldoc objectByApplyingXSLTAtURL:[NSURL fileURLWithPath:xltTemplate] arguments:nil error:nil	];
		NSString *returnString = [[NSString alloc] initWithData:returnxml encoding:NSUTF8StringEncoding];
		NSString * textMetaPath = [self.encodeFilePath stringByAppendingPathExtension:@"txt"];
		if (![returnString writeToFile:textMetaPath atomically:NO encoding:NSUTF8StringEncoding error:nil]) {
			DDLogReport(@"Couldn't write pyTiVo Data to file %@", textMetaPath);
		} else {
			NSFileHandle *textMetaHandle = [NSFileHandle fileHandleForWritingAtPath:textMetaPath];
			[textMetaHandle seekToEndOfFile];
			[self writeTextMetaData:self.show.seriesId		 forKey:@"seriesID"			    toFile:textMetaHandle];
			[self writeTextMetaData:self.show.channelString   forKey:@"displayMajorNumber"	toFile:textMetaHandle];
			[self writeTextMetaData:self.show.stationCallsign forKey:@"callsign"				toFile:textMetaHandle];
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
							   
-(void) finishUpPostEncodeProcessing {
	NSDate *startTime = [NSDate date];
	NSLog(@"QQQStarting finishing @ %@",startTime);
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(checkStillActive) object:nil];
	if (_addToiTunesWhenEncoded) {
		DDLogMajor(@"Adding to iTunes %@", self.show.showTitle);
        _processProgress = 1.0;
        [self setValue:[NSNumber numberWithInt:kMTStatusAddingToItunes] forKeyPath:@"downloadStatus"];
        [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationProgressUpdated object:nil];
		MTiTunes *iTunes = [[MTiTunes alloc] init];
		NSString * iTunesPath = [iTunes importIntoiTunes:self] ;
	
		if (iTunesPath && iTunesPath != self.encodeFilePath) {
			//apparently iTunes created new file
			
			if ([[NSUserDefaults standardUserDefaults] boolForKey:kMTiTunesDelete ]) {
				if (![[NSUserDefaults standardUserDefaults ] boolForKey:kMTSaveTmpFiles]) {
					if ([[NSFileManager defaultManager] removeItemAtPath:self.encodeFilePath error:nil]) {
						DDLogMajor (@"Deleting old video file %@", self.encodeFilePath);
					} else {
						DDLogReport(@"Couldn't remove file at path %@",self.encodeFilePath);
					}
				}
				//but remember new file for future processing
				_encodeFilePath= iTunesPath;
			} else {
				//two copies now, so add xattrs to iTunes copy as well
				[self addXAttrs:iTunesPath];
			}
		}
	}
    if (self.shouldMarkCommercials || self.encodeFormat.canAtomicParsley)
    {
        MP4FileHandle *encodedFile = MP4Modify([_encodeFilePath cStringUsingEncoding:NSASCIIStringEncoding],0);
		if (self.shouldMarkCommercials) {
			MP4Chapters *chapters = [self createChapters];
			if (chapters && encodedFile) {
				MP4SetChapters(encodedFile, chapters->chapters, chapters->count, MP4ChapterTypeQt);
			}
		}
		if (self.encodeFormat.canAtomicParsley) {
			const MP4Tags *tags = MP4TagsAlloc();
			uint8_t mediaType = 10;
			if (_show.isMovie) {
				mediaType = 9;
			}
			MP4TagsSetMediaType(tags, &mediaType);
			if (_show.episodeTitle.length>0) {
				MP4TagsSetName(tags,[_show.episodeTitle cStringUsingEncoding:NSUTF8StringEncoding]);
			}
			if (_show.episodeGenre.length>0) {
				MP4TagsSetGenre(tags,[_show.episodeGenre cStringUsingEncoding:NSUTF8StringEncoding]);
			}
			if (_show.originalAirDate.length>0) {
				MP4TagsSetReleaseDate(tags,[_show.originalAirDate cStringUsingEncoding:NSUTF8StringEncoding]);
			} else if (_show.movieYear.length>0) {
				MP4TagsSetReleaseDate(tags,[_show.movieYear	cStringUsingEncoding:NSUTF8StringEncoding]);
			}
			
			if (_show.showDescription.length > 0) {
				if (_show.showDescription.length < 230) {
					MP4TagsSetDescription(tags,[_show.showDescription cStringUsingEncoding:NSUTF8StringEncoding]);
					
				} else {
					MP4TagsSetLongDescription(tags,[_show.showDescription cStringUsingEncoding:NSUTF8StringEncoding]);
				}
			}
			if (_show.seriesTitle.length>0) {
				MP4TagsSetTVShow(tags,[_show.seriesTitle cStringUsingEncoding:NSUTF8StringEncoding]);
				MP4TagsSetArtist(tags,[_show.seriesTitle cStringUsingEncoding:NSUTF8StringEncoding]);
				MP4TagsSetAlbumArtist(tags,[_show.seriesTitle cStringUsingEncoding:NSUTF8StringEncoding]);
			}
			if (_show.episodeNumber.length>0) {
				uint32_t episodeNumber = [_show.episodeNumber intValue];
				MP4TagsSetTVEpisode(tags, &episodeNumber);
			}
			if (_show.episode > 0) {
				uint32_t episodeNumber = _show.episode;
				MP4TagsSetTVEpisode(tags, &episodeNumber);
//				NSString * epString = [NSString stringWithFormat:@"%d",self.episode];
//				[apmArgs addObject:@"--tracknum"];
//				[apmArgs addObject:epString];
			} else if (_show.episodeNumber.length>0) {
				uint32_t episodeNumber =  [_show.episodeNumber intValue];
				MP4TagsSetTVEpisode(tags, &episodeNumber);
//				[apmArgs addObject:@"--tracknum"];
//				[apmArgs addObject:self.episodeNumber];
				
			}
			if (_show.season > 0 ) {
				uint32_t showSeason =  _show.season;
				MP4TagsSetTVSeason(tags, &showSeason);
			}
			if (_show.stationCallsign) {
				MP4TagsSetTVNetwork(tags, [_show.stationCallsign cStringUsingEncoding:NSUTF8StringEncoding]);
			}
			MP4TagsStore(tags, encodedFile);
		}
        
		MP4Close(encodedFile, 0);
    }
	[self addXAttrs:self.encodeFilePath];
//    [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationDetailsLoaded object:_show];
	NSLog(@"QQQIt Took %lf seconds to complete for show %@",[[NSDate date] timeIntervalSinceDate:startTime], _show.showTitle);
	[self setValue:[NSNumber numberWithInt:kMTStatusDone] forKeyPath:@"downloadStatus"];
    [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationShowDownloadDidFinish object:nil];  //Free up an encoder
    _processProgress = 1.0;
	[[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationProgressUpdated object:nil];
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
        [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationShowDownloadWasCanceled object:nil];
    }
    _decryptTask = _captionTask = _commercialTask = _encodeTask  = nil;
    
	NSDate *now = [NSDate date];
    while (writingData && (-1.0 * [now timeIntervalSinceNow]) < 5.0){ //Wait for no more than 5 seconds.
        //Block until latest write data is complete - should stop quickly because isCanceled is set
		writingData = NO;
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
		[[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationProgressUpdated object:self];
  	}
    
}

#pragma mark - Download/Conversion  Progress Tracking

-(void)checkStillActive
{
	if (previousProcessProgress == _processProgress) { //The process is stalled so cancel and restart
		//Cancel and restart or delete depending on number of time we've been through this
        DDLogMajor (@"process stalled; rescheduling");
		[self rescheduleShowWithDecrementRetries:@(YES)];
	} else if ([self isInProgress]){
		previousProcessProgress = _processProgress;
		[self performSelector:@selector(checkStillActive) withObject:nil afterDelay:kMTProgressCheckDelay];
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

-(void)updateProgress
{
    [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationProgressUpdated object:nil];
}

#pragma mark - SRT/EDL handling Captions with commercial cuts

-(NSArray *)getSrt:(NSString *)srtFile
{
	NSArray *rawSrts = [[NSString stringWithContentsOfFile:srtFile encoding:NSASCIIStringEncoding error:nil] componentsSeparatedByString:@"\r\n\r\n"];
    NSMutableArray *srts = [NSMutableArray array];
	MTSrt *lastSrt = nil;
    for (NSString *rawSrt in rawSrts) {
        if (rawSrt.length > kMinSrtLength) {
            MTSrt *newSrt = [MTSrt srtFromString: rawSrt];
			if (newSrt && lastSrt) {
				if (newSrt.startTime <= lastSrt.endTime) {
					DDLogReport(@"SRT file not in correct order");
					newSrt = nil;
				}
			}
            if (newSrt) {
				[srts addObject:newSrt];
			} else {
				DDLogDetail(@"SRTs before bad one: %@",srts);
				return nil;
			}
			lastSrt = newSrt;
        }
    }
    DDLogVerbose(@"srts = %@",srts);
    return [NSArray arrayWithArray:srts];
}

-(MP4Chapters *)createChapters
{
    if (![[NSFileManager defaultManager] fileExistsAtPath:commercialFilePath]) {
        return NULL;  //Files don't exist to process
    }
    NSArray *edls = [self getEdl:commercialFilePath];
    if (!edls || edls.count == 0) {
        return NULL;  //No edls available to process
    }
    //Convert edls to MP4Chapter
    MP4Chapters *chapters = malloc(sizeof(MP4Chapters));
    MP4Chapter_t *chapterList = malloc((edls.count * 2 + 1) * sizeof(MP4Chapter_t)); //This is the most there could be
    chapters->chapters = chapterList;
    int edlOffset = 0;
    int showOffset = 0;
    int chapterOffset = 0;
    MTEdl *currentEDL = edls[edlOffset];
    if (currentEDL.startTime > 0.0) { //We need a first chapter which is the show
        chapterList[chapterOffset].duration = (MP4Duration)((currentEDL.startTime) * 1000.0);
        sprintf(chapterList[chapterOffset].title,"%s %d",[_show.showTitle cStringUsingEncoding:NSUTF8StringEncoding], showOffset+1);
        chapterOffset++;
        showOffset++;
    }
    for (edlOffset = 0; edlOffset < edls.count; edlOffset++) {
        currentEDL = edls[edlOffset];
        double endTime = currentEDL.endTime;
        if (endTime > _show.showLength) {
            endTime = _show.showLength;
        }
        chapterList[chapterOffset].duration = (MP4Duration)((endTime - currentEDL.startTime) * 1000.0);
        sprintf(chapterList[chapterOffset].title,"%s %d","Commercial", edlOffset+1);
        chapterOffset++;
        if (currentEDL.endTime < _show.showLength && (edlOffset + 1) < edls.count) { //Continuing
            MTEdl *nextEDL = edls[edlOffset + 1];
            chapterList[chapterOffset].duration = (MP4Duration)((nextEDL.startTime - currentEDL.endTime) * 1000.0);
            sprintf(chapterList[chapterOffset].title,"%s %d",[_show.showTitle cStringUsingEncoding:NSUTF8StringEncoding], showOffset+1);
            chapterOffset++;
            showOffset++;           
        } else if (currentEDL.endTime < _show.showLength) { // There's show left but no more commercials so just complete the show chapter
            chapterList[chapterOffset].duration = (MP4Duration)((_show.showLength - currentEDL.endTime) * 1000.0);
            sprintf(chapterList[chapterOffset].title,"%s %d",[_show.showTitle cStringUsingEncoding:NSUTF8StringEncoding], showOffset+1);
            chapterOffset++;
            showOffset++;
            
        }
    }
    //Loging fuction for testing
    
    for (int i = 0; i < chapterOffset ; i++) {
        NSLog(@"Chapter %d: duration %llu, title: %s",i+1,chapterList[i].duration, chapterList[i].title);
    }
    
    chapters->count = chapterOffset;
    return chapters;
    
}

-(NSArray *)getEdl:(NSString *)edlFile
{
	NSArray *rawEdls = [[NSString stringWithContentsOfFile:edlFile encoding:NSASCIIStringEncoding error:nil] componentsSeparatedByString:@"\n"];
    NSMutableArray *edls = [NSMutableArray array];
	MTEdl * lastEdl = nil;
    double cumulativeOffset = 0.0;
	for (NSString *rawEdl in rawEdls) {
        if (rawEdl.length > kMinEdlLength) {
            MTEdl *newEdl = [MTEdl edlFromString:rawEdl];
			if (newEdl && lastEdl) {
				if (newEdl.startTime <= lastEdl.endTime) {
					DDLogReport(@"EDL file not in correct order");
					newEdl = nil;
				}
			}
            if (newEdl) {
				if (newEdl.edlType == 0) { //This is for a cut edl.  Other types/action don't cut (such as 1 for mute)
					cumulativeOffset += (newEdl.endTime - newEdl.startTime);
				}
				newEdl.offset = cumulativeOffset;
				[edls addObject:newEdl];
			} else {
				DDLogDetail(@"EDLs before bad one: %@",edls);
				return nil;
			}
        }
    }
    DDLogVerbose(@"edls = %@",edls);
    return [NSArray arrayWithArray:edls];
	
}

-(void)writeSrt:(NSArray *)srts toFilePath:(NSString *)filePath
{
    [[NSFileManager defaultManager] createFileAtPath:filePath contents:[NSData data] attributes:nil];
    NSFileHandle *srtFileHandle = [NSFileHandle fileHandleForWritingAtPath:filePath];
    NSString *output = @"";
    int i =1;
    for (MTSrt *srt in srts) {
        output = [output stringByAppendingString:[srt formatedSrt:i]];
        i++;
    }
    [srtFileHandle writeData:[output dataUsingEncoding:NSASCIIStringEncoding allowLossyConversion:YES]];
    [srtFileHandle closeFile];
	
}

-(NSArray *)processSrts:(NSArray *)srts withEdls:(NSArray *)edls
{
    if (edls.count == 0) return srts;
	NSMutableArray *keptSrts = [NSMutableArray array];
	NSUInteger edlIndex = 0;
	MTEdl *currentEDL = edls[edlIndex];
    for (MTSrt *srt in srts) {
		while (currentEDL &&  (  (srt.startTime > currentEDL.endTime) || (currentEDL.edlType != 0)  ) ){
			//relies on both edl and srt to be sorted and skips edl that are not cuts (type != 0)
			edlIndex++;
			currentEDL = nil;
			if (edlIndex < edls.count) {
				currentEDL = edls[edlIndex];
			}
			
		};
		//now current edl is either crossed with srt or after it.
		//If crossed, we delete srt;
		if (currentEDL) {
			if (currentEDL.startTime <= srt.endTime ) {
				//The srt is  in a cut so remove
				continue;
			}
		}
		//if after, we use cumulative offset of "just-prior" edl
		if (edlIndex > 0) {  //else no offset required
			MTEdl * prevEdl = (MTEdl *)edls[edlIndex-1];
			srt.startTime -= prevEdl.offset;
			srt.endTime -= prevEdl.offset;
		}
		[keptSrts addObject:srt];
    }
	return [NSArray arrayWithArray:keptSrts];
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
	//	writingData = YES;
	int chunkSize = 50000;
	unsigned long dataRead;
	@autoreleasepool {
		NSData *data = nil;
		if (!_isCanceled) {
			@try {
                // writeData supports getting its data from either an NSData buffer (urlBuffer) or a file on disk (_bufferFilePath).  This allows cTiVo to 
                // initially try to keep the dataflow off the disk, except for final products, where possible.  But, the ability to do this depends on the 
                // processor being able to keep up with the data flow from the TiVo which is often not the case due to either a slow processor, fast network 
                // connection, of different tasks competing for processor resources.  When the processor falls too far behind and the memory buffer will 
                // become too large cTiVo will fall back to using files on the disk as a data buffer.
                
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
		}
		if (!_isCanceled){
			@try {
                if (data.length) {
                    [taskChainInputHandle writeData:data];
                }
			}
			@catch (NSException *exception) {
                if (!_isCanceled){
                    [self rescheduleOnMain];
                    DDLogDetail(@"Rescheduling");
                };
				DDLogDetail(@"download write fail: %@; %@", exception.reason, _show.showTitle);
			}
			@finally {
			}
		}
		dataRead = data.length;
        totalDataRead += dataRead;
		while (dataRead == chunkSize && !_isCanceled) {
			@autoreleasepool {
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
					DDLogDetail(@"buffer read fail2: %@; %@", exception.reason,_show.showTitle);
				}
				@finally {
				}
				if (!_isCanceled) {
					@try {
                        if (data.length) {
                            [taskChainInputHandle writeData:data];
                        }
					}
					@catch (NSException *exception) {
						if (!_isCanceled){
                            [self rescheduleOnMain];
                            DDLogDetail(@"Rescheduling");
                        };
						DDLogDetail(@"download write fail2: %@; %@", exception.reason, _show.showTitle);
					}
					@finally {
					}
				}
				if (_isCanceled) break;
				dataRead = data.length;
                totalDataRead += dataRead;
				_processProgress = totalDataRead/_show.fileSize;
				[self performSelectorOnMainThread:@selector(updateProgress) withObject:nil waitUntilDone:NO];
			}
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
				DDLogReport(@"URLBuffer length exceeded %d, switching to file based buffering",kMTMaxBuffSize);
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

- (BOOL)connection:(NSURLConnection *)connection canAuthenticateAgainstProtectionSpace:(NSURLProtectionSpace *)protectionSpace {
    return YES;
}

- (void)connection:(NSURLConnection *)connection didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge {
    //    [challenge.sender useCredential:[NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust] forAuthenticationChallenge:challenge];
    DDLogDetail(@"Show password check");
    [challenge.sender useCredential:[NSURLCredential credentialWithUser:@"tivo" password:self.show.tiVo.mediaKey persistence:NSURLCredentialPersistenceForSession] forAuthenticationChallenge:challenge];
    [challenge.sender continueWithoutCredentialForAuthenticationChallenge:challenge];
}

-(void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error
{
    DDLogMajor(@"URL Connection Failed with error %@",error);
	[self performSelectorOnMainThread:@selector(rescheduleShowWithDecrementRetries:) withObject:@(YES) waitUntilDone:NO];
}

#define kMTMinTiVoFileSize 100000
-(void)connectionDidFinishLoading:(NSURLConnection *)connection
{
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
				[self.show.tiVo updateShows:nil];
				return;
			}
		}
		DDLogMajor(@"Downloaded file  too small - rescheduling; File sent was %@",dataReceived);
		[self performSelector:@selector(rescheduleShowWithDecrementRetries:) withObject:@(NO) afterDelay:kMTTiVoAccessDelay];
	} else {
//		NSLog(@"File size before reset %lf %lf",self.show.fileSize,downloadedFileSize);
		self.show.fileSize = downloadedFileSize;  //More accurate file size
//		NSLog(@"File size after reset %lf %lf",self.show.fileSize,downloadedFileSize);
		NSNotification *not = [NSNotification notificationWithName:kMTNotificationDownloadDidFinish object:self.show.tiVo];
		[[NSNotificationCenter defaultCenter] performSelector:@selector(postNotification:) withObject:not afterDelay:kMTTiVoAccessDelay];
        if ([bufferFileReadHandle isKindOfClass:[NSFileHandle class]]) {
            if ([[_bufferFilePath substringFromIndex:_bufferFilePath.length-4] compare:@"tivo"] == NSOrderedSame  && !_isCanceled) { //We finished a complete download so mark it so
                setxattr([_bufferFilePath cStringUsingEncoding:NSASCIIStringEncoding], [kMTXATTRFileComplete UTF8String], [[NSData data] bytes], 0, 0, 0);  //This is for a checkpoint and tell us the file is complete
            }
        }
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

-(BOOL) shouldMarkCommercials
{
    return (_encodeFormat.canMarkCommercials && _markCommercials);
}

-(BOOL) canAddToiTunes {
    return self.encodeFormat.canAddToiTunes;
}

-(BOOL) shouldAddToiTunes {
    return _addToiTunesWhenEncoded;
}

-(BOOL) canPostDetectCommercials {
	NSArray * allowedExtensions = @[@".mp4", @".m4v", @".mpg"];
	NSString * extension = [_encodeFormat.filenameExtension lowercaseString];
	return [allowedExtensions containsObject: extension];
}



#pragma mark - Custom Getters

-(NSNumber *)downloadIndex
{
	NSInteger index = [tiVoManager.downloadQueue indexOfObject:self];
	return [NSNumber numberWithInteger:index+1];
}


-(NSString *) showStatus {
	switch (_downloadStatus.intValue) {
		case  kMTStatusNew : return @"";
		case  kMTStatusDownloading : return @"Downloading";
		case  kMTStatusDownloaded : return @"Downloaded";
		case  kMTStatusDecrypting : return @"Decrypting";
		case  kMTStatusDecrypted : return @"Decrypted";
		case  kMTStatusCommercialing : return @"Detecting Commercials";
		case  kMTStatusCommercialed : return @"Commercials Detected";
		case  kMTStatusEncoding : return @"Encoding";
		case  kMTStatusEncoded : return @"Encoded";
        case  kMTStatusAddingToItunes: return @"Adding To iTunes";
		case  kMTStatusDone : return @"Complete";
		case  kMTStatusCaptioned: return @"Subtitled";
		case  kMTStatusCaptioning: return @"Subtitling";
		case  kMTStatusDeleted : return @"TiVo Deleted";
		case  kMTStatusFailed : return @"Failed";
		case  kMTStatusMetaDataProcessing : return @"Adding MetaData";
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
    }
}


#pragma mark - Memory Management

-(void)dealloc
{
    self.encodeFormat = nil;
    [self deallocDownloadHandling];
	[self removeObserver:self forKeyPath:@"downloadStatus"];
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	
}

-(NSString *)description
{
    return [NSString stringWithFormat:@"%@ (%@)%@",self.show.showTitle,self.show.tiVoName,[self.show.protectedShow boolValue]?@"-Protected":@""];
}


@end

