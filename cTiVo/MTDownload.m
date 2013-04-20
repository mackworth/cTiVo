//
//  MTDownload.m
//  cTiVo
//
//  Created by Hugh Mackworth on 2/26/13.
//  Copyright (c) 2013 Scott Buchanan. All rights reserved.
//
#define comSkip92 1

#import "MTProgramTableView.h"
#import "MTiTunes.h"
#import "MTTiVoManager.h"
#import "MTDownload.h"
#include <sys/xattr.h>

@interface MTDownload () {
	
	NSFileHandle  *bufferFileWriteHandle;
    id bufferFileReadHandle;
    
    NSFileHandle *taskChainInputHandle;
	
    NSString *commercialFilePath, *nameLockFilePath, *captionFilePath; //Files shared between tasks
	
    double dataDownloaded;
	NSURLConnection *activeURLConnection;
	BOOL volatile writingData, downloadingURL;
    NSDate *previousCheck;
	double previousProcessProgress;
    NSMutableData *urlBuffer;
    ssize_t urlReadPointer;
	
}

@property (strong, nonatomic) NSString *downloadDir;

@property (nonatomic) MTTask *decryptTask, *encodeTask, *commercialTask, *apmTask, *captionTask;

@end

@implementation MTDownload


@synthesize encodeFilePath   = _encodeFilePath,
downloadFilePath = _downloadFilePath,
bufferFilePath   = _bufferFilePath,
isCanceled;

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
        _simultaneousEncode = YES;
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
		DDLogVerbose(@"Changing DL status of %@ to %@", object, [(MTDownload *)object downloadStatus]);
        [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationDownloadStatusChanged object:nil];
    }
}


-(void)saveCurrentLogFiles
{
    if (_downloadStatus.intValue == kMTStatusDownloading) {
        DDLogMajor(@"%@ downloaded %f of %f bytes; %ld%%",self,dataDownloaded, _show.fileSize, lround(_processProgress*100));
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
	DDLogMajor(@"Stalled at %@, %@ download of %@ with progress at %lf with previous check at %@",self.showStatus,(_numRetriesRemaining > 0) ? @"restarting":@"canceled",  _show.showTitle, _processProgress, previousCheck );
	[self saveCurrentLogFiles];
	[self cancel];
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
	[encoder encodeObject:[NSNumber numberWithBool:_simultaneousEncode] forKey: kMTSubscribedSimulEncode];
	[encoder encodeObject:[NSNumber numberWithBool:_skipCommercials] forKey: kMTSubscribedSkipCommercials];
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
								   [NSNumber numberWithBool:_simultaneousEncode], kMTSubscribedSimulEncode,
								   [NSNumber numberWithBool:_skipCommercials], kMTSubscribedSkipCommercials,
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
	_downloadStatus = queueEntry[kMTQueueStatus];
	if (_downloadStatus.integerValue == kMTStatusDoneOld) _downloadStatus = @kMTStatusDone; //temporary patch for old queues
	if (self.isInProgress) _downloadStatus = @kMTStatusNew;		//until we can launch an in-progress item
	
	_simultaneousEncode = [queueEntry[kMTSimultaneousEncode] boolValue];
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
		_simultaneousEncode	 =   [[decoder decodeObjectForKey: kMTSubscribedSimulEncode] boolValue];
		_skipCommercials   =     [[decoder decodeObjectForKey: kMTSubscribedSkipCommercials] boolValue];
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
	//Clean up files in KMTTmpDir
	if (deleteFiles && self.baseFileName) {
		NSArray *tmpFiles = [fm contentsOfDirectoryAtPath:kMTTmpDir error:nil];
		[fm changeCurrentDirectoryPath:kMTTmpDir];
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
    NSString *trialEncodeFilePath = [NSString stringWithFormat:@"%@/%@%@",downloadDir,baseName,_encodeFormat.filenameExtension];
	NSString *trialLockFilePath = [NSString stringWithFormat:@"%@%@.lck" ,kMTTmpDir,baseName];
	NSFileManager *fm = [NSFileManager defaultManager];
	if ([fm fileExistsAtPath:trialEncodeFilePath] || [fm fileExistsAtPath:trialLockFilePath]) {
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

-(void)configureFiles  //Configure file paths and pointers that may be shared between multiple tasks
{
	DDLogDetail(@"configuring files for %@",self);
	//Release all previous attached pointers
	urlBuffer = [NSMutableData new];
    urlReadPointer = 0;
    [self deallocDownloadHandling];
	self.baseFileName = [self makeBaseFileNameForDirectory:self.downloadDir];
	_encodeFilePath = [NSString stringWithFormat:@"%@/%@%@",self.downloadDir,self.baseFileName,_encodeFormat.filenameExtension];
	DDLogVerbose(@"setting encodepath: %@", _encodeFilePath);
    _bufferFilePath = [NSString stringWithFormat:@"%@buffer%@.bin",kMTTmpDir,self.baseFileName];
    _decryptBufferFilePath = [NSString stringWithFormat:@"%@buffer%@.mpg",kMTTmpDir,self.baseFileName];
//    [[NSFileManager defaultManager] createFileAtPath:_bufferFilePath contents:[NSData data] attributes:nil];
    [[NSFileManager defaultManager] createFileAtPath:_decryptBufferFilePath contents:[NSData data] attributes:nil];
    bufferFileReadHandle = urlBuffer;
//    bufferFileReadHandle = [NSFileHandle fileHandleForReadingAtPath:_bufferFilePath];
//	bufferFileWriteHandle = [NSFileHandle fileHandleForWritingAtPath:_bufferFilePath];
    captionFilePath = [NSString stringWithFormat:@"%@/%@.srt",self.downloadDir ,self.baseFileName];

#if comSkip92
    commercialFilePath = [NSString stringWithFormat:@"%@buffer%@.edl" ,kMTTmpDir, self.baseFileName];  //0.92 version
#else
    commercialFilePath = [[NSString stringWithFormat:@"%@/%@.edl",downloadDir ,self.baseFileName] retain];  //0.7 version
#endif
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
	
    if ([_encodeFormat.comSkip boolValue] && _skipCommercials && _encodeFormat.edlFlag.length) {
        [arguments addObject:_encodeFormat.edlFlag];
        [arguments addObject:commercialFilePath];
    }
    if (_encodeFormat.outputFileFlag.length) {
        if (_encodeFormat.encoderEarlyVideoOptions.length) [arguments addObjectsFromArray:[self getArguments:_encodeFormat.encoderEarlyVideoOptions]];
        if (_encodeFormat.encoderEarlyAudioOptions.length) [arguments addObjectsFromArray:[self getArguments:_encodeFormat.encoderEarlyAudioOptions]];
        if (_encodeFormat.encoderEarlyOtherOptions.length) [arguments addObjectsFromArray:[self getArguments:_encodeFormat.encoderEarlyOtherOptions]];
        [arguments addObject:_encodeFormat.outputFileFlag];
        [arguments addObject:outputFilePath];
        if (_encodeFormat.inputFileFlag.length) {
            [arguments addObject:_encodeFormat.inputFileFlag];
        }
        [arguments addObject:inputFilePath];
    } else {
        if (_encodeFormat.encoderEarlyVideoOptions.length) [arguments addObjectsFromArray:[self getArguments:_encodeFormat.encoderEarlyVideoOptions]];
        if (_encodeFormat.encoderEarlyAudioOptions.length) [arguments addObjectsFromArray:[self getArguments:_encodeFormat.encoderEarlyAudioOptions]];
        if (_encodeFormat.encoderEarlyOtherOptions.length) [arguments addObjectsFromArray:[self getArguments:_encodeFormat.encoderEarlyOtherOptions]];
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
    MTTask *catTask = [MTTask newWithTaskName:@"cat" download:self];
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
    MTTask *decryptTask = [MTTask newWithTaskName:@"decrypt" download:self];
    [decryptTask setLaunchPath:[[NSBundle mainBundle] pathForResource:@"tivodecode" ofType:@""]];

    decryptTask.completionHandler = ^(){
        if (!self.shouldSimulEncode) {
            [self setValue:[NSNumber numberWithInt:kMTStatusDownloaded] forKeyPath:@"downloadStatus"];
            [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationDownloadDidFinish object:nil];
            if (_decryptBufferFilePath) {
                setxattr([_decryptBufferFilePath cStringUsingEncoding:NSASCIIStringEncoding], [kMTXATTRFileComplete UTF8String], [[NSData data] bytes], 0, 0, 0);  //This is for a checkpoint and tell us the file is complete

            }
        }
    };
    
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
                     @"--",
                     @"-",
                     nil];
        decryptTask.requiresOutputPipe = YES;
        //Not using the filebuffer so remove so it can act as a flag upon completion.
        if (!_skipCommercials) {
            [[NSFileManager defaultManager] removeItemAtPath:_decryptBufferFilePath error:nil];
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
    MTTask *encodeTask = [MTTask newWithTaskName:@"encode" download:self];
    [encodeTask setLaunchPath:[self encoderPath]];
    encodeTask.requiresOutputPipe = NO;
	NSArray * encoderArgs = nil;
    
    encodeTask.completionHandler = ^(){
        [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationEncodeDidFinish object:nil];
        self.processProgress = 1.0;
        [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationProgressUpdated object:nil];
        if (! [[NSFileManager defaultManager] fileExistsAtPath:self.encodeFilePath] ) {
            DDLogReport(@" %@ File %@ not found after encoding complete",self, self.encodeFilePath );
            [self saveCurrentLogFiles];
            [self rescheduleShowWithDecrementRetries:@(YES)];
            
        } else {
            [self writeMetaDataFiles];
            if ( ! (self.includeAPMMetaData.boolValue && self.encodeFormat.canAtomicParsley) ) {
                [self finishUpPostEncodeProcessing];
            }
        }
        
    };
    encoderArgs = [self encodingArgumentsWithInputFile:@"-" outputFile:_encodeFilePath];
    
    if (!self.shouldSimulEncode)  {
        if (self.encodeFormat.canSimulEncode) {  //Need to setup up the startup for sequential processing to use the writeData progress tracking
            encodeTask.requiresInputPipe = YES;
            __block NSPipe *encodePipe = [NSPipe new];
            [encodeTask setStandardInput:encodePipe];
            encodeTask.startupHandler = ^(){
                bufferFileReadHandle = [NSFileHandle fileHandleForReadingAtPath:_decryptBufferFilePath];
                taskChainInputHandle = [encodePipe fileHandleForWriting];
                _processProgress = 0.0;
                previousProcessProgress = 0.0;
                totalDataRead = 0.0;
                [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationProgressUpdated object:nil];
                [self setValue:[NSNumber numberWithInt:kMTStatusEncoding] forKeyPath:@"downloadStatus"];
                [self performSelectorInBackground:@selector(writeData) withObject:nil];
            };

        } else {
            encoderArgs = [self encodingArgumentsWithInputFile:_decryptBufferFilePath outputFile:_encodeFilePath];
            encodeTask.requiresInputPipe = NO;
            __block NSRegularExpression *percents = [NSRegularExpression regularExpressionWithPattern:self.encodeFormat.regExProgress options:NSRegularExpressionCaseInsensitive error:nil];
            encodeTask.progressCalc = ^double(NSString *data){
                NSArray *values = [percents matchesInString:data options:NSMatchingWithoutAnchoringBounds range:NSMakeRange(0, data.length)];
                NSTextCheckingResult *lastItem = [values lastObject];
                NSRange valueRange = [lastItem rangeAtIndex:1];
                DDLogVerbose(@"Encoder progress %lf",[[data substringWithRange:valueRange] doubleValue]/100.0);
                return  [[data substringWithRange:valueRange] doubleValue]/100.0;
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
    MTTask *captionTask = [MTTask newWithTaskName:@"caption" download:self completionHandler:nil];
    [captionTask setLaunchPath:[[NSBundle mainBundle] pathForResource:@"ccextractor" ofType:@""]];
    captionTask.requiresOutputPipe = NO;
    
    captionTask.completionHandler = ^(){
        [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationCaptionDidFinish object:nil];
        setxattr([captionFilePath cStringUsingEncoding:NSASCIIStringEncoding], [kMTXATTRFileComplete UTF8String], [[NSData data] bytes], 0, 0, 0);  //This is for a checkpoint and tell us the file is complete
    };
    
//    captionTask.cleanupHandler = ^(){
//        if (![[NSUserDefaults standardUserDefaults] boolForKey:kMTSaveTmpFiles]) {
//            if ([[NSFileManager defaultManager] fileExistsAtPath:captionOutputFile]) {
//                [[NSFileManager defaultManager] removeItemAtPath:captionOutputFile error:nil];
//            }
//        }
//    };
    
    NSMutableArray * captionArgs = [NSMutableArray array];
    
    if (_encodeFormat.captionOptions.length) [captionArgs addObjectsFromArray:[self getArguments:_encodeFormat.captionOptions]];
    
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
    if (!_skipCommercials) {
        return nil;
    }
    if (_commercialTask) {
        return _commercialTask;
    }
    MTTask *commercialTask = [MTTask newWithTaskName:@"commercial" download:self completionHandler:nil];
  	[commercialTask setLaunchPath:[[NSBundle mainBundle] pathForResource:@"comskip" ofType:@""]];
    commercialTask.requiresOutputPipe = NO;
    commercialTask.requiresInputPipe = NO;
    [commercialTask setStandardError:commercialTask.logFileWriteHandle];  //progress data is in err output
    
    commercialTask.startupHandler = ^(){
        self.processProgress = 0.0;
        [self setValue:[NSNumber numberWithInt:kMTStatusCommercialing] forKeyPath:@"downloadStatus"];
    };
    
    commercialTask.cleanupHandler = ^(){
        if (![[NSUserDefaults standardUserDefaults] boolForKey:kMTSaveTmpFiles]) {
            if ([[NSFileManager defaultManager] fileExistsAtPath:commercialFilePath]) {
                [[NSFileManager defaultManager] removeItemAtPath:commercialFilePath error:nil];
            }
        }
    };
    
    commercialTask.progressCalc = ^double(NSString *data){
        NSRegularExpression *percents = [NSRegularExpression regularExpressionWithPattern:@"(\\d+)\\%" options:NSRegularExpressionCaseInsensitive error:nil];
		NSArray *values = [percents matchesInString:data options:NSMatchingWithoutAnchoringBounds range:NSMakeRange(0, data.length)];
		NSTextCheckingResult *lastItem = [values lastObject];
		NSRange valueRange = [lastItem rangeAtIndex:1];
		return [[data substringWithRange:valueRange] doubleValue]/100.0;
    };
    
    commercialTask.completionHandler = ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationCommercialDidFinish object:nil];
        DDLogMajor(@"Finished detecting commercials in %@",self.show.showTitle);
//		NSString * encodeDirectory = [_encodeFilePath stringByDeletingLastPathComponent];
//#if comSkip92
//		NSString * newCommercialPath = [encodeDirectory stringByAppendingPathComponent: [commercialFilePath lastPathComponent]] ;
//		[[NSFileManager defaultManager] removeItemAtPath:newCommercialPath error:nil ]; //just in case already there.
//		NSError * error = nil;
//		[[NSFileManager defaultManager] moveItemAtPath:commercialFilePath toPath:newCommercialPath error:&error];
//		if (error) {
//			DDLogMajor(@"Error moving commercial EDL file %@ to %@: %@",commercialFilePath, newCommercialPath, error.localizedDescription);
//		} else {
//			commercialFilePath = newCommercialPath;
//		}
//#else
//		if( ![[NSUserDefaults standardUserDefaults] boolForKey:kMTSaveTmpFiles]) {
//			[[NSFileManager defaultManager] removeItemAtPath:[NSString stringWithFormat:@"%@/%@.tivo.txt",encodeDirectory ,self.baseFileName] error:nil];
//		}
//#endif
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
        setxattr([captionFilePath cStringUsingEncoding:NSASCIIStringEncoding], [kMTXATTRFileComplete UTF8String], [[NSData data] bytes], 0, 0, 0);  //This is for a checkpoint and tell us the file is complete
        setxattr([commercialFilePath cStringUsingEncoding:NSASCIIStringEncoding], [kMTXATTRFileComplete UTF8String], [[NSData data] bytes], 0, 0, 0);  //This is for a checkpoint and tell us the file is complete

    };

	NSMutableArray *arguments = [NSMutableArray array];
    if (_encodeFormat.comSkipOptions.length) [arguments addObjectsFromArray:[self getArguments:_encodeFormat.comSkipOptions]];
    NSRange iniRange = [_encodeFormat.comSkipOptions rangeOfString:@"--ini="];
#if comSkip92
	[arguments addObject:[NSString stringWithFormat: @"--output=%@",[commercialFilePath stringByDeletingLastPathComponent]]];  //0.92 version
#endif
    if (iniRange.location == NSNotFound) {
        [arguments addObject:[NSString stringWithFormat: @"--ini=%@",[[NSBundle mainBundle] pathForResource:@"comskip" ofType:@"ini"]]];
    }
    
	[arguments addObject:_decryptBufferFilePath];  // Run this on the output of tivodecode
	DDLogVerbose(@"comskip Path: %@",[[NSBundle mainBundle] pathForResource:@"comskip" ofType:@""]);
	DDLogVerbose(@"comskip args: %@",arguments);
	[commercialTask setArguments:arguments];
    _commercialTask = commercialTask;
    return _commercialTask;
  
}

-(MTTask *)apmTask
{
    if (! (self.includeAPMMetaData.boolValue && self.encodeFormat.canAtomicParsley)) {
		return nil;
	}
    if (_apmTask) {
        return _apmTask;
    }
	MTTask *apmTask = [MTTask newWithTaskName:@"apm" download:self];
    
    apmTask.startupHandler = ^(){
        [self setValue:[NSNumber numberWithInt:kMTStatusMetaDataProcessing] forKeyPath:@"downloadStatus"];
        self.processProgress = 0.0;
        [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationProgressUpdated object:nil];
    };
    
    apmTask.completionHandler = ^(){[self finishUpPostEncodeProcessing];};
    
	[apmTask setLaunchPath:[[NSBundle mainBundle] pathForResource:@"AtomicParsley" ofType: @""] ];
    apmTask.requiresOutputPipe = NO;
    apmTask.requiresInputPipe = NO;
	NSMutableArray *apmArgs =[NSMutableArray array];
	[apmArgs addObject:_encodeFilePath];
	[apmArgs addObjectsFromArray:[self.show apmArguments]];
	
	DDLogVerbose(@"APM Arguments: %@", apmArgs);
	[apmTask setArguments:apmArgs];
	
	[apmTask setStandardOutput:apmTask.logFileWriteHandle];
    apmTask.trackingRegEx = [NSRegularExpression regularExpressionWithPattern:@"(\\d+)%" options:NSRegularExpressionCaseInsensitive error:nil];
    _apmTask = apmTask;
    return _apmTask;

}


-(void)download
{
	DDLogDetail(@"Starting download for %@",self);
	isCanceled = NO;
    //Before starting make sure the encoder is OK.
	if (![self encoderPath]) {
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
    NSPipe *taskInputPipe = [NSPipe pipe];
	self.activeTaskChain.dataSource = taskInputPipe;
    taskChainInputHandle = [taskInputPipe fileHandleForWriting];
	
    NSMutableArray *taskArray = [NSMutableArray array];
	
	[taskArray addObject:@[self.decryptTask]];
	
	if (self.captionTask) {
		if (self.commercialTask) {
			[taskArray addObject:@[self.captionTask,[self catTask:_decryptBufferFilePath]]];
			[taskArray addObject:@[self.commercialTask]];
			[taskArray addObject:@[self.encodeTask]];
		} else if (_encodeFormat.canSimulEncode) {
			[taskArray addObject:@[self.encodeTask,self.captionTask]];
		} else {
			[taskArray addObject:@[self.captionTask,[self catTask:_decryptBufferFilePath]]];
			[taskArray addObject:@[self.encodeTask]];
		}
	} else {
		if (self.commercialTask) {
			[taskArray addObject:@[self.commercialTask]];
		}
		[taskArray addObject:@[self.encodeTask]];
	}
	if (self.apmTask) {
		[taskArray addObject:@[self.apmTask]];
	}
	
	self.activeTaskChain.taskArray = [NSArray arrayWithArray:taskArray];
    
    totalDataRead = 0;
    totalDataDownloaded = 0;

    NSURLRequest *thisRequest = [NSURLRequest requestWithURL:self.show.downloadURL];
    activeURLConnection = [[NSURLConnection alloc] initWithRequest:thisRequest delegate:self startImmediately:NO] ;
	downloadingURL = YES;
    dataDownloaded = 0.0;
    _processProgress = 0.0;
	DDLogVerbose(@"launching URL for download %@", _show.downloadURL);
	previousProcessProgress = 0.0;
    
	[self.activeTaskChain run];
	[activeURLConnection start];
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
	[self addXAttrs:self.encodeFilePath];
    [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationDetailsLoaded object:_show];
	
	[self setValue:[NSNumber numberWithInt:kMTStatusDone] forKeyPath:@"downloadStatus"];
    _processProgress = 1.0;
	[[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationProgressUpdated object:nil];
	[tiVoManager  notifyWithTitle:@"TiVo show transferred." subTitle:self.show.showTitle forNotification:kMTGrowlEndDownload];
	
	[self cleanupFiles];
}


-(void)cancel
{
    DDLogMajor(@"Canceling of         %@", self.show.showTitle);
//    NSFileManager *fm = [NSFileManager defaultManager];
    isCanceled = YES;
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:NSFileHandleReadCompletionNotification object:bufferFileReadHandle];
    if (activeURLConnection) {
        [activeURLConnection cancel];
        activeURLConnection = nil;
	}
    if(self.activeTaskChain.isRunning) {
        [self.activeTaskChain cancel];
    }
    _decryptTask = _captionTask = _commercialTask = _encodeTask = _apmTask = nil;
    
	NSDate *now = [NSDate date];
    while (writingData && (-1.0 * [now timeIntervalSinceNow]) < 5.0){ //Wait for no more than 5 seconds.
        //Block until latest write data is complete - should stop quickly because isCanceled is set
		writingData = NO;
    } //Wait for pipe out to complete
    
    [self cleanupFiles]; //Everything but the final file
//    if ([_downloadStatus intValue] == kMTStatusEncoding || (_simultaneousEncode && self.isDownloading)) {
        [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationEncodeWasCanceled object:self];
//    }
    if ([_downloadStatus intValue] == kMTStatusCaptioning) {
        [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationCaptionWasCanceled object:self];
    }
    if ([_downloadStatus intValue] == kMTStatusCommercialing) {
        [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationCommercialWasCanceled object:self];
    }
    [self setValue:[NSNumber numberWithInt:kMTStatusNew] forKeyPath:@"downloadStatus"];
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
	isCanceled = YES;
	[self performSelectorOnMainThread:@selector(rescheduleShowWithDecrementRetries:) withObject:@YES waitUntilDone:NO];
}

-(void)writeData
{
	//	writingData = YES;
	int chunkSize = 50000;
	unsigned long dataRead;
	@autoreleasepool {
		NSData *data = nil;
		if (!isCanceled) {
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
				[self rescheduleOnMain];
				DDLogDetail(@"buffer read fail:%@; rescheduling", exception.reason);
			}
			@finally {
			}
		}
		if (!isCanceled){
			@try {
                if (data.length) {
                    [taskChainInputHandle writeData:data];
                }
			}
			@catch (NSException *exception) {
				[self rescheduleOnMain];
				DDLogDetail(@"download write fail: %@; rescheduling", exception.reason);
			}
			@finally {
			}
		}
		dataRead = data.length;
        totalDataRead += dataRead;
		while (dataRead == chunkSize && !isCanceled) {
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
					[self rescheduleOnMain];
					DDLogDetail(@"buffer read fail2: %@; rescheduling", exception.reason);
				}
				@finally {
				}
				if (!isCanceled) {
					@try {
                        if (data.length) {
                            [taskChainInputHandle writeData:data];
                        }
					}
					@catch (NSException *exception) {
						[self rescheduleOnMain];
						DDLogDetail(@"download write fail2: %@; rescheduling", exception.reason);
					}
					@finally {
					}
				}
				if (isCanceled) break;
				dataRead = data.length;
                totalDataRead += dataRead;
				//		dataDownloaded += data.length;
				_processProgress = totalDataRead/_show.fileSize;
				[self performSelectorOnMainThread:@selector(updateProgress) withObject:nil waitUntilDone:NO];
			}
		}
	}
	if (!activeURLConnection || isCanceled) {
		DDLogDetail(@"Closing taskChainHandle for show %@",self.show.showTitle);
		[taskChainInputHandle closeFile];
		DDLogDetail(@"closed filehandle");
		taskChainInputHandle = nil;
        if ([bufferFileReadHandle isKindOfClass:[NSFileHandle class]]) {
            [bufferFileReadHandle closeFile];
        }
		bufferFileReadHandle = nil;
        if (self.shouldSimulEncode && !isCanceled) {
            [self setValue:[NSNumber numberWithInt:kMTStatusEncoded] forKeyPath:@"downloadStatus"];
        }
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
		NSLog(@"Starting new thread");
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
        [self setValue:[NSNumber numberWithInt:kMTStatusEncoding] forKeyPath:@"downloadStatus"];
    }
	downloadingURL = NO;
	activeURLConnection = nil;
    //Make sure to flush the last of the buffer file into the pipe and close it.
	if (!writingData) {
        DDLogVerbose (@"writing last data for %@",self);
		writingData = YES;
		NSLog(@"Starting new thread");
		[self performSelectorInBackground:@selector(writeData) withObject:nil];
	}
	
	if (downloadedFileSize < kMTMinTiVoFileSize) { //Not a good download - reschedule
		NSString *dataReceived = [NSString stringWithContentsOfFile:_bufferFilePath encoding:NSUTF8StringEncoding error:nil];
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
		self.show.fileSize = downloadedFileSize;  //More accurate file size
		NSNotification *not = [NSNotification notificationWithName:kMTNotificationDownloadDidFinish object:self.show.tiVo];
		[[NSNotificationCenter defaultCenter] performSelector:@selector(postNotification:) withObject:not afterDelay:4.0];
	}
}


#pragma mark Convenience methods

-(BOOL) canSimulEncode {
    return self.encodeFormat.canSimulEncode;
}

-(BOOL) shouldSimulEncode {
    return (_encodeFormat.canSimulEncode && !_skipCommercials);
}

-(BOOL) canSkipCommercials {
    return self.encodeFormat.comSkip.boolValue;
}

-(BOOL) shouldSkipCommercials {
    return _skipCommercials;
}

-(BOOL) canAddToiTunes {
    return self.encodeFormat.canAddToiTunes;
}

-(BOOL) shouldAddToiTunes {
    return _addToiTunesWhenEncoded;
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
        BOOL simulWasDisabled = ![self canSimulEncode];
        BOOL iTunesWasDisabled = ![self canAddToiTunes];
        BOOL skipWasDisabled = ![self canSkipCommercials];
        _encodeFormat = encodeFormat;
        if (!self.canSimulEncode && self.shouldSimulEncode) {
            //no longer possible
            self.simultaneousEncode = NO;
        } else if (simulWasDisabled && [self canSimulEncode]) {
            //newly possible, so take user default
            self.simultaneousEncode = [[NSUserDefaults standardUserDefaults] boolForKey:kMTSimultaneousEncode];
        }
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

