//
//  MTTiVoShow.m
//  cTiVo
//
//  Created by Scott Buchanan on 12/18/12.
//  Copyright (c) 2012 Scott Buchanan. All rights reserved.
//
// Class for handling individual TiVo Shows

#import "MTTiVoShow.h"

@implementation MTTiVoShow

-(id)init
{
    self = [super init];
    if (self) {
        activeTask = nil;
        _showID = 0;
        _showStatus = @"";
		targetFilePath = nil;
		sourceFilePath = nil;
        _addToiTunesWhenEncoded = NO;
        _simultaneousEncode = YES;
		activeTask = nil;
		tivodecoderTask = nil;
		dataToWrite = [[NSMutableArray alloc] init];
		writingData = NO;
		downloadingURL = NO;
		pipingData = NO;
		fileBufferRead = fileBufferWrite = nil;
		fileBufferPath = nil;
    }
    return self;
}


#pragma mark - Download decrypt and encode Methods

-(void)download
{
	self.isCanceled = NO;
    NSURLRequest *thisRequest = [NSURLRequest requestWithURL:[NSURL URLWithString:_urlString ]];
//    activeURLConnection = [NSURLConnection connectionWithRequest:thisRequest delegate:self];
    activeURLConnection = [[[NSURLConnection alloc] initWithRequest:thisRequest delegate:self startImmediately:NO] autorelease];
    if (targetFilePath) {
        [targetFilePath release];
        targetFilePath = nil;
    }
    if (fileBufferPath) {
        [fileBufferPath release];
    }
	fileBufferPath = [[NSString stringWithFormat:@"/tmp/buffer%@.bin",_title] retain];
	NSFileManager *fm = [NSFileManager defaultManager];
	[fm createFileAtPath:fileBufferPath contents:[NSData data] attributes:nil];
	if (fileBufferWrite) {
		[fileBufferWrite release];
	}
	if (fileBufferRead) {
		[fileBufferRead release];
	}
	fileBufferRead = [[NSFileHandle fileHandleForReadingAtPath:fileBufferPath] retain];
	fileBufferWrite = [[NSFileHandle fileHandleForWritingAtPath:fileBufferPath] retain];
    if (!_simultaneousEncode || [[_encodeFormat objectForKey:@"mustDownloadFirst"] boolValue]) {
        targetFilePath = [[NSString stringWithFormat:@"%@%@.tivo",_downloadDirectory ,_title] retain];
        NSFileManager *fm = [NSFileManager defaultManager];
        [fm createFileAtPath:targetFilePath contents:[NSData data] attributes:nil];
        activeFile = [[NSFileHandle fileHandleForWritingAtPath:targetFilePath] retain];
        _isSimultaneousEncoding = NO;
    } else { //We'll build the full piped download chain here
        pipe1 = [[NSPipe pipe] retain];
        pipe2 = [[NSPipe pipe] retain];
		activeFile = [pipe1 fileHandleForWriting];
       //Decrypting section of full pipeline
        encodeFilePath = [[NSString stringWithFormat:@"/tmp/encoding%@.txt",_title] retain];
        [[NSFileManager defaultManager] createFileAtPath:encodeFilePath contents:[NSData data] attributes:nil];
        encodeFile  = [[NSFileHandle fileHandleForWritingAtPath:encodeFilePath] retain];
		if (tivodecoderTask) {
			if ([tivodecoderTask isRunning]) {
				[tivodecoderTask terminate];
			}
			[tivodecoderTask release];
		}
        tivodecoderTask  = [[NSTask alloc] init];
        NSString *tivodecoderLaunchPath = [[[NSBundle mainBundle] pathForResource:@"tivodecode" ofType:@""] retain];
		[tivodecoderTask setLaunchPath:tivodecoderLaunchPath];
		NSMutableArray *arguments = [NSMutableArray arrayWithObjects:
                        [NSString stringWithFormat:@"-m%@",_mediaKey],
                        @"--",
                        @"-",
                        nil];
        [tivodecoderTask setArguments:arguments];
        [tivodecoderTask setStandardInput:pipe1];
        [tivodecoderTask setStandardOutput:pipe2];
        NSString *mencoderLaunchPath;
		if ([(NSString *)[_encodeFormat objectForKey:@"encoderUsed"] caseInsensitiveCompare:@"mencoder"] == NSOrderedSame ) {
			targetFilePath = [[NSString stringWithFormat:@"%@/%@%@",_downloadDirectory,_title,[_encodeFormat objectForKey:@"filenameExtension"]] retain];
			activeTask = [[NSTask alloc] init];
            mencoderLaunchPath = [[[NSBundle mainBundle] pathForResource:@"mencoder" ofType:@""] retain];
			[activeTask setLaunchPath:mencoderLaunchPath];
        
			arguments = [self mencoderArgumentsWithOutputFile:targetFilePath];
			[arguments addObject:@"-"];  //Take input from standard Input
			[activeTask setArguments:arguments];
			[activeTask setStandardInput:pipe2];
			[activeTask setStandardOutput:encodeFile];
			[activeTask setStandardError:encodeFile];
		}
        [tivodecoderTask launch];
        [activeTask launch];
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
    if([activeTask isRunning]) {
        [self performSelector:@selector(trackDownloadEncode) withObject:nil afterDelay:0.3];
    } else {
        _downloadStatus = kMTStatusDone;
        _showStatus = @"Complete";
        _processProgress = 1.0;
        [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationEncodeDidFinish object:nil];
        [activeTask release];
        activeTask = nil;
        [tivodecoderTask release];
        tivodecoderTask = nil;
        [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationProgressUpdated object:nil];
    }
}

-(void)decrypt
{
    if (activeTask) {
        [activeTask release];
    }
	if (targetFilePath) {
		[targetFilePath release];
	}
	if (activeFilePath) {
		[activeFilePath release];
	}
	if (sourceFilePath) {
		[sourceFilePath release];
	}
	targetFilePath = [[NSString stringWithFormat:@"%@%@.tivo.mpg",_downloadDirectory,_title] retain];
	activeFilePath = [[NSString stringWithFormat:@"/tmp/decoding%@.txt",_title] retain];
	[[NSFileManager defaultManager] createFileAtPath:activeFilePath contents:[NSData data] attributes:nil];
	activeFile = [NSFileHandle fileHandleForWritingAtPath:activeFilePath];
	activeTask = [[NSTask alloc] init];
	[activeTask setLaunchPath:[[NSBundle mainBundle] pathForResource:@"tivodecode" ofType:@""]];
	[activeTask setStandardOutput:activeFile];
	[activeTask setStandardError:activeFile];
	//Find the source file size
	sourceFilePath = [[NSString stringWithFormat:@"%@/%@.tivo",_downloadDirectory,_title] retain];
	NSFileHandle *sourceFileHandle = [NSFileHandle fileHandleForReadingAtPath:sourceFilePath];
	_fileSize = (double)[sourceFileHandle seekToEndOfFile];
	
    // tivodecode -m0636497662 -o Two\ and\ a\ Half\ Men.mpg -v Two\ and\ a\ Half\ Men.TiVo
    
	NSArray *arguments = [NSArray arrayWithObjects:
						  [NSString stringWithFormat:@"-m%@",_mediaKey],
						  [NSString stringWithFormat:@"-o%@",targetFilePath],
						  @"-v",
						  [NSString stringWithFormat:@"%@%@.tivo",_downloadDirectory,_title],
						  nil];
    _processProgress = 0.0;
 	[[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationProgressUpdated object:nil];
   _downloadStatus = kMTStatusDecrypting;
	_showStatus = @"Decrypting";
	[activeTask setArguments:arguments];
	[activeTask launch];
	[self performSelector:@selector(trackDecrypts) withObject:nil afterDelay:0.3];
	
}

-(void)trackDecrypts
{
	if (![activeTask isRunning]) {
		_processProgress = 1.0;
		[[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationProgressUpdated object:nil];
        _downloadStatus = kMTStatusDecrypted;
		NSError *thisError = nil;
		[[NSFileManager defaultManager] removeItemAtPath:sourceFilePath error:&thisError];
		[sourceFilePath release];
		sourceFilePath = nil;
		[targetFilePath release];
		targetFilePath = nil;
 		[activeTask release];
		activeTask = nil;
       [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationDecryptDidFinish object:nil];
		return;
	}
	NSString *readFile = [NSString stringWithFormat:@"/tmp/decoding%@.txt",_title];
	NSFileHandle *readFileHandle = [NSFileHandle fileHandleForReadingAtPath:readFile];
	unsigned long long fileSize = [readFileHandle seekToEndOfFile];
	if (fileSize > 100) {
		[readFileHandle seekToFileOffset:(fileSize-100)];
		NSData *tailOfFile = [readFileHandle readDataOfLength:100];
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
	if (activeTask) {
		[activeTask release];
	}
	if (targetFilePath) {
		[targetFilePath release];
	}
	if (sourceFilePath) {
		[sourceFilePath release];
	}
	targetFilePath = [[NSString stringWithFormat:@"%@/%@%@",_downloadDirectory,_title,[_encodeFormat objectForKey:@"filenameExtension"]] retain];
	if (activeFilePath) {
		[activeFilePath release];
	}
	activeFilePath = [[NSString stringWithFormat:@"/tmp/encoding%@.txt",_title] retain];
	sourceFilePath = [[NSString stringWithFormat:@"%@/%@.tivo.mpg",_downloadDirectory,_title] retain];
	[[NSFileManager defaultManager] createFileAtPath:activeFilePath contents:[NSData data] attributes:nil];
	activeFile = [NSFileHandle fileHandleForWritingAtPath:activeFilePath];
	activeTask = [[NSTask alloc] init];
//	NSDictionary *selectedFormat = [programEncoding objectForKey:kMTSelectedFormat];
	NSMutableArray *arguments;
	if ([(NSString *)[_encodeFormat objectForKey:@"encoderUsed"] caseInsensitiveCompare:@"mencoder"] == NSOrderedSame ) {
		[activeTask setLaunchPath:[[NSBundle mainBundle] pathForResource:@"mencoder" ofType:@""]];
		arguments = [self mencoderArgumentsWithOutputFile:targetFilePath];        
		[arguments addObject:sourceFilePath];  //start with the input file
		
	}
	if ([(NSString *)[_encodeFormat objectForKey:@"encoderUsed"] caseInsensitiveCompare:@"HandBrake"] == NSOrderedSame ) {
		arguments = [NSMutableArray array];
		[activeTask setLaunchPath:[[NSBundle mainBundle] pathForResource:@"HandBrakeCLI" ofType:@""]];
		[arguments addObject:sourceFilePath];  //start with the input file
		[arguments addObject:[NSString stringWithFormat:@"-o%@/%@%@",_downloadDirectory,_title,[_encodeFormat objectForKey:@"filenameExtension"]]];  //add the output file
		[arguments addObject:[_encodeFormat objectForKey:@"encoderVideoOptions"]];
		if ([_encodeFormat objectForKey:@"encoderAudioOptions"] && ((NSString *)[_encodeFormat objectForKey:@"encoderAudioOptions"]).length) {
			[arguments addObject:[_encodeFormat objectForKey:@"encoderAudioOptions"]];
		}
		if ([_encodeFormat objectForKey:@"encoderOtherOptions"] && ((NSString *)[_encodeFormat objectForKey:@"encoderOtherOptions"]).length) {
			[arguments addObject:[_encodeFormat objectForKey:@"encoderOtherOptions"]];
		}
	}
	[activeTask setArguments:arguments];
	[activeTask setStandardOutput:activeFile];
	[activeTask setStandardError:[NSFileHandle fileHandleForWritingAtPath:@"/dev/null"]];
    _processProgress = 0.0;
	[[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationProgressUpdated object:nil];
	[activeTask launch];
    _downloadStatus = kMTStatusEncoding;
	_showStatus = @"Encoding";
	[self performSelector:@selector(trackEncodes) withObject:nil afterDelay:0.5];
	
}

-(void)trackEncodes
{
	if (![activeTask isRunning]) {
        _processProgress = 1.0;
        [[NSFileManager defaultManager] removeItemAtPath:sourceFilePath error:nil];
		[sourceFilePath release];
		sourceFilePath = nil;
		[activeTask release];
		activeTask = nil;
        _showStatus = @"Complete";
        _downloadStatus = kMTStatusDone;
		[[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationProgressUpdated object:nil];
        [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationEncodeDidFinish object:nil];
        if (_addToiTunesWhenEncoded) {
            iTunesApplication *iTunes = [SBApplication applicationWithBundleIdentifier:@"com.apple.iTunes"];
            if (iTunes) {
                [iTunes add:[NSArray arrayWithObject:[NSURL fileURLWithPath:targetFilePath]] to:nil];
            }
        }
		[targetFilePath release];
		targetFilePath = nil;
		return;
	}
	double newProgressValue = 0;
	NSString *readFile = [NSString stringWithFormat:@"/tmp/encoding%@.txt",_title];
	NSFileHandle *readFileHandle = [NSFileHandle fileHandleForReadingAtPath:readFile];
	unsigned long long fileSize = [readFileHandle seekToEndOfFile];
	if (fileSize > 100) {
		[readFileHandle seekToFileOffset:(fileSize-100)];
		NSData *tailOfFile = [readFileHandle readDataOfLength:100];
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

-(BOOL)cancel
{
    BOOL ret = YES;
    if (_downloadStatus != kMTStatusNew && _downloadStatus != kMTStatusDone) {
		//Put alert here
		NSAlert *myAlert = [NSAlert alertWithMessageText:[NSString stringWithFormat:@"Do you want to cancel Download of %@",_title] defaultButton:@"No" alternateButton:@"Yes" otherButton:nil informativeTextWithFormat:@""];
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
            [fm removeItemAtPath:targetFilePath error:nil];
        }
		while (pipingData); //Wait for pipe out to complete
        if(activeTask && [activeTask isRunning]) {
            [activeTask terminate];
            [fm removeItemAtPath:sourceFilePath error:nil];
            [fm removeItemAtPath:targetFilePath error:nil];
            activeTask = nil;
			if (activeFilePath) {
				[[NSFileManager defaultManager] removeItemAtPath:activeFilePath error:nil];
				[activeFilePath release];
				activeFilePath = nil;
			}
			if (fileBufferPath) {
				[[NSFileManager defaultManager] removeItemAtPath:fileBufferPath error:nil];
				[fileBufferPath release];
				fileBufferPath = nil;
			}
			if (encodeFilePath) {
				[encodeFile closeFile];
				[[NSFileManager defaultManager] removeItemAtPath:encodeFilePath error:nil];
				[encodeFile release];
				encodeFile = nil;
				[encodeFilePath release];
				encodeFilePath = nil;
			}
			if (_downloadStatus == kMTStatusEncoding || _simultaneousEncode) {
				[[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationEncodeDidFinish object:nil];
			}
        }
        if(tivodecoderTask && [tivodecoderTask isRunning]) {
            [tivodecoderTask terminate];
            tivodecoderTask = nil;
        }
        _downloadStatus = kMTStatusNew;
        _processProgress = 0.0;
        _showStatus = @"";
    }
    return ret;
}

-(void)writeData
{
	writingData = YES;
	int chunkSize = 10000;
	int nchunks = 0;
	int chunkReleaseMemory = 10;
	unsigned long dataRead;
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSData *data = [fileBufferRead readDataOfLength:chunkSize];
	pipingData = YES;
	[activeFile writeData:data];
	pipingData = NO;
	dataRead = data.length;
	while (dataRead == chunkSize && !_isCanceled) {
		data = [fileBufferRead readDataOfLength:chunkSize];
		pipingData = YES;
		[activeFile writeData:data];
		pipingData = NO;
		if (_isCanceled) break;
		dataRead = data.length;
		dataDownloaded += data.length;
		_processProgress = dataDownloaded/_fileSize;
		[[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationProgressUpdated object:nil];
		nchunks++;
		if (nchunks == chunkReleaseMemory) {
			nchunks = 0;
			[pool drain];
			pool = [[NSAutoreleasePool alloc] init];
		}
	}
	[pool drain];
	if (!downloadingURL || _isCanceled) {
		[activeFile closeFile];
		[activeFile release];
		activeFile = nil;
		[fileBufferRead closeFile];
		[fileBufferRead release];
		fileBufferRead = nil;
		[[NSFileManager defaultManager] removeItemAtPath:fileBufferPath error:nil];
		[fileBufferPath release];
		fileBufferPath = nil;
	}
	writingData = NO;
}

#pragma mark - NSURL Delegate Methods

-(void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data
{
	[fileBufferWrite writeData:data];
	if (!writingData) {
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
		while (pipingData);
        _downloadStatus = kMTStatusDownloaded;
    } else {
        _downloadStatus = kMTStatusEncoding;
        _showStatus = @"Encoding";
 		downloadingURL = NO;
		[fileBufferWrite closeFile];
		[fileBufferWrite release];
		fileBufferWrite = nil;
       [self performSelector:@selector(trackDownloadEncode) withObject:nil afterDelay:0.3];
    }
	activeURLConnection = nil;
    [self performSelector:@selector(sendNotification:) withObject:kMTNotificationDownloadDidFinish afterDelay:4.0];
}

-(void)sendNotification:(NSString *)notification
{
    [[NSNotificationCenter defaultCenter] postNotificationName:notification object:nil];
    
}

#pragma mark - Memory Management

-(void)dealloc
{
    self.urlString = nil;
    self.downloadDirectory = nil;
    self.mediaKey = nil;
    self.title = nil;
    self.description = nil;
    self.showStatus = nil;
    self.URL = nil;
    self.encodeFormat = nil;
    self.tiVo = nil;
	if (targetFilePath) {
		[targetFilePath release];
	}
	if (sourceFilePath) {
		[sourceFilePath release];
	}
	if (encodeFilePath) {
		[encodeFilePath release];
	}
	if (activeTask) {
		if ([activeTask isRunning]) {
			[activeTask terminate];
		}
		[activeTask release];
	}
	if (tivodecoderTask) {
		if ([tivodecoderTask isRunning]) {
			[tivodecoderTask terminate];
		}
		[tivodecoderTask release];
	}
    [pipe1 release];
    [pipe2 release];
	[dataToWrite release];
	[fileBufferPath release];
	[fileBufferRead release];
	[fileBufferWrite release];
//    [dataBuffer release];
	[super dealloc];
}


@end
