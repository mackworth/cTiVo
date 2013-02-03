//
//  MTTiVoShow.m
//  cTiVo
//
//  Created by Scott Buchanan on 12/18/12.
//  Copyright (c) 2012 Scott Buchanan. All rights reserved.
//
// Class for handling individual TiVo Shows

#import "MTTiVoShow.h"
#import "MTProgramTableView.h"
#import "MTiTunes.h"
#import "MTTiVoManager.h"


@implementation MTTiVoShow

@synthesize encodeFilePath   = _encodeFilePath,
			downloadFilePath = _downloadFilePath,
			bufferFilePath   = _bufferFilePath,
			seriesTitle = _seriesTitle,
			episodeTitle = _episodeTitle,
			tempTiVoName     = _tempTiVoName;


-(id)init
{
    self = [super init];
    if (self) {
        encoderTask = nil;
        _showID = 0;
        _showStatus = @"";
		decryptFilePath = nil;
        commercialFilePath = nil;
        _addToiTunesWhenEncoded = NO;
        _simultaneousEncode = YES;
		encoderTask = nil;
		decrypterTask = nil;
		writingData = NO;
		downloadingURL = NO;
		pipingData = NO;
		gotDetails = NO;
        _isSelected = NO;
        _isQueued = NO;
		elementString = nil;
        pipe1 = nil;
        pipe2 = nil;
		_vActor = nil;
		_vExecProducer = nil;
        _vDirector = nil;
        _vGuestStar = nil;
        devNullFileHandle = [[NSFileHandle fileHandleForWritingAtPath:@"/dev/null"] retain];
		_season = 0;
		_episode = 0;
		_episodeNumber = @"";
		_episodeTitle = @"";
		_seriesTitle = @"";
//		_originalAirDate = @"";
		_episodeYear = 0;
		self.protectedShow = @(NO); //This is the default
		self.inProgress = @(NO); //This is the default
		parseTermMapping = [@{@"description" : @"showDescription", @"time": @"showTime"} retain];
        [self addObserver:self forKeyPath:@"downloadStatus" options:NSKeyValueObservingOptionNew context:nil];
        previousCheck = [[NSDate date] retain];
    }
    return self;
}

-(void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if ([keyPath compare:@"downloadStatus"] == NSOrderedSame) {
//		NSLog(@"QQQChanging DL status of %@ to %@", [(MTTiVoShow *)object showTitle], [(MTTiVoShow *)object downloadStatus]);
        [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationDownloadStatusChanged object:nil];
    }
}

-(NSNumber *)downloadIndex
{
    NSInteger index = [tiVoManager.downloadQueue indexOfObject:self];
    return [NSNumber numberWithInteger:index+1];
}

-(void)setInProgress:(NSNumber *)inProgress
{
	if (_inProgress != inProgress) {
		[_inProgress release];
		_inProgress = [inProgress retain];
		if ([_inProgress boolValue]) {
			self.protectedShow = @(YES);
		}
	}
}


-(NSArray *)parseNames:(NSArray *)nameSet
{
	if (!nameSet || ![nameSet respondsToSelector:@selector(count)] || nameSet.count == 0) {
		return nameSet;
	}
	NSRegularExpression *nameParse = [NSRegularExpression regularExpressionWithPattern:@"([^|]*)\\|([^|]*)" options:NSRegularExpressionCaseInsensitive error:nil];
	NSMutableArray *newNames = [NSMutableArray array];
	for (NSString *name in nameSet) {
		NSTextCheckingResult *match = [nameParse firstMatchInString:name options:NSMatchingWithoutAnchoringBounds range:NSMakeRange(0, name.length)];
		NSString *lastName = [name substringWithRange:[match rangeAtIndex:1]];
		NSString *firstName = [name substringWithRange:[match rangeAtIndex:2]];
		[newNames addObject:@{kMTLastName : lastName, kMTFirstName : firstName}];
	}
	return [NSArray arrayWithArray:newNames];
}

-(NSString *)nameString:(NSDictionary *)nameDictionary
{
    return [NSString stringWithFormat:@"%@ %@",nameDictionary[kMTFirstName] ? nameDictionary[kMTFirstName] : @"" ,nameDictionary[kMTLastName] ? nameDictionary[kMTLastName] : @"" ];
}

-(void)setShowLengthString:(NSString *)showLengthString
{
	if (showLengthString != _showLengthString) {
		[_showLengthString release];
		_showLengthString = [showLengthString retain];
		_showLength = [_showLengthString longLongValue]/1000;
	}
}

//-(void)getShowDetailWithNotification
//{
//	if (gotDetails) {
//		return;
//	}
//	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init]	;
//	[self getShowDetail];
//	if (gotDetails) {
//		NSNotification *n = [NSNotification notificationWithName:kMTNotificationReloadEpisode object:self];
//		[[NSNotificationCenter defaultCenter] performSelectorOnMainThread:@selector(postNotification:) withObject:n  waitUntilDone:NO];
//	} else {
//		NSLog(@"Got Details Failed for %@",_showTitle);
//	}
//	[pool drain];
//}

-(void)getShowDetail
{
	if (gotDetails) {
		return;
	}
	gotDetails = YES;
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init]	;
//	NSString *detailURLString = [NSString stringWithFormat:@"https://%@/TiVoVideoDetails?id=%d",_tiVo.tiVo.hostName,_showID];
//	NSLog(@"Show Detail URL %@",detailURLString);
	NSURLResponse *detailResponse = nil;
	NSURLRequest *detailRequest = [NSURLRequest requestWithURL:_detailURL];;
	NSData *xml = [NSURLConnection sendSynchronousRequest:detailRequest returningResponse:&detailResponse error:nil];
	parser = [[[NSXMLParser alloc] initWithData:xml] autorelease];
	parser.delegate = self;
	[parser parse];
	self.vActor = [self parseNames:_vActor];
	self.vExecProducer = [self parseNames:_vExecProducer];
	self.vGuestStar = [self parseNames:_vGuestStar];
	self.vDirector = [self parseNames:_vDirector];
	if (!gotDetails) {
		NSLog(@"GetDetails Fail for %@",_showTitle);
		NSLog(@"Returned XML is %@",[[[NSString alloc] initWithData:xml encoding:NSUTF8StringEncoding	] autorelease]	);
	}
	NSNotification *notification = [NSNotification notificationWithName:kMTNotificationDetailsLoaded object:self];
    [[NSNotificationCenter defaultCenter] performSelectorOnMainThread:@selector(postNotification:) withObject:notification waitUntilDone:NO];
	[pool drain];
}

-(void)rescheduleShow:(NSNumber *)decrementRetries
{
	NSLog(@"Stalled, %@ download of %@ with progress at %lf with previous check at %@",(_numRetriesRemaining > 0) ? @"restarting":@"canceled",  _showTitle, _processProgress, previousCheck );
	[self cancel];
	if (_numRetriesRemaining <= 0 || _numStartupRetriesRemaining <=0) {
		[self setValue:[NSNumber numberWithInt:kMTStatusFailed] forKeyPath:@"downloadStatus"];
		_showStatus = @"Failed";
		_processProgress = 1.0;
		[[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationProgressUpdated object:nil];
		
		[tiVoManager  notifyWithTitle: @"TiVo show failed; cancelled."
					  subTitle:self.showTitle forNotification:kMTGrowlEndDownload];
		
		//			[[MTTiVoManager sharedTiVoManager] deleteProgramFromDownloadQueue:self];
	} else {
		if ([decrementRetries boolValue]) {
			_numRetriesRemaining--;
			[tiVoManager  notifyWithTitle:@"TiVo show failed; retrying..." subTitle:self.showTitle forNotification:kMTGrowlEndDownload];
		} else {
            _numStartupRetriesRemaining--;
        }
		[self setValue:[NSNumber numberWithInt:kMTStatusNew] forKeyPath:@"downloadStatus"];
	}
    NSNotification *notification = [NSNotification notificationWithName:kMTNotificationDownloadQueueUpdated object:self.tiVo];
    [[NSNotificationCenter defaultCenter] performSelector:@selector(postNotification:) withObject:notification afterDelay:4.0];
	
}

#pragma mark - Queue methods
#pragma mark - NSCoding

- (void) encodeWithCoder:(NSCoder *)encoder {
	//necessary for cut/paste drag/drop. Not used for persistent queue, as we like having english readable pref lists
	//keep parallel with queueRecord

	[encoder encodeObject:[NSNumber numberWithInteger: _showID] forKey: kMTQueueID];
	[encoder encodeObject:_showTitle forKey: kMTQueueTitle];
	[encoder encodeObject:_tiVo.tiVo.name forKey: kMTQueueTivo];
	[encoder encodeObject:[NSNumber numberWithBool:_addToiTunesWhenEncoded] forKey: kMTSubscribediTunes];
	[encoder encodeObject:[NSNumber numberWithBool:_simultaneousEncode] forKey: kMTSubscribedSimulEncode];
	[encoder encodeObject:[NSNumber numberWithBool:_skipCommercials] forKey: kMTSubscribedSkipCommercials];
	[encoder encodeObject:_encodeFormat.name forKey:kMTQueueFormat];
	[encoder encodeObject:_downloadStatus forKey: kMTQueueStatus];
	[encoder encodeObject:_showStatus forKey: kMTQueueShowStatus];
	[encoder encodeObject: _downloadDirectory forKey: kMTQueueDirectory];
	[encoder encodeObject: _downloadFilePath forKey: kMTQueueDownloadFile] ;
	[encoder encodeObject: _bufferFilePath forKey: kMTQueueBufferFile] ;
	[encoder encodeObject: _encodeFilePath forKey: kMTQueueFinalFile] ;

}

- (NSDictionary *) queueRecord {
	//used for persistent queue, as we like having english readable pref lists
	//keep parallel with encodeWithCoder

	return [NSDictionary dictionaryWithObjectsAndKeys:
			[NSNumber numberWithInteger: _showID], kMTQueueID,
			_showTitle, kMTQueueTitle,
			_tiVo.tiVo.name, kMTQueueTivo,
			[NSNumber numberWithBool:_addToiTunesWhenEncoded], kMTSubscribediTunes,
			[NSNumber numberWithBool:_simultaneousEncode], kMTSubscribedSimulEncode,
			[NSNumber numberWithBool:_skipCommercials], kMTSubscribedSkipCommercials,
			_encodeFormat.name,kMTQueueFormat,
			_downloadStatus, kMTQueueStatus,
			_showStatus, kMTQueueShowStatus,
			 _downloadDirectory, kMTQueueDirectory,
			_downloadFilePath, kMTQueueDownloadFile,
			_bufferFilePath, kMTQueueBufferFile,
			_encodeFilePath, kMTQueueFinalFile,
			nil];
}



- (id)initWithCoder:(NSCoder *)decoder {
	//keep parallel with updateFromDecodedShow
	if ((self = [self init])) {
		//NSString *title = [decoder decodeObjectForKey:kTitleKey];
		//float rating = [decoder decodeFloatForKey:kRatingKey];
		_showID   = [[decoder decodeObjectForKey: kMTQueueID] intValue];
		_showTitle= [[decoder decodeObjectForKey: kMTQueueTitle] retain];
		NSString * tivoName = [decoder decodeObjectForKey: kMTQueueTivo] ;
		for (MTTiVo * tiVo in [tiVoManager tiVoList]) {
			if ([tiVo.tiVo.name compare: tivoName] == NSOrderedSame) {
				_tiVo = tiVo;
				break;
			}
		}
		if (!_tiVo) {
			self.tempTiVoName = tivoName;
		}
		_addToiTunesWhenEncoded= [[decoder decodeObjectForKey: kMTSubscribediTunes] boolValue];
		_simultaneousEncode	 =   [[decoder decodeObjectForKey: kMTSubscribedSimulEncode] boolValue];
		_skipCommercials   =     [[decoder decodeObjectForKey: kMTSubscribedSkipCommercials] boolValue];
		NSString * encodeName	 = [decoder decodeObjectForKey:kMTQueueFormat];
		_encodeFormat =	[[tiVoManager findFormat: encodeName] retain]; //minor bug here: will not be able to restore a no-longer existent format, so will substitue with first one available, which is then wrong for completed/failed entries
		_downloadStatus		 = [[decoder decodeObjectForKey: kMTQueueStatus] retain];
		_showStatus			 = [[decoder decodeObjectForKey: kMTQueueShowStatus] retain];
		_bufferFilePath = [[decoder decodeObjectForKey:kMTQueueBufferFile] retain];
		_downloadFilePath = [[decoder decodeObjectForKey:kMTQueueDownloadFile] retain];
		_encodeFilePath = [[decoder decodeObjectForKey:kMTQueueFinalFile] retain];
	}
	return self;
}

-(void) updateFromDecodedShow:(MTTiVoShow *) newShow {
	//copies details that were encoded into current show
	//Keep parallel with InitWithDecoder
	//Assumed that showID and showTItle and TiVO are already matched
	_addToiTunesWhenEncoded = newShow.addToiTunesWhenEncoded;
	if ([newShow.downloadStatus intValue] != kMTStatusNew){
		//previously failed or completed, but don't stomp on inprogress
		_downloadStatus = [newShow.downloadStatus retain];
	}
	if (!self.isInProgress) {
		_simultaneousEncode = newShow.simultaneousEncode;
		_addToiTunesWhenEncoded = newShow.addToiTunesWhenEncoded;
		_skipCommercials = newShow.skipCommercials;
		if (newShow.showStatus) {
			self.showStatus = newShow.showStatus;
		} else {
			self.showStatus = @"";
		}
		self.downloadDirectory = newShow.downloadDirectory;
		_encodeFilePath = [newShow.encodeFilePath retain];
		_downloadFilePath = [newShow.downloadFilePath retain];
		_bufferFilePath = [newShow.bufferFilePath retain];
		
	}
}


- (id)pasteboardPropertyListForType:(NSString *)type {
	if ([type compare:kMTTivoShowPasteBoardType] ==NSOrderedSame) {
		return  [NSKeyedArchiver archivedDataWithRootObject:self];
/* NOT working yet
 } else if ([type compare:(NSString *)kUTTypeFileURL] ==NSOrderedSame) {
		if (self.downloadStatus.integerValue ==kMTStatusDone) {
			if (self.encodeFilePath) {
				NSArray * urls = @[[NSURL fileURLWithPath:self.encodeFilePath isDirectory:NO]];
				//id data = [urls pasteboardPropertyListForType:(NSString *)kUTTypeFileURL];
				NSLog(@"Returning %@", urls);
				return urls;
			} else {
				return nil;
			}
		} else {
			return nil;
		}
 */
	} else {
		return nil;
	}
}

-(NSArray *)writableTypesForPasteboard:(NSPasteboard *)pasteboard {
	return @[kMTTivoShowPasteBoardType];// ,(NSString *)kUTTypeFileURL];  //NOT working yet
}

- (NSPasteboardWritingOptions)writingOptionsForType:(NSString *)type pasteboard:(NSPasteboard *)pasteboard {
	return 0;
}

+ (NSArray *)readableTypesForPasteboard:(NSPasteboard *)pasteboard {
	return @[kMTTivoShowPasteBoardType];

}
+ (NSPasteboardReadingOptions)readingOptionsForType:(NSString *)type pasteboard:(NSPasteboard *)pasteboard {
	if ([type compare:kMTTivoShowPasteBoardType] ==NSOrderedSame)
		return NSPasteboardReadingAsKeyedArchive;
	return 0;
}

-(BOOL) isSameAs:(NSDictionary *) queueEntry {
	NSInteger queueID = [queueEntry[kMTQueueID] integerValue];
	BOOL result = (queueID == _showID) && ([self.tiVo.tiVo.name compare:queueEntry[kMTQueueTivo]] == NSOrderedSame);
	if (result && [self.showTitle compare:queueEntry[kMTQueueTitle]] != NSOrderedSame) {
		NSLog(@"Very odd, but reloading anyways: same ID: %ld same TiVo:%@ but different titles: <<%@>> vs <<%@>>",queueID, queueEntry[kMTQueueTivo], self.showTitle, queueEntry[kMTQueueTitle] );
	}
	return result;
	
}

-(void) restoreDownloadData:queueEntry {
	_addToiTunesWhenEncoded = [queueEntry[kMTSubscribediTunes ]  boolValue];
	_skipCommercials = [queueEntry[kMTSubscribedSkipCommercials ]  boolValue];
	if (queueEntry[kMTQueueStatus] != kMTStatusNew){
		//previously failed or completed
		_downloadStatus = queueEntry[kMTQueueStatus];
	}
	if (!self.isInProgress) {
		_simultaneousEncode = [queueEntry[kMTSimultaneousEncode] boolValue];
		self.encodeFormat = [tiVoManager findFormat: queueEntry[kMTQueueFormat]]; //bug here: will not be able to restore a no-longer existent format, so will substitue with first one available, which is wrong for completed/failed entries
		if (queueEntry[kMTQueueShowStatus]) {
			self.showStatus = queueEntry[kMTQueueShowStatus];
		} else {
			self.showStatus = @"";
		}
	}
}


-(void)checkStillActive
{
	if (previousProcessProgress == _processProgress) { //The process is stalled so cancel and restart
		//Cancel and restart or delete depending on number of time we've been through this
        [self rescheduleShow:[NSNumber numberWithBool:YES]];
	} else if ([self isInProgress]){
		previousProcessProgress = _processProgress;
		[self performSelector:@selector(checkStillActive) withObject:nil afterDelay:kMTProgressCheckDelay];
	}
    [previousCheck release];
    previousCheck = [[NSDate date] retain];
}

#pragma  mark - parser methods

-(void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName attributes:(NSDictionary *)attributeDict
{
	if (elementString) {
		[elementString release];
	}
	elementString = [NSMutableString new];
	if ([elementName compare:@"element"] != NSOrderedSame) {
		if (elementArray) {
			[elementArray release];
		}
		elementArray = [NSMutableArray new];
	}
}

-(void)parser:(NSXMLParser *)parser foundCharacters:(NSString *)string
{
	[elementString appendString:string];
}

- (void)setValue:(id)value forUndefinedKey:(NSString *)key{
    //nothing to see here; just move along
}


-(void)parser:(NSXMLParser *)parser didEndElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName
{
	if (parseTermMapping[elementName]) {
		elementName = parseTermMapping[elementName];
	}
	if ([elementName compare:@"element"] == NSOrderedSame) {
		[elementArray addObject:elementString];
	} else {
		id item;
		if (elementArray.count) {
			item = [NSArray arrayWithArray:elementArray];
		} else {
			item = elementString;
		}
		@try {
			[self setValue:item forKeyPath:elementName];
		}
		@catch (NSException *exception) {
		}
		@finally {
		}
	}
}

-(void)parser:(NSXMLParser *)parser parseErrorOccurred:(NSError *)parseError
{
	gotDetails = NO;
	NSLog(@"Parser Error %@",parseError);
}

-(NSString *)showTitleForFiles
{
	NSString * safeTitle = [_showTitle stringByReplacingOccurrencesOfString:@"/" withString:@"-"];
	safeTitle = [safeTitle stringByReplacingOccurrencesOfString:@":" withString:@"-"];
	return safeTitle;
}


#pragma mark - Download decrypt and encode Methods

//Method called at the beginning of the download to configure all required files and file handles

-(void)deallocDownloadHandling
{
    if (_downloadFilePath) {
        [_downloadFilePath release];
        _downloadFilePath = nil;
    }
    if (downloadFileHandle && downloadFileHandle != [pipe1 fileHandleForWriting]) {
        [downloadFileHandle release];
        downloadFileHandle = nil;
    }
    if (decrypterTask) {
		if ([decrypterTask isRunning]) {
			[decrypterTask terminate];
		}
        [decrypterTask release];
        decrypterTask = nil;
    }
    if (decryptFilePath) {
        [decryptFilePath release];
        decryptFilePath = nil;
    }
    if (decryptLogFilePath) {
        [decryptLogFilePath release];
        decryptLogFilePath = nil;
    }
    if (decryptLogFileHandle) {
        [decryptLogFileHandle closeFile];
        [decryptLogFileHandle release];
        decryptLogFileHandle = nil;
    }
    if (decryptLogFileReadHandle) {
        [decryptLogFileReadHandle closeFile];
        [decryptLogFileReadHandle release];
        decryptLogFileReadHandle = nil;
    }
    if (commercialFilePath) {
        [commercialFilePath release];
        commercialFilePath = nil;
    }
    if (commercialFileHandle) {
        [commercialFileHandle release];
        commercialFileHandle = nil;
    }
    if (commercialLogFilePath) {
        [commercialLogFilePath release];
        commercialLogFilePath = nil;
    }
    if (commercialLogFileHandle) {
        [commercialLogFileHandle closeFile];
        [commercialLogFileHandle release];
        commercialLogFileHandle = nil;
    }
    if (commercialLogFileReadHandle) {
        [commercialLogFileReadHandle closeFile];
        [commercialLogFileReadHandle release];
        commercialLogFileReadHandle = nil;
    }
    if (encoderTask) {
		if ([encoderTask isRunning]) {
			[encoderTask terminate];
		}
        [encoderTask release];
        encoderTask = nil;
    }
    if (_encodeFilePath) {
        [_encodeFilePath release];
        _encodeFilePath = nil;
    }
    if (encodeFileHandle) {
        [encodeFileHandle closeFile];
        [encodeFileHandle release];
        encodeFileHandle = nil;
    }
    if (encodeLogFilePath) {
        [encodeLogFilePath release];
        encodeLogFilePath = nil;
    }
    if (encodeLogFileHandle) {
        [encodeLogFileHandle closeFile];
        [encodeLogFileHandle release];
        encodeLogFileHandle = nil;
    }
    if (encodeLogFileReadHandle) {
        [encodeLogFileReadHandle closeFile];
        [encodeLogFileReadHandle release];
        encodeLogFileReadHandle = nil;
    }
    if (_bufferFilePath) {
        [_bufferFilePath release];
        _bufferFilePath = nil;
    }
    if (bufferFileReadHandle) {
        [bufferFileReadHandle closeFile];
        [bufferFileReadHandle release];
        bufferFileReadHandle = nil;
    }
    if (bufferFileWriteHandle) {
        [bufferFileWriteHandle closeFile];
        [bufferFileWriteHandle release];
        bufferFileWriteHandle = nil;
    }
    if (pipe1) {
        [pipe1 release];
		pipe1 = nil;
    }
    if (pipe2) {
        [pipe2 release];
		pipe2 = nil;
    }
}

-(NSString *) directoryForShowInDirectory:(NSString*) tryDirectory  {
	//Check that download directory (including show directory) exists.  If create it.  If unsuccessful return nil
	if ([[NSUserDefaults standardUserDefaults] boolForKey:kMTMakeSubDirs] && ![self isMovie]){
		tryDirectory = [tryDirectory stringByAppendingPathComponent:self.seriesTitle];
	}
	if (![[NSFileManager defaultManager] fileExistsAtPath: tryDirectory]) { // try to create it
		if (![[NSFileManager defaultManager] createDirectoryAtPath:tryDirectory withIntermediateDirectories:YES attributes:nil error:nil]) {
			return nil;
		}
	}
	return tryDirectory;
}


-(void)configureFiles
{
    //Release all previous attached pointers
    [self deallocDownloadHandling];
	NSString *downloadDir = [self directoryForShowInDirectory:[self downloadDirectory]];

	//go to current directory if one at show scheduling time failed
	if (!downloadDir) {
		downloadDir = [self directoryForShowInDirectory:[tiVoManager downloadDirectory]];
	}
    
	//finally, go to default if not successful
	if (!downloadDir) {
		downloadDir = [self directoryForShowInDirectory:[tiVoManager defaultDownloadDirectory]];
	}
    _encodeFilePath = [[NSString stringWithFormat:@"%@/%@%@",downloadDir,self.showTitleForFiles,_encodeFormat.filenameExtension] retain];
    NSFileManager *fm = [NSFileManager defaultManager];
    if (_simultaneousEncode) {
        //Things require uniquely for simultaneous download
        pipe1 = [[NSPipe pipe] retain];
        pipe2 = [[NSPipe pipe] retain];
		downloadFileHandle = [pipe1 fileHandleForWriting];
        _bufferFilePath = [[NSString stringWithFormat:@"/tmp/buffer%@.bin",self.showTitleForFiles] retain];
        [fm createFileAtPath:_bufferFilePath contents:[NSData data] attributes:nil];
        bufferFileReadHandle = [[NSFileHandle fileHandleForReadingAtPath:_bufferFilePath] retain];
        bufferFileWriteHandle = [[NSFileHandle fileHandleForWritingAtPath:_bufferFilePath] retain];
    } else {
        //Things require uniquely for sequential download
        _downloadFilePath = [[NSString stringWithFormat:@"%@/%@.tivo",downloadDir ,self.showTitleForFiles] retain];
        [fm createFileAtPath:_downloadFilePath contents:[NSData data] attributes:nil];
        downloadFileHandle = [[NSFileHandle fileHandleForWritingAtPath:_downloadFilePath] retain];
		decryptFilePath = [[NSString stringWithFormat:@"%@/%@.tivo.mpg",downloadDir ,self.showTitleForFiles] retain];
        decryptLogFilePath = [[NSString stringWithFormat:@"/tmp/decrypting%@.txt",self.showTitleForFiles] retain];
        [fm createFileAtPath:decryptLogFilePath contents:[NSData data] attributes:nil];
        decryptLogFileHandle = [[NSFileHandle fileHandleForWritingAtPath:decryptLogFilePath] retain];
        decryptLogFileReadHandle = [[NSFileHandle fileHandleForReadingAtPath:decryptLogFilePath] retain];
        commercialLogFilePath = [[NSString stringWithFormat:@"/tmp/commercial%@.txt",self.showTitleForFiles] retain];
        [fm createFileAtPath:commercialLogFilePath contents:[NSData data] attributes:nil];
        commercialLogFileHandle = [[NSFileHandle fileHandleForWritingAtPath:commercialLogFilePath] retain];
        commercialLogFileReadHandle = [[NSFileHandle fileHandleForReadingAtPath:commercialLogFilePath] retain];
        
    }
    
    encodeLogFilePath = [[NSString stringWithFormat:@"/tmp/encoding%@.txt",self.showTitleForFiles] retain];
    [fm createFileAtPath:encodeLogFilePath contents:[NSData data] attributes:nil];
    encodeLogFileHandle = [[NSFileHandle fileHandleForWritingAtPath:encodeLogFilePath] retain];
    encodeLogFileReadHandle = [[NSFileHandle fileHandleForReadingAtPath:encodeLogFilePath] retain];
}

-(NSString *) encoderPath {
	NSString *encoderLaunchPath = [_encodeFormat pathForExecutable];
    if (!encoderLaunchPath) {
        NSLog(@"Encoding of %@ failed for %@ format, encoder %@ not found",_showTitle,_encodeFormat.name,_encodeFormat.encoderUsed);
        [self setValue:[NSNumber numberWithInt:kMTStatusFailed] forKeyPath:@"downloadStatus"];
        _showStatus = @"Failed";
        _processProgress = 1.0;
        [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationProgressUpdated object:nil];
        return nil;
    } else {
		return encoderLaunchPath;
	}
}


-(void)download
{
	isCanceled = NO;
    //Before starting make sure the encoder is OK.
	NSString *encoderLaunchPath = [self encoderPath];
	if (!encoderLaunchPath) {
		return;
	}

    [self setValue:[NSNumber numberWithInt:kMTStatusDownloading] forKeyPath:@"downloadStatus"];
    _showStatus = @"Downloading";
	if (!gotDetails) {
		[self getShowDetail];
//		[[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationTiVoShowsUpdated object:nil];
	}
    if (_simultaneousEncode && !_encodeFormat.canSimulEncode) {  //last chance check
        _simultaneousEncode = NO;
    }
    [self configureFiles];
    NSURLRequest *thisRequest = [NSURLRequest requestWithURL:_downloadURL];
//    activeURLConnection = [NSURLConnection connectionWithRequest:thisRequest delegate:self];
    activeURLConnection = [[[NSURLConnection alloc] initWithRequest:thisRequest delegate:self startImmediately:NO] autorelease];

//Now set up for either simul or sequential download
    NSLog(@"Starting %@ of %@", (_simultaneousEncode ? @"simul DL" : @"download"), _showTitle);
	[tiVoManager  notifyWithTitle: [NSString stringWithFormat: @"TiVo %@ starting download...",self.tiVo.tiVo.name]
													 subTitle:self.showTitle forNotification:kMTGrowlBeginDownload];
	 if (!_simultaneousEncode ) {
        _isSimultaneousEncoding = NO;
    } else { //We'll build the full piped download chain here
       //Decrypting section of full pipeline
        decrypterTask  = [[NSTask alloc] init];
        NSString *tivodecoderLaunchPath = [[NSBundle mainBundle] pathForResource:@"tivodecode" ofType:@""];
		[decrypterTask setLaunchPath:tivodecoderLaunchPath];
		NSMutableArray *arguments = [NSMutableArray arrayWithObjects:
                        [NSString stringWithFormat:@"-m%@",_tiVo.mediaKey],
                        @"--",
                        @"-",
                        nil];
        [decrypterTask setArguments:arguments];
        [decrypterTask setStandardInput:pipe1];
        [decrypterTask setStandardOutput:pipe2];
		encoderTask = [[NSTask alloc] init];
		[encoderTask setLaunchPath:encoderLaunchPath];
		[encoderTask setArguments:[self encodingArgumentsWithInputFile:@"-" outputFile:_encodeFilePath]];
		[encoderTask setStandardInput:pipe2];
		[encoderTask setStandardOutput:encodeLogFileHandle];
		[encoderTask setStandardError:encodeLogFileHandle];
        [decrypterTask launch];
        [encoderTask launch];
        _isSimultaneousEncoding = YES;
    }
	downloadingURL = YES;
    dataDownloaded = 0.0;
    _processProgress = 0.0;
	previousProcessProgress = 0.0;
	[activeURLConnection start];
	[self performSelector:@selector(checkStillActive) withObject:nil afterDelay:kMTProgressCheckDelay];
}

-(void)trackDownloadEncode
{
    if([encoderTask isRunning]) {
        [self performSelector:@selector(trackDownloadEncode) withObject:nil afterDelay:0.3];
    } else {
        NSLog(@"Finished simul DL of %@", _showTitle);
 		[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(checkStillActive) object:nil];
       [self setValue:[NSNumber numberWithInt:kMTStatusDone] forKeyPath:@"downloadStatus"];
        _showStatus = @"Complete";
        _processProgress = 1.0;
        [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationProgressUpdated object:nil];
        [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationEncodeDidFinish object:self];

		[tiVoManager  notifyWithTitle:@"TiVo show transferred." subTitle:self.showTitle forNotification:kMTGrowlEndDownload];
        
        if (_addToiTunesWhenEncoded) {
			MTiTunes *iTunes = [[[MTiTunes alloc] init] autorelease];
			[iTunes importIntoiTunes:self];
        }
		[self cleanupFiles];
    }
}

-(void)decrypt
{
	NSLog(@"Starting Decrypt of  %@", _showTitle);
	decrypterTask = [[NSTask alloc] init];
	[decrypterTask setLaunchPath:[[NSBundle mainBundle] pathForResource:@"tivodecode" ofType:@""]];
	[decrypterTask setStandardOutput:decryptLogFileHandle];
	[decrypterTask setStandardError:decryptLogFileHandle];	
    // tivodecode -m0636497662 -o Two\ and\ a\ Half\ Men.mpg -v Two\ and\ a\ Half\ Men.TiVo
    
	NSArray *arguments = [NSArray arrayWithObjects:
						  [NSString stringWithFormat:@"-m%@",_tiVo.mediaKey],
						  [NSString stringWithFormat:@"-o%@",decryptFilePath],
						  @"-v",
						  _downloadFilePath,
						  nil];
    _processProgress = 0.0;
	previousProcessProgress = 0.0;
	[self performSelector:@selector(checkStillActive) withObject:nil afterDelay:kMTProgressCheckDelay];
 	[[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationProgressUpdated object:nil];
    [self setValue:[NSNumber numberWithInt:kMTStatusDecrypting] forKeyPath:@"downloadStatus"];
	_showStatus = @"Decrypting";
	[decrypterTask setArguments:arguments];
	[decrypterTask launch];
	[self performSelector:@selector(trackDecrypts) withObject:nil afterDelay:0.3];
	
}

-(void)trackDecrypts
{
	if (![decrypterTask isRunning]) {
		[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(checkStillActive) object:nil];
        NSLog(@"Finished Decrypt of  %@", _showTitle);
		_processProgress = 1.0;
		[[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationProgressUpdated object:nil];
        [self setValue:[NSNumber numberWithInt:kMTStatusDecrypted] forKeyPath:@"downloadStatus"];
        _showStatus = @"Wait for encoder";
		NSError *thisError = nil;
		[[NSFileManager defaultManager] removeItemAtPath:_downloadFilePath error:&thisError];
       [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationDecryptDidFinish object:self.tiVo];
		return;
	}
	unsigned long long logFileSize = [decryptLogFileReadHandle seekToEndOfFile];
	if (logFileSize > 100) {
		[decryptLogFileReadHandle seekToFileOffset:(logFileSize-100)];
		NSData *tailOfFile = [decryptLogFileReadHandle readDataOfLength:100];
		NSString *data = [[[NSString alloc] initWithData:tailOfFile encoding:NSUTF8StringEncoding] autorelease];
		NSArray *lines = [data componentsSeparatedByString:@"\n"];
		data = [lines objectAtIndex:lines.count-2];
		lines = [data componentsSeparatedByString:@":"];
		double position = [[lines objectAtIndex:0] doubleValue];
		_processProgress = position/_fileSize;
		[[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationProgressUpdated object:nil];
       
	}
	[self performSelector:@selector(trackDecrypts) withObject:nil afterDelay:0.3];
    
    [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationProgressUpdated object:nil];
	
	
}

-(void)commercial
{
	NSLog(@"Starting comskip of  %@", _showTitle);
	commercialTask = [[NSTask alloc] init];
	[commercialTask setLaunchPath:[[NSBundle mainBundle] pathForResource:@"comskip" ofType:@""]];
	[commercialTask setStandardOutput:commercialLogFileHandle];
	[commercialTask setStandardError:commercialLogFileHandle];
	NSMutableArray *arguments = [NSMutableArray array];
    if (_encodeFormat.comSkipOptions.length) [arguments addObjectsFromArray:[self getArguments:_encodeFormat.comSkipOptions]];
    [arguments addObject:@"--output=/tmp/"];
	[arguments addObject:decryptFilePath];
    [commercialTask setArguments:arguments];
    _processProgress = 0.0;
	previousProcessProgress = 0.0;
	[commercialTask launch];
	[self setValue:[NSNumber numberWithInt:kMTStatusCommercialing] forKeyPath:@"downloadStatus"];
	_showStatus = @"Detecting Commercials";
	[self performSelector:@selector(trackCommercial) withObject:nil afterDelay:3.0];
}

-(void)trackCommercial
{
	if (![commercialTask isRunning]) {
		[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(checkStillActive) object:nil];
        NSLog(@"Finished detecting commercials in %@",_showTitle);
        _processProgress = 1.0;
		[commercialTask release];
		commercialTask = nil;
        _showStatus = @"Commercials Detected";
        [self setValue:[NSNumber numberWithInt:kMTStatusCommercialed] forKeyPath:@"downloadStatus"];
		[[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationProgressUpdated object:nil];
        [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationCommercialDidFinish object:self];
		return;
	}
	double newProgressValue = 0;
	unsigned long long logFileSize = [commercialLogFileReadHandle seekToEndOfFile];
	if (logFileSize > 100) {
		[commercialLogFileReadHandle seekToFileOffset:(logFileSize-100)];
		NSData *tailOfFile = [commercialLogFileReadHandle readDataOfLength:100];
		NSString *data = [[[NSString alloc] initWithData:tailOfFile encoding:NSUTF8StringEncoding] autorelease];
		
		NSRegularExpression *percents = [NSRegularExpression regularExpressionWithPattern:@"(\\d+)\\%" options:NSRegularExpressionCaseInsensitive error:nil];
		NSArray *values = [percents matchesInString:data options:NSMatchingWithoutAnchoringBounds range:NSMakeRange(0, data.length)];
		NSTextCheckingResult *lastItem = [values lastObject];
		NSRange valueRange = [lastItem rangeAtIndex:1];
		newProgressValue = [[data substringWithRange:valueRange] doubleValue]/100.0;
		[[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationProgressUpdated object:nil];
		if (newProgressValue > _processProgress) {
			_processProgress = newProgressValue;
		}
	}
	[self performSelector:@selector(trackCommercial) withObject:nil afterDelay:0.5];
    [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationProgressUpdated object:nil];
	
}

-(void)encode
{
	NSString *encoderLaunchPath = [self encoderPath];
	if (!encoderLaunchPath) {
		return;
	}

    encoderTask = [[NSTask alloc] init];
    NSLog(@"Starting Encode of   %@", _showTitle);
    [encoderTask setLaunchPath:encoderLaunchPath];
    if (!_encodeFormat.canSimulEncode) {  //If can't simul encode have to depend on log file for tracking
        NSMutableArray *arguments = [self encodingArgumentsWithInputFile:decryptFilePath outputFile:_encodeFilePath];
        [encoderTask setArguments:arguments];
        [encoderTask setStandardOutput:encodeLogFileHandle];
        [encoderTask setStandardError:devNullFileHandle];
        _processProgress = 0.0;
        previousProcessProgress = 0.0;
        [self performSelector:@selector(checkStillActive) withObject:nil afterDelay:kMTProgressCheckDelay];
        [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationProgressUpdated object:nil];
        [encoderTask launch];
        [self setValue:[NSNumber numberWithInt:kMTStatusEncoding] forKeyPath:@"downloadStatus"];
        _showStatus = @"Encoding";
        [self performSelector:@selector(trackEncodes) withObject:nil afterDelay:0.5];
    } else { //if can simul encode we can ignore the log file and just track an input pipe - more accurate and more general
        if(pipe1){
            [pipe1 release];
        }
        pipe1 = [[NSPipe pipe] retain];
        bufferFileReadHandle = [[NSFileHandle fileHandleForReadingAtPath:decryptFilePath] retain];
        NSMutableArray *arguments = [self encodingArgumentsWithInputFile:@"-" outputFile:_encodeFilePath];
        [encoderTask setArguments:arguments];
        [encoderTask setStandardInput:pipe1];
        [encoderTask setStandardOutput:encodeLogFileHandle];
        [encoderTask setStandardError:devNullFileHandle];
        if (downloadFileHandle) {
            [downloadFileHandle release];
        }
        downloadFileHandle = [pipe1 fileHandleForWriting];
        _processProgress = 0.0;
        previousProcessProgress = 0.0;
        [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationProgressUpdated object:nil];
        [encoderTask launch];
        [self setValue:[NSNumber numberWithInt:kMTStatusEncoding] forKeyPath:@"downloadStatus"];
        _showStatus = @"Encoding";
        [self performSelectorInBackground:@selector(writeData) withObject:nil];
        [self performSelector:@selector(trackDownloadEncode) withObject:nil afterDelay:3.0];
    }
}

-(void)trackEncodes
{
	if (![encoderTask isRunning]) {
		[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(checkStillActive) object:nil];
        NSLog(@"Finished Encode of   %@",_showTitle);
        _processProgress = 1.0;
		[encoderTask release];
		encoderTask = nil;
        _showStatus = @"Complete";
        [self setValue:[NSNumber numberWithInt:kMTStatusDone] forKeyPath:@"downloadStatus"];
        [self cleanupFiles];
		[[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationProgressUpdated object:nil];
        [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationEncodeDidFinish object:self];
		
		[tiVoManager  notifyWithTitle:@"TiVo show transferred." subTitle:self.showTitle forNotification:kMTGrowlEndDownload];
		
        if (_addToiTunesWhenEncoded) {
			MTiTunes *iTunes = [[[MTiTunes alloc] init] autorelease];
			[iTunes importIntoiTunes:self];
        }
		[self cleanupFiles];
		return;
	}
	double newProgressValue = 0;
	unsigned long long logFileSize = [encodeLogFileReadHandle seekToEndOfFile];
	if (logFileSize > 100) {
		[encodeLogFileReadHandle seekToFileOffset:(logFileSize-100)];
		NSData *tailOfFile = [encodeLogFileReadHandle readDataOfLength:100];
		NSString *data = [[[NSString alloc] initWithData:tailOfFile encoding:NSUTF8StringEncoding] autorelease];
		NSRegularExpression *percents = [NSRegularExpression regularExpressionWithPattern:_encodeFormat.regExProgress options:NSRegularExpressionCaseInsensitive error:nil];
//		if ([_encodeFormat.encoderUsed caseInsensitiveCompare:@"mencoder"] == NSOrderedSame) {
//			NSRegularExpression *percents = [NSRegularExpression regularExpressionWithPattern:@"\\((.*?)\\%\\)" options:NSRegularExpressionCaseInsensitive error:nil];
			NSArray *values = [percents matchesInString:data options:NSMatchingWithoutAnchoringBounds range:NSMakeRange(0, data.length)];
			NSTextCheckingResult *lastItem = [values lastObject];
			NSRange valueRange = [lastItem rangeAtIndex:1];
			newProgressValue = [[data substringWithRange:valueRange] doubleValue]/100.0;
			[[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationProgressUpdated object:nil];
//		}
//		if ([_encodeFormat.encoderUsed caseInsensitiveCompare:@"HandBrakeCLI"] == NSOrderedSame) {
//			NSRegularExpression *percents = [NSRegularExpression regularExpressionWithPattern:@" ([\\d.]*?) \\% " options:NSRegularExpressionCaseInsensitive error:nil];
//			NSArray *values = [percents matchesInString:data options:NSMatchingWithoutAnchoringBounds range:NSMakeRange(0, data.length)];
//			if (values.count) {
//				NSTextCheckingResult *lastItem = [values lastObject];
//				NSRange valueRange = [lastItem rangeAtIndex:1];
//				newProgressValue = [[data substringWithRange:valueRange] doubleValue]/102.0;
//				[[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationProgressUpdated object:nil];
//			}
//		}
		if (newProgressValue > _processProgress) {
			_processProgress = newProgressValue;
		}
	}
	[self performSelector:@selector(trackEncodes) withObject:nil afterDelay:0.5];
    [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationProgressUpdated object:nil];	
}

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
	return arguments;

}

-(NSMutableArray *)encodingArgumentsWithInputFile:(NSString *)inputFilePath outputFile:(NSString *)outputFilePath
{
	NSMutableArray *arguments = [NSMutableArray array];
    if (_encodeFormat.encoderVideoOptions.length) [arguments addObjectsFromArray:[self getArguments:_encodeFormat.encoderVideoOptions]];
	if (_encodeFormat.encoderAudioOptions.length) [arguments addObjectsFromArray:[self getArguments:_encodeFormat.encoderAudioOptions]];
	if (_encodeFormat.encoderOtherOptions.length) [arguments addObjectsFromArray:[self getArguments:_encodeFormat.encoderOtherOptions]];
	if ([_encodeFormat.comSkip boolValue] && _skipCommercials) {
		[arguments addObject:@"-edl"];
		[arguments addObject:[NSString stringWithFormat:@"/tmp/%@.tivo.edl",self.showTitleForFiles]];
	}
    if (_encodeFormat.outputFileFlag.length) {
        [arguments addObject:_encodeFormat.outputFileFlag];
        [arguments addObject:outputFilePath];
        if (_encodeFormat.inputFileFlag.length) {
            [arguments addObject:_encodeFormat.inputFileFlag];
        }
        [arguments addObject:inputFilePath];
    } else {
        if (_encodeFormat.inputFileFlag.length) {
            [arguments addObject:_encodeFormat.inputFileFlag];
        }
        [arguments addObject:inputFilePath];
        [arguments addObject:outputFilePath];
    }
	return arguments;
}

-(void)cleanupFiles
{
    NSFileManager *fm = [NSFileManager defaultManager];
    if (_downloadFilePath) {
        [downloadFileHandle closeFile];
        [fm removeItemAtPath:_downloadFilePath error:nil];
		[downloadFileHandle release]; downloadFileHandle = nil;
		[_downloadFilePath release]; _downloadFilePath = nil;
    }
    if (_bufferFilePath) {
        [bufferFileReadHandle closeFile];
        [bufferFileWriteHandle closeFile];
        [fm removeItemAtPath:_bufferFilePath error:nil];
		[bufferFileReadHandle release]; bufferFileReadHandle = nil;
		[bufferFileWriteHandle release]; bufferFileWriteHandle = nil;
		[_bufferFilePath release]; _bufferFilePath = nil;
    }
    if (commercialLogFileHandle) {
        [commercialLogFileHandle closeFile];
        [fm removeItemAtPath:commercialLogFilePath error:nil];
		[commercialLogFileHandle release]; commercialLogFileHandle = nil;
		[commercialLogFilePath release]; commercialLogFilePath = nil;
    }
    if (encodeLogFileHandle) {
        [encodeLogFileHandle closeFile];
        [fm removeItemAtPath:encodeLogFilePath error:nil];
		[encodeLogFileHandle release]; encodeLogFileHandle = nil;
		[encodeLogFilePath release]; encodeLogFilePath = nil;
    }
    if (decryptLogFileHandle) {
        [decryptLogFileHandle closeFile];
        [fm removeItemAtPath:decryptLogFilePath error:nil];
		[decryptLogFileHandle release]; decryptLogFileHandle = nil;
		[decryptLogFilePath release]; decryptLogFilePath = nil;
    }
    if (decryptFilePath) {
        [fm removeItemAtPath:decryptFilePath error:nil];
		[decryptFilePath release]; decryptFilePath = nil;
    }
	//Clean up files in /tmp
	NSArray *tmpFiles = [fm contentsOfDirectoryAtPath:@"/tmp/" error:nil];
	[fm changeCurrentDirectoryPath:@"/tmp"];
	for(NSString *file in tmpFiles){
		NSRange tmpRange = [file rangeOfString:[self showTitleForFiles]];
		if(tmpRange.location != NSNotFound) [fm removeItemAtPath:file error:nil];
	}
}

-(BOOL) isInProgress {
    return ([_downloadStatus intValue] != kMTStatusNew && [_downloadStatus intValue] != kMTStatusDone &&  [_downloadStatus intValue] != kMTStatusFailed);
}

-(void)cancel
{
    NSLog(@"Canceling of         %@", _showTitle);
    NSFileManager *fm = [NSFileManager defaultManager];
    isCanceled = YES;
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    if ([_downloadStatus intValue] == kMTStatusDownloading && activeURLConnection) {
        [activeURLConnection cancel];
        activeURLConnection = nil;
        [fm removeItemAtPath:decryptFilePath error:nil];
    }
    while (writingData){
        //Block until latest write data is complete - should stop quickly because isCanceled is set
    } //Wait for pipe out to complete
    [self cleanupFiles]; //Everything but the final file
    if(decrypterTask && [decrypterTask isRunning]) {
        [decrypterTask terminate];
    }
    if(encoderTask && [encoderTask isRunning]) {
        [encoderTask terminate];
    }
    if(commercialTask && [commercialTask isRunning]) {
        [commercialTask terminate];
    }
    if (encodeFileHandle) {
        [encodeFileHandle closeFile];
        [fm removeItemAtPath:_encodeFilePath error:nil];
    }
    if ([_downloadStatus intValue] == kMTStatusEncoding || (_simultaneousEncode && [_downloadStatus intValue] == kMTStatusDownloading)) {
        [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationEncodeWasCanceled object:self];
    }
    if ([_downloadStatus intValue] == kMTStatusCommercialing) {
        [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationCommercialWasCanceled object:self];
    }
    [self setValue:[NSNumber numberWithInt:kMTStatusNew] forKeyPath:@"downloadStatus"];
    _processProgress = 0.0;
    _showStatus = @"";
    
}

-(void)updateProgress
{
    [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationProgressUpdated object:nil];
}

-(void)sendNotification
{
	NSNotification *not = [NSNotification notificationWithName:kMTNotificationDownloadQueueUpdated object:self.tiVo];
	[[NSNotificationCenter defaultCenter] performSelector:@selector(postNotification:) withObject:not afterDelay:4.0];
}

-(void)writeData
{
//	writingData = YES;
	int chunkSize = 10000;
	int nchunks = 0;
	int chunkReleaseMemory = 10;
	unsigned long dataRead;
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSData *data = nil;
	if (!isCanceled) {
		@try {
			data = [bufferFileReadHandle readDataOfLength:chunkSize];
		}
		@catch (NSException *exception) {
			writingData = NO;
			[self rescheduleShow:[NSNumber numberWithBool:YES]];
			[self performSelectorOnMainThread:@selector(sendNotification) withObject:nil waitUntilDone:NO];
			return;
		}
		@finally {
		}
	}
	pipingData = YES;
	if (!isCanceled){
		@try {
			[downloadFileHandle writeData:data];
		}
		@catch (NSException *exception) {
			writingData = NO;
			[self rescheduleShow:[NSNumber numberWithBool:YES]];
			[self performSelectorOnMainThread:@selector(sendNotification) withObject:nil waitUntilDone:NO];
			return;
		}
		@finally {
		}
	}
	pipingData = NO;
	dataRead = data.length;
	while (dataRead == chunkSize && !isCanceled) {
		@try {
			data = [bufferFileReadHandle readDataOfLength:chunkSize];
		}
		@catch (NSException *exception) {
			writingData = NO;
			[self rescheduleShow:[NSNumber numberWithBool:YES]];
			[self performSelectorOnMainThread:@selector(sendNotification) withObject:nil waitUntilDone:NO];
			return;
		}
		@finally {
		}
		pipingData = YES;
		if (!isCanceled) {
			@try {
				[downloadFileHandle writeData:data];
			}
			@catch (NSException *exception) {
				writingData = NO;
				[self rescheduleShow:[NSNumber numberWithBool:YES]];
				[self performSelectorOnMainThread:@selector(sendNotification) withObject:nil waitUntilDone:NO];
				return;
			}
			@finally {
			}
		}
		pipingData = NO;
		if (isCanceled) break;
		dataRead = data.length;
//		dataDownloaded += data.length;
		_processProgress = (double)[bufferFileReadHandle offsetInFile]/_fileSize;
        [self performSelectorOnMainThread:@selector(updateProgress) withObject:nil waitUntilDone:NO];
		nchunks++;
		if (nchunks == chunkReleaseMemory) {
			nchunks = 0;
			[pool drain];
			pool = [[NSAutoreleasePool alloc] init];
		}
	}
	[pool drain];
	if (!activeURLConnection || isCanceled) {
//        NSLog(@"Closing downloadFileHandle which %@ from pipe1 for show %@", (downloadFileHandle != [pipe1 fileHandleForWriting]) ? @"is not" : @"is", _showTitle);
		[downloadFileHandle closeFile];
		if (downloadFileHandle != [pipe1 fileHandleForWriting]) {
			[downloadFileHandle release];
		}
		downloadFileHandle = nil;
		[bufferFileReadHandle closeFile];
		[bufferFileReadHandle release];
		bufferFileReadHandle = nil;
		[[NSFileManager defaultManager] removeItemAtPath:_bufferFilePath error:nil];

	}
	writingData = NO;
}

#pragma mark - NSURL Delegate Methods

-(void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data
{
    if (!_isSimultaneousEncoding) {
        [downloadFileHandle writeData:data];
        dataDownloaded += data.length;
        _processProgress = dataDownloaded/_fileSize;
        [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationProgressUpdated object:nil];

    } else {
        [bufferFileWriteHandle writeData:data];
    }
	if (!writingData && _isSimultaneousEncoding) {
		writingData = YES;
		[self performSelectorInBackground:@selector(writeData) withObject:nil];
	}
}

- (BOOL)connection:(NSURLConnection *)connection canAuthenticateAgainstProtectionSpace:(NSURLProtectionSpace *)protectionSpace {
    return YES;
}

- (void)connection:(NSURLConnection *)connection didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge {
    //    [challenge.sender useCredential:[NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust] forAuthenticationChallenge:challenge];
    [challenge.sender useCredential:[NSURLCredential credentialWithUser:@"tivo" password:_tiVo.mediaKey persistence:NSURLCredentialPersistenceForSession] forAuthenticationChallenge:challenge];
    [challenge.sender continueWithoutCredentialForAuthenticationChallenge:challenge];
}

-(void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error
{
    NSLog(@"URL Connection Failed with error %@",error);
	[self rescheduleShow:[NSNumber numberWithBool:YES]];
}

-(void)dismissAlertSheet
{
    NSWindow *alertWindow = [tiVoManager.mainWindow attachedSheet];
    [NSApp endSheet:alertWindow returnCode:NSAlertFirstButtonReturn];
    [alertWindow orderOut:self];
    [tiVoManager noRecordingAlertDidEnd:nil returnCode:0 contextInfo:self];

}

-(NSAttributedString *)attrStringFromDictionary:(id)nameList
{
    NSMutableString *returnString = [NSMutableString string];
    if ([nameList isKindOfClass:[NSArray class]]) {
        for (NSDictionary *name in nameList) {
            [returnString appendFormat:@"%@\n",[self nameString:name]];
        }
       	if (returnString.length > 0)[returnString deleteCharactersInRange:NSMakeRange(returnString.length-1, 1)];
		
    }
   return [[[NSAttributedString alloc] initWithString:returnString attributes:@{NSFontAttributeName : [NSFont systemFontOfSize:11]}] autorelease];
    
}

-(NSAttributedString *)actors
{
    return [self attrStringFromDictionary:_vActor];
}

-(NSAttributedString *)guestStars
{
    return [self attrStringFromDictionary:_vGuestStar];
}

-(NSAttributedString *)directors
{
    return [self attrStringFromDictionary:_vDirector];
}

-(NSAttributedString *)producers
{
    return [self attrStringFromDictionary:_vExecProducer];
}

-(NSString *)yearString
{
    return [NSString stringWithFormat:@"%d",_episodeYear];
}

-(NSString *)seasonString
{
	NSString *returnString = @"";
	if (_season > 0) {
		returnString = [NSString stringWithFormat:@"%d",_season];
	}
    return returnString;
}


-(void)connectionDidFinishLoading:(NSURLConnection *)connection
{
	double downloadedFileSize = 0;
    if (!_isSimultaneousEncoding) {
        downloadedFileSize = (double)[downloadFileHandle offsetInFile];
       [downloadFileHandle release];
        downloadFileHandle = nil;
		//Check to make sure a reasonable file size in case there was a problem.
		if (downloadedFileSize > 100000) {
			[self setValue:[NSNumber numberWithInt:kMTStatusDownloaded] forKeyPath:@"downloadStatus"];
			[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(checkStillActive) object:nil];
		}
    } else {
        downloadedFileSize = (double)[bufferFileWriteHandle offsetInFile];
        [bufferFileWriteHandle closeFile];
		//Check to make sure a reasonable file size in case there was a problem.
		if (downloadedFileSize > 100000) {
			[self setValue:[NSNumber numberWithInt:kMTStatusEncoding] forKeyPath:@"downloadStatus"];
			_showStatus = @"Encoding";
		   [self performSelector:@selector(trackDownloadEncode) withObject:nil afterDelay:0.3];
		}
    }
	downloadingURL = NO;
	activeURLConnection = nil;
	
    //Make sure to flush the last of the buffer file into the pipe and close it.
	if (!writingData && _isSimultaneousEncoding) {
//		[self performSelectorInBackground:@selector(writeData) withObject:nil];
		writingData = YES;
		[self writeData];
	}
	if (downloadedFileSize < 100000) { //Not a good download - reschedule
		NSString *dataReceived = [NSString stringWithContentsOfFile:_bufferFilePath encoding:NSUTF8StringEncoding error:nil];
		if (dataReceived) {
			NSRange noRecording = [dataReceived rangeOfString:@"recording not found" options:NSCaseInsensitiveSearch];
			if (noRecording.location != NSNotFound) { //This is a missing recording
				NSAlert *notFoundAlert = [NSAlert alertWithMessageText:[NSString stringWithFormat:@"%@ not found.  Deleting from download queue",_showTitle] defaultButton:@"OK" alternateButton:nil otherButton:nil informativeTextWithFormat:@""];
				[notFoundAlert beginSheetModalForWindow:tiVoManager.mainWindow modalDelegate:tiVoManager didEndSelector:@selector(noRecordingAlertDidEnd:returnCode:contextInfo:) contextInfo:self];
				[self performSelector:@selector(dismissAlertSheet) withObject:nil afterDelay:3.0];
				[self.tiVo updateShows:nil];
				return;
			}
		}
		NSLog(@"Downloaded file  too small - rescheduling; File sent was %@",dataReceived);
		[self performSelector:@selector(rescheduleShow:) withObject:[NSNumber numberWithBool:NO] afterDelay:kMTTiVoAccessDelay];
	} else {
		_fileSize = downloadedFileSize;  //More accurate file size
		[self performSelector:@selector(sendNotification:) withObject:kMTNotificationDownloadDidFinish afterDelay:4.0];
	}
}

#pragma mark - Misc Support Functions

+ (NSDate *)dateForRFC3339DateTimeString:(NSString *)rfc3339DateTimeString
// Returns a  date  that corresponds to the
// specified RFC 3339 date time string. Note that this does not handle
// all possible RFC 3339 date time strings, just one of the most common
// styles.
{
    static NSDateFormatter *    sRFC3339DateFormatter;
    NSDate *                    date;
	
    // If the date formatters aren't already set up, do that now and cache them
    // for subsequence reuse.
	
    if (sRFC3339DateFormatter == nil) {
        NSLocale *enUSPOSIXLocale;
		
        sRFC3339DateFormatter = [[NSDateFormatter alloc] init];
		
        enUSPOSIXLocale = [[[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"] autorelease];
		
        [sRFC3339DateFormatter setLocale:enUSPOSIXLocale];
        [sRFC3339DateFormatter setDateFormat:@"yyyy'-'MM'-'dd'T'HH':'mm':'ss'Z'"];
        [sRFC3339DateFormatter setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];
    }
	
    // Convert the RFC 3339 date time string to an NSDate.
    // Then convert the NSDate to a user-visible date string.
	
 	
    date = [sRFC3339DateFormatter dateFromString:rfc3339DateTimeString];
	return date;
}

-(void)sendNotification:(NSString *)notification
{
    [[NSNotificationCenter defaultCenter] postNotificationName:notification object:self.tiVo];
    
}
#pragma mark Setters (most to complete parsing)

-(void) setShowTime: (NSString *) newTime {
	if (newTime != _showTime) {
        [_showTime release];
        _showTime = [newTime retain];
        NSDate *newDate =[MTTiVoShow dateForRFC3339DateTimeString:_showTime];
        if (newDate) {
            self.showDate = newDate;
        }
		//        NSLog(@"converting %@ from: %@ to %@ ", self.showTitle, newTime, self.showDate);
    }
}

-(void)setOriginalAirDate:(NSString *)originalAirDate
{
	if (originalAirDate != _originalAirDate) {
		[_originalAirDate release];
		_originalAirDate = [originalAirDate retain];
		if (originalAirDate.length > 4) {
			_episodeYear = [[originalAirDate substringToIndex:4] intValue];
		}
		if (originalAirDate.length >= 10) {
			self.originalAirDateNoTime = [originalAirDate substringToIndex:10];
		}
	}
}

-(void)setEpisodeNumber:(NSString *)episodeNumber
{
	if (episodeNumber != _episodeNumber) {  // this check is mandatory
        [_episodeNumber release];
        _episodeNumber = [episodeNumber retain];
		if (episodeNumber.length) {
			long l = episodeNumber.length;
			if (l > 2) {
				_episode = [[episodeNumber substringFromIndex:l-2] intValue];
				_season = [[episodeNumber substringToIndex:l-2] intValue];
			} else {
				_episode = [episodeNumber intValue];
			}
		}
	}

}

-(BOOL) canSimulEncode {
    return self.encodeFormat.canSimulEncode;
}

-(BOOL) shouldSimulEncode {
    return _simultaneousEncode;
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

-(NSString *)hDString
{
	NSString *returnString = @"No";
	if ([_isHD boolValue ]) {
		returnString = @"Yes";
	}
	return returnString;
}

-(NSString *) seasonEpisode {
    
    int e = _episode;
    int s = _season;
    NSString *episode = @"";
    if (e > 0) {
        if (s > 0 && s < 100 && e < 100) {
            episode = [NSString stringWithFormat:@"S%0.2d E%0.2d",s,e ];
        } else {
            episode	 = [NSString stringWithFormat:@"%d",e];
        }
    } else if ([_episodeNumber compare:@"0"] != NSOrderedSame){
        episode = _episodeNumber;
    }
    return episode;
}

-(NSString *) seriesFromProgram:(NSString *) name {
    NSArray * nameParts = [name componentsSeparatedByString: @":"];
    if (nameParts.count == 0) return name;
    return [nameParts objectAtIndex:0];
}

-(NSString * ) seriesTitle {
    if (!_seriesTitle) {
        self.seriesTitle = [self seriesFromProgram:_showTitle];
    }
    return _seriesTitle;
}

-(BOOL) isMovie {
	return (self.episodeTitle.length == 0) &&
	([self.episodeNumber intValue] == 0) &&
			 (self.showLength > 70) ;
}

-(MTTiVo *) tiVo {
	if (!_tiVo) {
		for (MTTiVo * possibleTiVo in tiVoManager.tiVoList) {
			if ([possibleTiVo.tiVo.name compare:self.tempTiVoName]) {
				self.tiVo = possibleTiVo;
				break;
			}
		}
	}
	return _tiVo;
}

-(NSString *)showDateString
{
	static NSDateFormatter *dateFormat;
	if(!dateFormat) {
		dateFormat = [[NSDateFormatter alloc] init] ;
		[dateFormat setDateStyle:NSDateFormatterShortStyle];
		[dateFormat setTimeStyle:NSDateFormatterShortStyle] ;
	}
//	[dateFormat setTimeStyle:NSDateFormatterNoStyle];
	return [dateFormat stringFromDate:_showDate];
}

-(NSString *)showMediumDateString
{
	static NSDateFormatter *dateFormat;
	if(!dateFormat) {
		dateFormat = [[NSDateFormatter alloc] init] ;
		[dateFormat setDateStyle:NSDateFormatterMediumStyle];
		[dateFormat setTimeStyle:NSDateFormatterShortStyle] ;
	}
	//	[dateFormat setTimeStyle:NSDateFormatterNoStyle];
	return [dateFormat stringFromDate:_showDate];
}

#pragma mark - Custom Setters

-(void) setEncodeFormat:(MTFormat *) encodeFormat {
    if (_encodeFormat != encodeFormat ) {
        BOOL simulWasDisabled = ![self canSimulEncode];
        BOOL iTunesWasDisabled = ![self canAddToiTunes];
        BOOL skipWasDisabled = ![self canSkipCommercials];
        [_encodeFormat release];
        _encodeFormat = [encodeFormat retain];
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

-(void)setSeriesTitle:(NSString *)seriesTitle
{
	if (_seriesTitle != seriesTitle) {
		[_seriesTitle release];
		_seriesTitle = [seriesTitle retain];
		if (_episodeTitle.length > 0 ) {
			self.showTitle = [NSString stringWithFormat:@"%@: %@",_seriesTitle, _episodeTitle];
		} else {
			self.showTitle = _seriesTitle;
		}
	}
}

-(void)setEpisodeTitle:(NSString *)episodeTitle
{
	if (_episodeTitle != episodeTitle) {
		[_episodeTitle release];
		_episodeTitle = [episodeTitle retain];
		if (_episodeTitle.length > 0 ) {
			self.showTitle = [NSString stringWithFormat:@"%@: %@",_seriesTitle, _episodeTitle];
		} else {
			self.showTitle = _seriesTitle;
		}
	}
}

-(void)setShowDescription:(NSString *)showDescription
{
    NSString * tribuneCopyright = @" Copyright Tribune Media Services, Inc.";
	if (_showDescription == showDescription) {
		return;
	}
	[_showDescription release];
    if ([showDescription hasSuffix: tribuneCopyright]){
        _showDescription = [[showDescription substringToIndex:showDescription.length -tribuneCopyright.length]  retain ];
    } else {
        _showDescription = [showDescription retain];

    }
}

-(void)setVActor:(NSArray *)vActor
{
	if (_vActor == vActor || ![vActor isKindOfClass:[NSArray class]]) {
		return;
	}
	[_vActor release];
	_vActor = [vActor retain];
}

-(void)setVExecProducer:(NSArray *)vExecProducer
{
	if (_vExecProducer == vExecProducer || ![vExecProducer isKindOfClass:[NSArray class]]) {
		return;
	}
	[_vExecProducer release];
	_vExecProducer = [vExecProducer retain];
}


-(NSString *) episodeGenre {
    //iTunes says "there can only be one", so pick the first we see.
    NSCharacterSet * quotes = [NSCharacterSet characterSetWithCharactersInString:@"\""];
    NSString * firstGenre = nil;
    if (_vSeriesGenre.count > 0) firstGenre = [_vSeriesGenre objectAtIndex:0];
        else if (_vProgramGenre.count > 0) firstGenre = [_vProgramGenre objectAtIndex:0];
			else firstGenre = @"";
    return [firstGenre stringByTrimmingCharactersInSet:quotes];
}

-(void)setVProgramGenre:(NSArray *)vProgramGenre
{
	if (_vProgramGenre == vProgramGenre || ![vProgramGenre isKindOfClass:[NSArray class]]) {
		return;
	}
	[_vProgramGenre release];
	_vProgramGenre = [vProgramGenre retain];
}

-(void)setVSeriesGenre:(NSArray *)vSeriesGenre{
	if (_vSeriesGenre == vSeriesGenre || ![vSeriesGenre isKindOfClass:[NSArray class]]) {
		return;
	}
	[_vSeriesGenre release];
	_vSeriesGenre = [vSeriesGenre retain];
}

#pragma mark - Memory Management

-(void)dealloc
{
    self.showTitle = nil;
    self.showDescription = nil;
    self.showStatus = nil;
    self.detailURL = nil;
	self.downloadURL = nil;
    self.encodeFormat = nil;
    self.tiVo = nil;
	self.downloadDirectory = nil;
	if (_encodeFilePath) {
		[_encodeFilePath release];
        _encodeFilePath = nil;
	}
	if (_bufferFilePath) {
		[_bufferFilePath release];
        _bufferFilePath = nil;
	}
	if (_downloadFilePath) {
		[_downloadFilePath release];
        _downloadFilePath = nil;
	}
	if (elementString) {
		[elementString release];
        elementString = nil;
	}
	if (elementArray) {
		[elementArray release];
        elementArray = nil;
	}
    [previousCheck release];
    [self deallocDownloadHandling];
    [devNullFileHandle release];
	[parseTermMapping release];
	[self removeObserver:self forKeyPath:@"downloadStatus"];
	[super dealloc];
}

-(NSString *)description
{
    return [NSString stringWithFormat:@"%@ (%@)%@",_showTitle,_tiVo.tiVo.name,[_protectedShow boolValue]?@"-Protected":@""];
}


@end
