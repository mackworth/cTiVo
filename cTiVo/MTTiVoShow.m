//
//  MTTiVoShow.m
//  cTiVo
//
//  Created by Scott Buchanan on 12/18/12.
//  Copyright (c) 2012 Scott Buchanan. All rights reserved.
//
// Class for handling individual TiVo Shows

#import "MTTiVoShow.h"
#import "MTProgramList.h"
#import "MTiTunes.h"

@implementation MTTiVoShow

@synthesize encodeFilePath;

-(id)init
{
    self = [super init];
    if (self) {
        encoderTask = nil;
        _showID = 0;
        _showStatus = @"";
		decryptFilePath = nil;
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
        devNullFileHandle = [[NSFileHandle fileHandleForWritingAtPath:@"/dev/null"] retain];
		_season = 0;
		_episode = 0;
		_episodeNumber = @"";
		_episodeGenre = @"";
//		_originalAirDate = @"";
		_episodeYear = 0;
		parseTermMapping = [@{@"description" : @"showDescription", @"time": @"showTime"} retain];
        
    }
    return self;
}

-(void)getShowDetailWithNotification
{
	if (gotDetails) {
		return;
	}
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init]	;
	[self getShowDetail];
	if (gotDetails) {
//		[[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationTiVoShowsUpdated object:nil];
//		[_myTableView performSelectorOnMainThread:@selector(reloadData) withObject:nil waitUntilDone:YES];
		[self performSelectorOnMainThread:@selector(reloadEpisode) withObject:nil waitUntilDone:YES];
//        [_myTableView updateEpisodeForShow:self];
	} else {
		NSLog(@"Got Details Failed for %@",_showTitle);
	}
	[pool drain];
}

-(void)reloadEpisode
{
	NSInteger row = 0;
	for (row=0; row < _myTableView.tiVoShows.count; row++) {
		if ([_myTableView.tiVoShows objectAtIndex:row] == self) {
			break;
		}
	}
	NSInteger column = [_myTableView columnWithIdentifier:@"Episode"];
	[_myTableView reloadDataForRowIndexes:[NSIndexSet indexSetWithIndex:row] columnIndexes:[NSIndexSet indexSetWithIndex:column]];
}

-(NSArray *)parseNames:(NSArray *)nameSet
{
	if (!nameSet || nameSet.count == 0) {
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

-(void)getShowDetail
{
	if (gotDetails) {
		return;
	}
	gotDetails = YES;
	NSString *detailURLString = [NSString stringWithFormat:@"https://%@/TiVoVideoDetails?id=%d",_tiVo.hostName,_showID];
//	NSLog(@"Show Detail URL %@",detailURLString);
	NSURLResponse *detailResponse = nil;
	NSURLRequest *detailRequest = [NSURLRequest requestWithURL:[NSURL URLWithString:detailURLString]];;
	NSData *xml = [NSURLConnection sendSynchronousRequest:detailRequest returningResponse:&detailResponse error:nil];
//	NSLog(@"Returned XML is %@",[[[NSString alloc] initWithData:xml encoding:NSUTF8StringEncoding	] autorelease]	);
	parser = [[[NSXMLParser alloc] initWithData:xml] autorelease];
	parser.delegate = self;
	[parser parse];
	self.vActor = [self parseNames:_vActor];
	self.vExecProducer = [self parseNames:_vExecProducer];
	if (!gotDetails) {
		NSLog(@"Got Details Failed for %@",_showTitle);
	}
	NSNotification *notification = [NSNotification notificationWithName:kMTNotificationDetailsLoaded object:self];
    [[NSNotificationCenter defaultCenter] performSelectorOnMainThread:@selector(postNotification:) withObject:notification waitUntilDone:NO];
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


#pragma mark - Download decrypt and encode Methods

//Method called at the beginning of the download to configure all required files and file handles

-(void)deallocDownloadHandling
{
    if (downloadFilePath) {
        [downloadFilePath release];
        downloadFilePath = nil;
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
    if (decryptFileHandle) {
        [decryptFileHandle release];
        decryptFileHandle = nil;
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
    if (encoderTask) {
		if ([encoderTask isRunning]) {
			[encoderTask terminate];
		}
        [encoderTask release];
        encoderTask = nil;
    }
    if (encodeFilePath) {
        [encodeFilePath release];
        encodeFilePath = nil;
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
    if (bufferFilePath) {
        [bufferFilePath release];
        bufferFilePath = nil;
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

-(void)configureFiles
{
    //Release all previous attached pointers
    [self deallocDownloadHandling];
    encodeFilePath = [[NSString stringWithFormat:@"%@/%@%@",_downloadDirectory,_showTitle,[_encodeFormat objectForKey:@"filenameExtension"]] retain];
    if (_simultaneousEncode) {
        //Things require uniquely for simultaneous download
        pipe1 = [[NSPipe pipe] retain];
        pipe2 = [[NSPipe pipe] retain];
		downloadFileHandle = [pipe1 fileHandleForWriting];
        bufferFilePath = [[NSString stringWithFormat:@"/tmp/buffer%@.bin",_showTitle] retain];
        [[NSFileManager defaultManager] createFileAtPath:bufferFilePath contents:[NSData data] attributes:nil];
        bufferFileReadHandle = [[NSFileHandle fileHandleForReadingAtPath:bufferFilePath] retain];
        bufferFileWriteHandle = [[NSFileHandle fileHandleForWritingAtPath:bufferFilePath] retain];
    } else {
        //Things require uniquely for sequential download
        downloadFilePath = [[NSString stringWithFormat:@"%@%@.tivo",_downloadDirectory ,_showTitle] retain];
        NSFileManager *fm = [NSFileManager defaultManager];
        [fm createFileAtPath:downloadFilePath contents:[NSData data] attributes:nil];
        downloadFileHandle = [[NSFileHandle fileHandleForWritingAtPath:downloadFilePath] retain];
        
        decryptFilePath = [[NSString stringWithFormat:@"%@%@.tivo.mpg",_downloadDirectory ,_showTitle] retain];
        
        decryptLogFilePath = [[NSString stringWithFormat:@"/tmp/decrypting%@.txt",_showTitle] retain];
        [fm createFileAtPath:decryptLogFilePath contents:[NSData data] attributes:nil];
        decryptLogFileHandle = [[NSFileHandle fileHandleForWritingAtPath:decryptLogFilePath] retain];
        decryptLogFileReadHandle = [[NSFileHandle fileHandleForReadingAtPath:decryptLogFilePath] retain];
        
        encodeLogFilePath = [[NSString stringWithFormat:@"/tmp/encoding%@.txt",_showTitle] retain];
        [fm createFileAtPath:encodeLogFilePath contents:[NSData data] attributes:nil];
        encodeLogFileHandle = [[NSFileHandle fileHandleForWritingAtPath:encodeLogFilePath] retain];
        encodeLogFileReadHandle = [[NSFileHandle fileHandleForReadingAtPath:encodeLogFilePath] retain];
    }
}

-(void)download
{
	self.isCanceled = NO;
	if (!gotDetails) {
		[self getShowDetail];
		[[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationTiVoShowsUpdated object:nil];
	}
    [self configureFiles];
    NSURLRequest *thisRequest = [NSURLRequest requestWithURL:[NSURL URLWithString:_urlString ]];
//    activeURLConnection = [NSURLConnection connectionWithRequest:thisRequest delegate:self];
    activeURLConnection = [[[NSURLConnection alloc] initWithRequest:thisRequest delegate:self startImmediately:NO] autorelease];

//Now set up for either simul or sequential download

    if (!_simultaneousEncode || [[_encodeFormat objectForKey:@"mustDownloadFirst"] boolValue]) {
        _isSimultaneousEncoding = NO;
    } else { //We'll build the full piped download chain here
       //Decrypting section of full pipeline
        decrypterTask  = [[NSTask alloc] init];
        NSString *tivodecoderLaunchPath = [[NSBundle mainBundle] pathForResource:@"tivodecode" ofType:@""];
		[decrypterTask setLaunchPath:tivodecoderLaunchPath];
		NSMutableArray *arguments = [NSMutableArray arrayWithObjects:
                        [NSString stringWithFormat:@"-m%@",_mediaKey],
                        @"--",
                        @"-",
                        nil];
        [decrypterTask setArguments:arguments];
        [decrypterTask setStandardInput:pipe1];
        [decrypterTask setStandardOutput:pipe2];
        NSString *encoderLaunchPath;
		if ([(NSString *)[_encodeFormat objectForKey:@"encoderUsed"] caseInsensitiveCompare:@"mencoder"] == NSOrderedSame ) {
			encoderTask = [[NSTask alloc] init];
            encoderLaunchPath = [[NSBundle mainBundle] pathForResource:@"mencoder" ofType:@""];
			[encoderTask setLaunchPath:encoderLaunchPath];
        
			arguments = [self mencoderArgumentsWithOutputFile:encodeFilePath];
			[arguments addObject:@"-"];  //Take input from standard Input
			[encoderTask setArguments:arguments];
			[encoderTask setStandardInput:pipe2];
			[encoderTask setStandardOutput:devNullFileHandle];
			[encoderTask setStandardError:devNullFileHandle];
		}
        [decrypterTask launch];
        [encoderTask launch];
        _isSimultaneousEncoding = YES;
    }
	[activeURLConnection start];
	downloadingURL = YES;
    dataDownloaded = 0.0;
    _processProgress = 0.0;
    _downloadStatus = kMTStatusDownloading;
    _showStatus = @"Downloading";
}
-(void)trackDownloadEncode
{
    if([encoderTask isRunning]) {
        [self performSelector:@selector(trackDownloadEncode) withObject:nil afterDelay:0.3];
    } else {
        _downloadStatus = kMTStatusDone;
        _showStatus = @"Complete";
        _processProgress = 1.0;
        [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationProgressUpdated object:nil];
        [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationEncodeDidFinish object:self];
        if (_addToiTunesWhenEncoded) {
			MTiTunes *iTunes = [[[MTiTunes alloc] init] autorelease];
			[iTunes importIntoiTunes:self];
			//            iTunesApplication *iTunes = [SBApplication applicationWithBundleIdentifier:@"com.apple.iTunes"];
			//            if (iTunes) {
			//                [iTunes add:[NSArray arrayWithObject:[NSURL fileURLWithPath:targetFilePath]] to:nil];
			//            }
        }
    }
}

-(void)decrypt
{
	decrypterTask = [[NSTask alloc] init];
	[decrypterTask setLaunchPath:[[NSBundle mainBundle] pathForResource:@"tivodecode" ofType:@""]];
	[decrypterTask setStandardOutput:decryptLogFileHandle];
	[decrypterTask setStandardError:decryptLogFileHandle];	
    // tivodecode -m0636497662 -o Two\ and\ a\ Half\ Men.mpg -v Two\ and\ a\ Half\ Men.TiVo
    
	NSArray *arguments = [NSArray arrayWithObjects:
						  [NSString stringWithFormat:@"-m%@",_mediaKey],
						  [NSString stringWithFormat:@"-o%@",decryptFilePath],
						  @"-v",
						  downloadFilePath,
						  nil];
    _processProgress = 0.0;
 	[[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationProgressUpdated object:nil];
    _downloadStatus = kMTStatusDecrypting;
	_showStatus = @"Decrypting";
	[decrypterTask setArguments:arguments];
	[decrypterTask launch];
	[self performSelector:@selector(trackDecrypts) withObject:nil afterDelay:0.3];
	
}

-(void)trackDecrypts
{
	if (![decrypterTask isRunning]) {
		_processProgress = 1.0;
		[[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationProgressUpdated object:nil];
        _downloadStatus = kMTStatusDecrypted;
        _showStatus = @"Wait for encoder";
		NSError *thisError = nil;
		[[NSFileManager defaultManager] removeItemAtPath:downloadFilePath error:&thisError];
       [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationDecryptDidFinish object:nil];
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

-(void)encode
{
	encoderTask = [[NSTask alloc] init];
//	NSDictionary *selectedFormat = [programEncoding objectForKey:kMTSelectedFormat];
	NSMutableArray *arguments = nil;
	if ([(NSString *)[_encodeFormat objectForKey:@"encoderUsed"] caseInsensitiveCompare:@"mencoder"] == NSOrderedSame ) {
		[encoderTask setLaunchPath:[[NSBundle mainBundle] pathForResource:@"mencoder" ofType:@""]];
		arguments = [self mencoderArgumentsWithOutputFile:encodeFilePath];
		[arguments addObject:decryptFilePath];  //start with the input file
		
	}
	if ([(NSString *)[_encodeFormat objectForKey:@"encoderUsed"] caseInsensitiveCompare:@"HandBrake"] == NSOrderedSame ) {
		arguments = [NSMutableArray array];
		NSString *thisLaunchPath = [[NSBundle mainBundle] pathForResource:@"HandBrakeCLI" ofType:@""];
		[encoderTask setLaunchPath:thisLaunchPath];
		[arguments addObject:[NSString stringWithFormat:@"-i%@",decryptFilePath]];  //start with the input file
		[arguments addObject:[NSString stringWithFormat:@"-o%@",encodeFilePath]];  //add the output file
		[arguments addObject:[_encodeFormat objectForKey:@"encoderVideoOptions"]];
		if ([_encodeFormat objectForKey:@"encoderAudioOptions"] && ((NSString *)[_encodeFormat objectForKey:@"encoderAudioOptions"]).length) {
			[arguments addObject:[_encodeFormat objectForKey:@"encoderAudioOptions"]];
		}
		if ([_encodeFormat objectForKey:@"encoderOtherOptions"] && ((NSString *)[_encodeFormat objectForKey:@"encoderOtherOptions"]).length) {
			[arguments addObject:[_encodeFormat objectForKey:@"encoderOtherOptions"]];
		}
	}
	[encoderTask setArguments:arguments];
	[encoderTask setStandardOutput:encodeLogFileHandle];
	[encoderTask setStandardError:devNullFileHandle];
    _processProgress = 0.0;
	[[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationProgressUpdated object:nil];
	[encoderTask launch];
    _downloadStatus = kMTStatusEncoding;
	_showStatus = @"Encoding";
	[self performSelector:@selector(trackEncodes) withObject:nil afterDelay:0.5];
	
}

-(void)trackEncodes
{
	if (![encoderTask isRunning]) {
        _processProgress = 1.0;
        [[NSFileManager defaultManager] removeItemAtPath:decryptFilePath error:nil];
		[encoderTask release];
		encoderTask = nil;
        _showStatus = @"Complete";
        _downloadStatus = kMTStatusDone;
        [self cleanupFiles];
		[[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationProgressUpdated object:nil];
        [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationEncodeDidFinish object:self];
        if (_addToiTunesWhenEncoded) {
			MTiTunes *iTunes = [[[MTiTunes alloc] init] autorelease];
			[iTunes importIntoiTunes:self];
//            iTunesApplication *iTunes = [SBApplication applicationWithBundleIdentifier:@"com.apple.iTunes"];
//            if (iTunes) {
//                [iTunes add:[NSArray arrayWithObject:[NSURL fileURLWithPath:targetFilePath]] to:nil];
//            }
        }
		return;
	}
	double newProgressValue = 0;
	unsigned long long logFileSize = [encodeLogFileReadHandle seekToEndOfFile];
	if (logFileSize > 100) {
		[encodeLogFileReadHandle seekToFileOffset:(logFileSize-100)];
		NSData *tailOfFile = [encodeLogFileReadHandle readDataOfLength:100];
		NSString *data = [[[NSString alloc] initWithData:tailOfFile encoding:NSUTF8StringEncoding] autorelease];
		if ([(NSString *)[_encodeFormat objectForKey:@"encoderUsed"] caseInsensitiveCompare:@"mencoder"] == NSOrderedSame) {
			NSRegularExpression *percents = [NSRegularExpression regularExpressionWithPattern:@"\\((.*?)\\%\\)" options:NSRegularExpressionCaseInsensitive error:nil];
			NSArray *values = [percents matchesInString:data options:NSMatchingWithoutAnchoringBounds range:NSMakeRange(0, data.length)];
			NSTextCheckingResult *lastItem = [values lastObject];
			NSRange valueRange = [lastItem rangeAtIndex:1];
			newProgressValue = [[data substringWithRange:valueRange] doubleValue]/100.0;
			[[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationProgressUpdated object:nil];
		}
		if ([(NSString *)[_encodeFormat objectForKey:@"encoderUsed"] caseInsensitiveCompare:@"HandBrake"] == NSOrderedSame) {
			NSRegularExpression *percents = [NSRegularExpression regularExpressionWithPattern:@" ([\\d.]*?) \\% " options:NSRegularExpressionCaseInsensitive error:nil];
			NSArray *values = [percents matchesInString:data options:NSMatchingWithoutAnchoringBounds range:NSMakeRange(0, data.length)];
			if (values.count) {
				NSTextCheckingResult *lastItem = [values lastObject];
				NSRange valueRange = [lastItem rangeAtIndex:1];
				newProgressValue = [[data substringWithRange:valueRange] doubleValue]/102.0;
				[[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationProgressUpdated object:nil];
			}
		}
		if (newProgressValue > _processProgress) {
			_processProgress = newProgressValue;
		}
	}
	[self performSelector:@selector(trackEncodes) withObject:nil afterDelay:0.5];
    [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationProgressUpdated object:nil];	
}

-(NSMutableArray *)mencoderArgumentsWithOutputFile:(NSString *)outputFile
{
	NSMutableArray *arguments = [NSMutableArray array];
	[arguments addObjectsFromArray:[[_encodeFormat objectForKey:@"encoderVideoOptions"] componentsSeparatedByString:@" "]];
	[arguments addObjectsFromArray:[[_encodeFormat objectForKey:@"encoderAudioOptions"] componentsSeparatedByString:@" "]];
	[arguments addObjectsFromArray:[[_encodeFormat objectForKey:@"encoderOtherOptions"] componentsSeparatedByString:@" "]];
	[arguments addObject:@"-o"];
	[arguments addObject:outputFile];
	return arguments;
	
}

-(void)cleanupFiles
{
    NSFileManager *fm = [NSFileManager defaultManager];
    if (downloadFilePath) {
        [downloadFileHandle closeFile];
        [fm removeItemAtPath:downloadFilePath error:nil];
    }
    if (bufferFilePath) {
        [bufferFileReadHandle closeFile];
        [bufferFileWriteHandle closeFile];
        [fm removeItemAtPath:bufferFilePath error:nil];
    }
    if (encodeLogFileHandle) {
        [encodeLogFileHandle closeFile];
        [fm removeItemAtPath:encodeLogFilePath error:nil];
    }
    if (decryptFileHandle) {
        [decryptFileHandle closeFile];
        [fm removeItemAtPath:decryptFilePath error:nil];
    }
    if (decryptLogFileHandle) {
        [decryptLogFileHandle closeFile];
        [fm removeItemAtPath:decryptLogFilePath error:nil];
    }
}

-(BOOL)cancel
{
    BOOL ret = YES;
    if (_downloadStatus != kMTStatusNew && _downloadStatus != kMTStatusDone) {
		//Put alert here
		NSAlert *myAlert = [NSAlert alertWithMessageText:[NSString stringWithFormat:@"Do you want to cancel active download of '%@'?",_showTitle] defaultButton:@"No" alternateButton:@"Yes" otherButton:nil informativeTextWithFormat:@""];
		myAlert.alertStyle = NSCriticalAlertStyle;
		NSInteger result = [myAlert runModal];
		if (result != NSAlertAlternateReturn) {
			ret = NO;
		}

    }
    if (ret) {
        NSFileManager *fm = [NSFileManager defaultManager];
		self.isCanceled = YES;
		[NSObject cancelPreviousPerformRequestsWithTarget:self];
        if (_downloadStatus == kMTStatusDownloading && activeURLConnection) {
            [activeURLConnection cancel];
            activeURLConnection = nil;
            [fm removeItemAtPath:decryptFilePath error:nil];
        }
		while (pipingData){
			//Block until latest pipe write is complete
		} //Wait for pipe out to complete
        [self cleanupFiles]; //Everything but the final file
        if(decrypterTask && [decrypterTask isRunning]) {
            [decrypterTask terminate];
        }
        if(encoderTask && [encoderTask isRunning]) {
            [encoderTask terminate];
        }
        if (encodeFileHandle) {
            [encodeFileHandle closeFile];
            [fm removeItemAtPath:encodeFilePath error:nil];
        }
        if (_downloadStatus == kMTStatusEncoding || (_simultaneousEncode && _downloadStatus == kMTStatusDownloading)) {
            [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationEncodeDidFinish object:self];
        }
        _downloadStatus = kMTStatusNew;
        _processProgress = 0.0;
        _showStatus = @"";
    }
    return ret;
}

-(void)updateProgress
{
    [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationProgressUpdated object:nil];
}

-(void)writeData
{
	writingData = YES;
	int chunkSize = 10000;
	int nchunks = 0;
	int chunkReleaseMemory = 10;
	unsigned long dataRead;
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSData *data = nil;
	if (!_isCanceled) {
		data = [bufferFileReadHandle readDataOfLength:chunkSize];
	}
	pipingData = YES;
	if (!_isCanceled) [downloadFileHandle writeData:data];
	pipingData = NO;
	dataRead = data.length;
	while (dataRead == chunkSize && !_isCanceled) {
		data = [bufferFileReadHandle readDataOfLength:chunkSize];
		pipingData = YES;
		if (!_isCanceled) [downloadFileHandle writeData:data];
		pipingData = NO;
		if (_isCanceled) break;
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
	if (!downloadingURL || _isCanceled) {
		[downloadFileHandle closeFile];
		if (downloadFileHandle != [pipe1 fileHandleForWriting]) {
			[downloadFileHandle release];
		}
		downloadFileHandle = nil;
		[bufferFileReadHandle closeFile];
		[bufferFileReadHandle release];
		bufferFileReadHandle = nil;
		[[NSFileManager defaultManager] removeItemAtPath:bufferFilePath error:nil];

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
		[self performSelectorInBackground:@selector(writeData) withObject:nil];
	}
}

- (BOOL)connection:(NSURLConnection *)connection canAuthenticateAgainstProtectionSpace:(NSURLProtectionSpace *)protectionSpace {
    return [protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust];
}

- (void)connection:(NSURLConnection *)connection didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge {
    //    [challenge.sender useCredential:[NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust] forAuthenticationChallenge:challenge];
    [challenge.sender useCredential:[NSURLCredential credentialWithUser:@"tivo" password:_mediaKey persistence:NSURLCredentialPersistencePermanent] forAuthenticationChallenge:challenge];
    [challenge.sender continueWithoutCredentialForAuthenticationChallenge:challenge];
}

-(void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error
{
    NSLog(@"URL Connection Failed with error %@",error);
	_downloadStatus = kMTStatusNew;
	activeURLConnection = nil;
}


-(void)connectionDidFinishLoading:(NSURLConnection *)connection
{
    if (!_isSimultaneousEncoding) {
        _fileSize = (double)[downloadFileHandle offsetInFile];
       [downloadFileHandle release];
        downloadFileHandle = nil;
        _downloadStatus = kMTStatusDownloaded;
    } else {
        _downloadStatus = kMTStatusEncoding;
        _showStatus = @"Encoding";
 		downloadingURL = NO;
       [self performSelector:@selector(trackDownloadEncode) withObject:nil afterDelay:0.3];
        _fileSize = (double)[bufferFileWriteHandle offsetInFile];
        [bufferFileWriteHandle closeFile];
    }
	activeURLConnection = nil;
    [self performSelector:@selector(sendNotification:) withObject:kMTNotificationDownloadDidFinish afterDelay:4.0];
}

#pragma mark - Misc Support Functions

- (NSDate *)dateForRFC3339DateTimeString:(NSString *)rfc3339DateTimeString
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
        NSLocale *                  enUSPOSIXLocale;
		
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
    [[NSNotificationCenter defaultCenter] postNotificationName:notification object:nil];
    
}
#pragma mark Setters (most to complete parsing)

-(void) setTime: (NSString *) newTime {
	if (newTime != _time) {
        [_time release];
        _time = [newTime retain];
        self.showDate = [self dateForRFC3339DateTimeString:_time];
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

#pragma mark - Custom Setters

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

#pragma mark - Memory Management

-(void)dealloc
{
    self.urlString = nil;
    self.downloadDirectory = nil;
    self.mediaKey = nil;
    self.showTitle = nil;
    self.showDescription = nil;
    self.showStatus = nil;
    self.URL = nil;
    self.encodeFormat = nil;
    self.tiVo = nil;
	if (elementString) {
		[elementString release];
	}
	if (elementArray) {
		[elementArray release];
	}
    [self deallocDownloadHandling];
    [devNullFileHandle release];
	[parseTermMapping release];
	[super dealloc];
}


@end
