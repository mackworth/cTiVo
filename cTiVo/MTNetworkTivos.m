//
//  MTNetworkTivos.m
//  myTivo
//
//  Created by Scott Buchanan on 12/6/12.
//  Copyright (c) 2012 Scott Buchanan. All rights reserved.
//

#import "MTNetworkTivos.h"


@implementation MTNetworkTivos

-(void)awakeFromNib
{
	tivoBrowser = [[NSNetServiceBrowser alloc] init];
	tivoBrowser.delegate = self;
	[tivoBrowser scheduleInRunLoop:[NSRunLoop mainRunLoop] forMode:NSDefaultRunLoopMode];
	[tivoBrowser searchForServicesOfType:@"_tivo-videos._tcp" inDomain:@"local"];
	_tivoNames = [[NSMutableArray alloc] init];
	_tivoServices = [[NSMutableArray alloc] init];
	_videoListNeedsFilling = YES;
	listingData = [[NSMutableData alloc] init];
	_recordings = nil;
	[tivoList removeAllItems];
	NSString *formatListPath = [[NSBundle mainBundle] pathForResource:@"formats" ofType:@"plist"];
	NSDictionary *formats = [NSDictionary dictionaryWithContentsOfFile:formatListPath];
	encodingFormats = [[formats objectForKey:@"formats"] retain];
	[self configureFormatsPopup];
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	if (![defaults objectForKey:kMTMediaKeys]) {
		mediaKeys = [[NSMutableDictionary alloc] init];
		[defaults setObject:mediaKeys forKey:kMTMediaKeys];
	}
	if (![defaults objectForKey:kMTDownloadDirectory]) {
		NSString *ddir = [NSString stringWithFormat:@"%@/Downloads/",NSHomeDirectory()];
		[defaults setValue:ddir forKey:kMTDownloadDirectory];
	}
	downloadDirectory.stringValue = [defaults objectForKey:kMTDownloadDirectory];
	mediaKeys = [[NSMutableDictionary dictionaryWithDictionary:[defaults objectForKey:kMTMediaKeys]] retain];
	[loadingProgramListIndicator setDisplayedWhenStopped:NO];
	[loadingProgramListIndicator stopAnimation:nil];
	loadingProgramListLabel.stringValue = @"";
	_downloadQueue = [[NSMutableArray alloc] init];
	programEncoding = nil;
	programDecrypting = nil;
	programDownloading = nil;
	downloadURLConnection = nil;
	programListURLConnection = nil;
	downloadFile = nil;
	decryptingTask = nil;
	encodingTask = nil;
	stdOutFileHandle = nil;
	tivoConnectingTo = nil;
    decryptTableCell = nil;
    downloadTableCell = nil;
    encodeTableCell = nil;
	

//	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(manageDownloads) name:kMTNotificationDownloadQueueUpdated object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(manageDecrypts) name:kMTNotificationDownloadDidFinish object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(manageEncodes) name:kMTNotificationDecryptDidFinish object:nil];
}

-(void)configureFormatsPopup
{
	[formatList removeAllItems];
	for (NSDictionary *f in encodingFormats) {
		[formatList addItemWithTitle:[f objectForKey:@"name"]];
		NSMenuItem *item = [formatList lastItem];
		[item setRepresentedObject:f];
		if ([[NSUserDefaults standardUserDefaults] stringForKey:kMTSelectedFormat]) {
			if([[[NSUserDefaults standardUserDefaults] stringForKey:kMTSelectedFormat] compare:[f objectForKey:@"name"]] == NSOrderedSame) {
				[formatList selectItem:[formatList lastItem]];
			}
		}
	}
}

-(void)setProgressIndicatorForProgram:(NSMutableDictionary *)program withValue:(double)value
{
	long numRows = [downloadQueueTable numberOfRows];
	MTDownloadListCellView *thisCellView = nil;
	if ([_downloadQueue indexOfObject:program] < numRows) {
		thisCellView = [downloadQueueTable viewAtColumn:0 row:[_downloadQueue indexOfObject:program] makeIfNecessary:NO];
	}
	if (thisCellView) {
		thisCellView.progressIndicator.doubleValue = value;
	}
    [program setObject:[NSNumber numberWithDouble:value] forKey:kMTDownloadPercent];
    
}

-(void)setProgressStatus:(NSMutableDictionary *)program withValue:(NSString *)status
{
    [program setObject:status forKey:kMTDownloadStatus];
	long numRows = [downloadQueueTable numberOfRows];
	MTDownloadListCellView *thisCellView = nil;
	if ([_downloadQueue indexOfObject:program] < numRows) {
		thisCellView = [downloadQueueTable viewAtColumn:0 row:[_downloadQueue indexOfObject:program] makeIfNecessary:NO];
	}
	if (thisCellView) {
		thisCellView.progressIndicator.rightText.stringValue = status;
		[thisCellView setNeedsDisplay:YES];
	}
    
}

#pragma mark - UI Actions

-(IBAction)selectTivo:(id)sender
{
    NSPopUpButton *thisButton = (NSPopUpButton *)sender;
    NSMenuItem *selectedTivo = [thisButton selectedItem];
	if ([mediaKeys objectForKey:selectedTivo.title]) {
		mediaKeyLabel.stringValue = [mediaKeys objectForKey:selectedTivo.title];
	} else {
		mediaKeyLabel.stringValue = @"";
	}
	[[NSUserDefaults standardUserDefaults] setObject:selectedTivo.title forKey:kMTSelectedTivo];
    [self fetchVideoListFromHost];
}

-(IBAction)selectFormat:(id)sender
{
    NSPopUpButton *thisButton = (NSPopUpButton *)sender;
    NSMenuItem *selectedFormat= [thisButton selectedItem];
	[[NSUserDefaults standardUserDefaults] setObject:selectedFormat.title forKey:kMTSelectedFormat];
	
}

-(IBAction)updateDownloadQueue:(id)sender
{
    for (int i = 0; i < _recordings.count; i++) {
        if([programListTable isRowSelected:i]) {
            [self addProgramToDownloadQueue:[_recordings objectAtIndex:i]];
        } 
    }
	[programListTable deselectAll:nil];
	[downloadQueueTable deselectAll:nil];
	[[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationDownloadQueueUpdated object:nil];
}

-(IBAction)removeFromDownloadQueue:(id)sender
{
	NSMutableArray *itemsToRemove = [NSMutableArray array];
    for (int i = 0; i <  _downloadQueue.count; i++) {
        if ([downloadQueueTable isRowSelected:i]) {
            NSMutableDictionary *programToRemove = [_downloadQueue objectAtIndex:i];
			[itemsToRemove addObject:programToRemove];
            if ([[programToRemove objectForKey:kMTStatus] intValue] == kMTStatusDownloading) {
                [self cancelDownload:nil];
            }
            if ([[programToRemove objectForKey:kMTStatus] intValue] == kMTStatusDecrypting) {
                [self cancelDecrypt:nil];
            }
            if ([[programToRemove objectForKey:kMTStatus] intValue] == kMTStatusEncoding) {
                [self cancelEncode:nil];
            }
        }
    }
	for (id i in itemsToRemove) {
		[_downloadQueue removeObject:i];
	}
	[programListTable deselectAll:nil];
	[downloadQueueTable deselectAll:nil];
	[[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationDownloadQueueUpdated object:nil];

}

-(IBAction)cancelDownload:(id)sender
{
	NSAlert *myAlert = [NSAlert alertWithMessageText:[NSString stringWithFormat:@"Do you want to cancel Download of %@",[programDownloading objectForKey:@"Title"]] defaultButton:@"No" alternateButton:@"Yes" otherButton:nil informativeTextWithFormat:@""];
	myAlert.alertStyle = NSCriticalAlertStyle;
	NSInteger result = [myAlert runModal];
	if (result == NSAlertAlternateReturn) {
		[downloadURLConnection cancel];
		[downloadURLConnection release];
		downloadURLConnection = nil;
//		downloadingLabel.stringValue = @"Downloading";
//		downloadingProgress.doubleValue = 0;
		[downloadFile closeFile];
		[downloadFile release];
		downloadFile = nil;
		programDownloading = nil;
		[self performSelector:@selector(manageDownloads) withObject:nil afterDelay:3.0];
	}
}

-(IBAction)getDownloadDirectory:(id)sender
{
	myOpenPanel = [NSOpenPanel openPanel];
	[myOpenPanel setCanChooseDirectories:YES];
	[myOpenPanel setCanChooseFiles:NO];
	[myOpenPanel setAllowsMultipleSelection:NO];
	NSInteger ret = [myOpenPanel runModal];
	if (ret == NSFileHandlingPanelOKButton) {
		NSString *dir = [myOpenPanel.URL.absoluteString substringFromIndex:16];
		downloadDirectory.stringValue = dir;
		[[NSUserDefaults standardUserDefaults] setValue:dir forKey:kMTDownloadDirectory];
	}
}

-(IBAction)cancelDecrypt:(id)sender
{
	NSAlert *myAlert = [NSAlert alertWithMessageText:[NSString stringWithFormat:@"Do you want to cancel Decrypting of %@",[programDecrypting objectForKey:@"Title"]] defaultButton:@"No" alternateButton:@"Yes" otherButton:nil informativeTextWithFormat:@""];
	myAlert.alertStyle = NSCriticalAlertStyle;
	NSInteger result = [myAlert runModal];
	if (result == NSAlertAlternateReturn && [decryptingTask isRunning]) {
		[decryptingTask terminate];
		[decryptingTask release];
		decryptingTask = nil;
        [self setProgressIndicatorForProgram:programDecrypting withValue:0.0];
//		decryptingProgress.doubleValue = 0.0;
//		decryptingLabel.stringValue = @"Decrypting";
		programDecrypting = nil;
		[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(trackDecrypts) object:nil];
		[self manageDecrypts];
	}
	
}

-(IBAction)cancelEncode:(id)sender
{
	NSAlert *myAlert = [NSAlert alertWithMessageText:[NSString stringWithFormat:@"Do you want to cancel Encoding of %@",[programEncoding objectForKey:@"Title"]] defaultButton:@"No" alternateButton:@"Yes" otherButton:nil informativeTextWithFormat:@""];
	myAlert.alertStyle = NSCriticalAlertStyle;
	NSInteger result = [myAlert runModal];
	if (result == NSAlertAlternateReturn && [encodingTask isRunning]) {
		[encodingTask terminate];
		[encodingTask release];
		encodingTask = nil;
//		encodingProgress.doubleValue = 0.0;
        [self setProgressIndicatorForProgram:programEncoding withValue:0.0];
//		encodingLabel.stringValue = @"Encoding";
		programEncoding = nil;
		[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(trackEncodes) object:nil];
		[self manageEncodes];
	}
	
}

-(void)addProgramToDownloadQueue:(NSDictionary *)program
{
	BOOL programFound = NO;
	for (NSDictionary *p in _downloadQueue) {
		if ([(NSString *)[p objectForKey:@"ID"] compare:(NSString *)[program objectForKey:@"ID"]] == NSOrderedSame	) {
			programFound = YES;
		}
	}
	if (programDownloading && [(NSString *)[programDownloading objectForKey:@"ID"] compare:(NSString *)[program objectForKey:@"ID"]] == NSOrderedSame	) {
		programFound = YES;
	}
	if (programDecrypting &&[(NSString *)[programDecrypting objectForKey:@"ID"] compare:(NSString *)[program objectForKey:@"ID"]] == NSOrderedSame	) {
		programFound = YES;
	}
	if (programEncoding &&[(NSString *)[programEncoding objectForKey:@"ID"] compare:(NSString *)[program objectForKey:@"ID"]] == NSOrderedSame	) {
		programFound = YES;
	}
	
	if (!programFound) {
		NSDictionary *selectedFormat = [[formatList selectedItem] representedObject];
		NSNetService *selectedTivo = [[tivoList selectedItem] representedObject];
		NSMutableDictionary *tmpDict = [NSMutableDictionary dictionaryWithDictionary:program];
		[tmpDict setObject:selectedFormat forKey:kMTSelectedFormat];
		[tmpDict setObject:selectedTivo forKey:kMTSelectedTivo];
        [tmpDict setObject:@"" forKey:kMTDownloadStatus	];
        [tmpDict setObject:[NSNumber numberWithInt:kMTStatusNew] forKey:kMTStatus];
		[tmpDict setObject:[NSNumber numberWithBool:NO] forKey:kMTIsDownloaded];
		[tmpDict setObject:[NSNumber numberWithBool:NO] forKey:kMTIsDecrypted];
		[tmpDict setObject:[NSNumber numberWithBool:NO] forKey:kMTIsEncoded];
		[_downloadQueue addObject:tmpDict];
	}
}

#pragma mark - Download Management

-(void)manageDownloads
{
	//Are we currently downloading - if so return
	if (programDownloading || downloadURLConnection || _downloadQueue.count == 0) {
		return;
	}
    //Find if any left in the queue need downloading
    for (int i = 0; i < _downloadQueue.count; i++) {
        if ([[(NSMutableDictionary *)[_downloadQueue objectAtIndex:i] objectForKey:kMTStatus] intValue] == kMTStatusNew) {
            programDownloading = [_downloadQueue objectAtIndex:i];
//            downloadTableCell = [downloadQueueTable viewAtColumn:0 row:i makeIfNecessary:NO];
//			[programDownloading setObject:@"Downloading" forKey:kMTDownloadStatus];
            [self setProgressStatus:programDownloading withValue:@"Downloading"];
            [programDownloading setObject:[NSNumber numberWithInt:kMTStatusDownloading] forKey:kMTStatus];
//			[programDownloading setObject:[NSNumber numberWithBool:YES] forKey:kMTIsDownloading];
            break;
        }
    }
    if (!programDownloading) {
        return;
    }
//	programDownloading = [[_downloadQueue objectAtIndex:0] retain];
	NSString *sizeString = [programDownloading objectForKey:@"Size"];
	double size = [[sizeString substringToIndex:sizeString.length-3] doubleValue];
	NSString *modifier = [sizeString substringFromIndex:sizeString.length-2];
	if ([modifier caseInsensitiveCompare:@"MB"] == NSOrderedSame) {
		size *= 1000 * 1000;
	} else {
		size *= 1000 * 1000 * 1000;
	}
	NSURLRequest *thisRequest = [NSURLRequest requestWithURL:[NSURL URLWithString:[programDownloading objectForKey:@"URL"]]];
	downloadURLConnection = [[NSURLConnection connectionWithRequest:thisRequest delegate:self] retain];
	NSString *downloadFilePath = [NSString stringWithFormat:@"%@%@.tivo",[[NSUserDefaults standardUserDefaults] objectForKey:kMTDownloadDirectory] ,[programDownloading objectForKey:@"Title"]];
	NSFileManager *fm = [NSFileManager defaultManager];
	[fm createFileAtPath:downloadFilePath contents:[NSData data] attributes:nil];
	downloadFile = [[NSFileHandle fileHandleForWritingAtPath:downloadFilePath] retain];
	[downloadURLConnection start];
	dataDownloaded = 0.0;
	referenceFileSize = size;
//	NSLog(@"Downloading %@ of size %lf",[programDownloading objectForKey:@"Title"],referenceFileSize);
	//Note track downloads is done by the NSURLConnection delegate
}

-(void)manageDecrypts
{
	if (programDecrypting) {
		return;
	}
    for (int i = 0; i < _downloadQueue.count; i++) {
        if ([[[_downloadQueue objectAtIndex:i] objectForKey:kMTStatus] intValue] == kMTStatusDownloaded) {
            programDecrypting = [_downloadQueue objectAtIndex:i];
            [self setProgressStatus:programDecrypting withValue:@"Decrypting"];
			[programDecrypting setObject:[NSNumber numberWithBool:YES] forKey:kMTIsDecrypting];
            [programDecrypting setObject:[NSNumber numberWithInt:kMTStatusDecrypting] forKey:kMTStatus];
			[downloadQueueTable reloadData];
           break;
        }
    }
    if (!programDecrypting) {
        return;
    }
	NSString *stdOutFile = [NSString stringWithFormat:@"/tmp/decoding%@.txt",[programDecrypting objectForKey:@"Title"]];
	[[NSFileManager defaultManager] createFileAtPath:stdOutFile contents:[NSData data] attributes:nil];
	stdOutFileHandle = [NSFileHandle fileHandleForWritingAtPath:stdOutFile];
	if (decryptingTask) {
		[decryptingTask release];
	}
	decryptingTask = [[NSTask alloc] init];
	[decryptingTask setLaunchPath:[[NSBundle mainBundle] pathForResource:@"tivodecode" ofType:@""]];
	[decryptingTask setStandardOutput:stdOutFileHandle];
	[decryptingTask setStandardError:stdOutFileHandle];
	//Find the source file size
	NSString *sourceFilePath = [NSString stringWithFormat:@"%@/%@.tivo",[[NSUserDefaults standardUserDefaults] objectForKey:kMTDownloadDirectory],[programDecrypting objectForKey:@"Title"]];
	NSFileHandle *sourceFileHandle = [NSFileHandle fileHandleForReadingAtPath:sourceFilePath];
	referenceFileSize = (double)[sourceFileHandle seekToEndOfFile];
	NSNetService *thisService = [programDecrypting objectForKey:kMTSelectedTivo];
	NSString *thisMediaKey = [mediaKeys objectForKey:thisService.name];
	
// tivodecode -m0636497662 -o Two\ and\ a\ Half\ Men.mpg -v Two\ and\ a\ Half\ Men.TiVo

	NSArray *arguments = [NSArray arrayWithObjects:
						  [NSString stringWithFormat:@"-m%@",thisMediaKey],
						  [NSString stringWithFormat:@"-o%@%@.tivo.mpg",[[NSUserDefaults standardUserDefaults] objectForKey:kMTDownloadDirectory],[programDecrypting objectForKey:@"Title"]],
						  @"-v",
						  [NSString stringWithFormat:@"%@%@.tivo",[[NSUserDefaults standardUserDefaults] objectForKey:kMTDownloadDirectory],[programDecrypting objectForKey:@"Title"]],
						  nil];
	[decryptingTask setArguments:arguments];
	[self setProgressIndicatorForProgram:programDecrypting withValue:0.0];
	[decryptingTask launch];
	[self performSelector:@selector(trackDecrypts) withObject:nil afterDelay:0.3];
	
}

-(void)trackDecrypts
{
	if (![decryptingTask isRunning]) {
		[self setProgressIndicatorForProgram:programDecrypting withValue:1.0];
        [self setProgressStatus:programDecrypting withValue:@"Decrypted"];
        [programDecrypting setObject:[NSNumber numberWithInt:kMTStatusDecrypted] forKey:kMTStatus];
		[programDecrypting setObject:[NSNumber numberWithBool:YES] forKey:kMTIsDecrypted];
		[downloadQueueTable reloadData];
		NSString *sourceFilePath = [NSString stringWithFormat:@"%@/%@.tivo",[[NSUserDefaults standardUserDefaults] objectForKey:kMTDownloadDirectory],[programDecrypting objectForKey:@"Title"]];
		NSError *thisError = nil;
		[[NSFileManager defaultManager] removeItemAtPath:sourceFilePath error:&thisError];

		programDecrypting = nil;
		[[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationDecryptDidFinish object:nil];
		[self manageDecrypts];
		return;
	}
	NSString *readFile = [NSString stringWithFormat:@"/tmp/decoding%@.txt",[programDecrypting objectForKey:@"Title"]];
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
		[self setProgressIndicatorForProgram:programDecrypting withValue:position/referenceFileSize];

	}
	[self performSelector:@selector(trackDecrypts) withObject:nil afterDelay:0.3];
	
	
}

-(void)manageEncodes
{
	if (programEncoding) {
		return;
	}
    for (int i = 0; i < _downloadQueue.count; i++) {
        if ([[[_downloadQueue objectAtIndex:i] objectForKey:kMTStatus] intValue] == kMTStatusDecrypted) {
            programEncoding = [_downloadQueue objectAtIndex:i];
            [self setProgressStatus:programEncoding withValue:@"Encoding"];
            [programEncoding setObject:[NSNumber numberWithInt:kMTStatusEncoding] forKey:kMTStatus];
			[programEncoding setObject:[NSNumber numberWithBool:YES] forKey:kMTIsEncoding];
			[downloadQueueTable reloadData];
            break;
        }
    }
    if (!programEncoding) {
        return;
    }
	NSString *stdOutFile = [NSString stringWithFormat:@"/tmp/encoding%@.txt",[programEncoding objectForKey:@"Title"]];
	[[NSFileManager defaultManager] createFileAtPath:stdOutFile contents:[NSData data] attributes:nil];
	stdOutFileHandle = [NSFileHandle fileHandleForWritingAtPath:stdOutFile];
	if (encodingTask) {
		[encodingTask release];
	}
	encodingTask = [[NSTask alloc] init];
	NSDictionary *selectedFormat = [programEncoding objectForKey:kMTSelectedFormat];
	NSMutableArray *arguments = [NSMutableArray array];
	if ([(NSString *)[selectedFormat objectForKey:@"encoderUsed"] caseInsensitiveCompare:@"mencoder"] == NSOrderedSame ) {
	
		[encodingTask setLaunchPath:[[NSBundle mainBundle] pathForResource:@"mencoder" ofType:@""]];
		[arguments addObject:[NSString stringWithFormat:@"%@/%@.tivo.mpg",[[NSUserDefaults standardUserDefaults] objectForKey:kMTDownloadDirectory],[programEncoding objectForKey:@"Title"]]];  //start with the input file
		[arguments addObjectsFromArray:[[selectedFormat objectForKey:@"encoderVideoOptions"] componentsSeparatedByString:@" "]];
		[arguments addObjectsFromArray:[[selectedFormat objectForKey:@"encoderAudioOptions"] componentsSeparatedByString:@" "]];
		[arguments addObjectsFromArray:[[selectedFormat objectForKey:@"encoderOtherOptions"] componentsSeparatedByString:@" "]];
		[arguments addObject:@"-o"];
		[arguments addObject:[NSString stringWithFormat:@"%@/%@%@",[[NSUserDefaults standardUserDefaults] objectForKey:kMTDownloadDirectory],[programEncoding objectForKey:@"Title"],[selectedFormat objectForKey:@"filenameExtension"]]];
		
	}
	if ([(NSString *)[selectedFormat objectForKey:@"encoderUsed"] caseInsensitiveCompare:@"HandBrake"] == NSOrderedSame ) {
		[encodingTask setLaunchPath:[[NSBundle mainBundle] pathForResource:@"HandBrakeCLI" ofType:@""]];
		[arguments addObject:[NSString stringWithFormat:@"-i%@/%@.tivo.mpg",[[NSUserDefaults standardUserDefaults] objectForKey:kMTDownloadDirectory],[programEncoding objectForKey:@"Title"]]];  //start with the input file
		[arguments addObject:[NSString stringWithFormat:@"-o%@/%@%@",[[NSUserDefaults standardUserDefaults] objectForKey:kMTDownloadDirectory],[programEncoding objectForKey:@"Title"],[selectedFormat objectForKey:@"filenameExtension"]]];  //add the output file
		[arguments addObject:[selectedFormat objectForKey:@"encoderVideoOptions"]];
		if ([selectedFormat objectForKey:@"encoderAudioOptions"] && ((NSString *)[selectedFormat objectForKey:@"encoderAudioOptions"]).length) {
			[arguments addObject:[selectedFormat objectForKey:@"encoderAudioOptions"]];
		}
		if ([selectedFormat objectForKey:@"encoderOtherOptions"] && ((NSString *)[selectedFormat objectForKey:@"encoderOtherOptions"]).length) {
			[arguments addObject:[selectedFormat objectForKey:@"encoderOtherOptions"]];
		}
	}
	[encodingTask setArguments:arguments];
	[encodingTask setStandardOutput:stdOutFileHandle];
	[encodingTask setStandardError:[NSFileHandle fileHandleForWritingAtPath:@"/dev/null"]];
	[self setProgressIndicatorForProgram:programEncoding withValue:0.0];
	percentComplete = 0;
	[encodingTask launch];
	[self performSelector:@selector(trackEncodes) withObject:nil afterDelay:0.5];
	
}

-(void)trackEncodes
{
	if (![encodingTask isRunning]) {
        [self setProgressIndicatorForProgram:programEncoding withValue:1.0];
        NSString *sourceFilePath = [NSString stringWithFormat:@"%@/%@.tivo.mpg",[[NSUserDefaults standardUserDefaults] objectForKey:kMTDownloadDirectory],[programEncoding objectForKey:@"Title"]];
        [[NSFileManager defaultManager] removeItemAtPath:sourceFilePath error:nil];
        [self setProgressStatus:programEncoding withValue:@"Complete"];
        [programEncoding setObject:[NSNumber numberWithBool:YES] forKey:kMTIsEncoded];

        programEncoding = nil;
        [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationEncodeDidFinish object:nil];
        [self manageEncodes];
		return;
	}
	NSDictionary *selectedFormat = [programEncoding objectForKey:kMTSelectedFormat];
	NSString *readFile = [NSString stringWithFormat:@"/tmp/encoding%@.txt",[programEncoding objectForKey:@"Title"]];
	NSFileHandle *readFileHandle = [NSFileHandle fileHandleForReadingAtPath:readFile];
	unsigned long long fileSize = [readFileHandle seekToEndOfFile];
	if (fileSize > 100) {
		[readFileHandle seekToFileOffset:(fileSize-100)];
		NSData *tailOfFile = [readFileHandle readDataOfLength:100];
		NSString *data = [[[NSString alloc] initWithData:tailOfFile encoding:NSUTF8StringEncoding] autorelease];
		if ([(NSString *)[selectedFormat objectForKey:@"encoderUsed"] caseInsensitiveCompare:@"mencoder"] == NSOrderedSame) {
			NSRegularExpression *percents = [NSRegularExpression regularExpressionWithPattern:@"\\((.*?)\\%\\)" options:NSRegularExpressionCaseInsensitive error:nil];
			NSArray *values = [percents matchesInString:data options:NSMatchingWithoutAnchoringBounds range:NSMakeRange(0, data.length)];
			NSTextCheckingResult *lastItem = [values lastObject];
			NSRange valueRange = [lastItem rangeAtIndex:1];
			percentComplete = [[data substringWithRange:valueRange] doubleValue]/100.0;
		}
		if ([(NSString *)[selectedFormat objectForKey:@"encoderUsed"] caseInsensitiveCompare:@"HandBrake"] == NSOrderedSame) {
			NSRegularExpression *percents = [NSRegularExpression regularExpressionWithPattern:@" ([\\d.]*?) \\% " options:NSRegularExpressionCaseInsensitive error:nil];
			NSArray *values = [percents matchesInString:data options:NSMatchingWithoutAnchoringBounds range:NSMakeRange(0, data.length)];
			if (values.count) {
				NSTextCheckingResult *lastItem = [values lastObject];
				NSRange valueRange = [lastItem rangeAtIndex:1];
				percentComplete = [[data substringWithRange:valueRange] doubleValue]/105.0;
			}
		}
        [self setProgressIndicatorForProgram:programEncoding withValue:percentComplete];
		
	}
	[self performSelector:@selector(trackEncodes) withObject:nil afterDelay:0.5];
	
}

#pragma mark - Memory Management

-(void)dealloc
{
	if (_recordings) {
		[_recordings release];
	}
	[_downloadQueue release];
	[encodingFormats release];
	[tivoBrowser release];
	[_tivoNames release];
	[_tivoServices release];
    [listingData release];
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[super dealloc];
}

-(void)fetchVideoListFromHost
{
    NSMenuItem *selectedTivo = [tivoList selectedItem];
    NSNetService *thisService = (NSNetService *)[selectedTivo representedObject];
	if (tivoConnectingTo && tivoConnectingTo == thisService) {
		return;
	}
	if (programListURLConnection) {
		[programListURLConnection cancel];
		[programListURLConnection release];
		programListURLConnection = nil;
	}
	tivoConnectingTo = thisService;
	NSString *host = thisService.hostName;
	NSString *mediaKeyString = @"";
	if ([mediaKeys objectForKey:thisService.name]) {
		mediaKeyString = [mediaKeys objectForKey:thisService.name];
	}
	 
	_recordings = [[NSMutableArray alloc] init];
	[[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationRecordingsUpdated object:nil];

    NSString *tivoURLString = [[NSString stringWithFormat:@"https://tivo:%@@%@/nowplaying/index.html?Recurse=Yes",mediaKeyString,host] stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    NSURL *tivoURL = [NSURL URLWithString:tivoURLString];
    NSURLRequest *tivoURLRequest = [NSURLRequest requestWithURL:tivoURL];
    programListURLConnection = [[NSURLConnection connectionWithRequest:tivoURLRequest delegate:self] retain];
    [listingData setData:[NSData data]];
	[loadingProgramListIndicator startAnimation:nil];
	loadingProgramListLabel.stringValue = @"Loading Programs";
    [programListURLConnection start];
                      
}

-(void)parseListingData
{
	if (_recordings) {
		[_recordings release];
	}
	_recordings = [[NSMutableArray alloc] init];
	
	NSString *listingDataString = [[[NSString alloc] initWithData:listingData encoding:NSUTF8StringEncoding] autorelease];
	NSRegularExpression *tableRx = [NSRegularExpression regularExpressionWithPattern:@"<table[^>]*>(.*?)</table>" options:NSRegularExpressionCaseInsensitive error:nil];
	NSRegularExpression *rowRx = [NSRegularExpression regularExpressionWithPattern:@"<tr[^>]*>(.*?)</tr>" options:NSRegularExpressionCaseInsensitive error:nil];
	NSRegularExpression *cellRx = [NSRegularExpression regularExpressionWithPattern:@"<td[^>]*>(.*?)(</td>|<td)" options:NSRegularExpressionCaseInsensitive error:nil];
	NSRegularExpression *titleRx = [NSRegularExpression regularExpressionWithPattern:@"<b[^>]*>(.*?)</b>" options:NSRegularExpressionCaseInsensitive error:nil];
	NSRegularExpression *descriptionRx = [NSRegularExpression regularExpressionWithPattern:@"<br>(.*)" options:NSRegularExpressionCaseInsensitive error:nil];
	NSRegularExpression *urlRx = [NSRegularExpression regularExpressionWithPattern:@"<a href=\"([^\"]*)\">Download MPEG-PS" options:NSRegularExpressionCaseInsensitive error:nil];
	NSRegularExpression *idRx = [NSRegularExpression regularExpressionWithPattern:@"id=(\\d+)" options:NSRegularExpressionCaseInsensitive error:nil];
	NSArray *tables = [tableRx matchesInString:listingDataString options:NSMatchingWithoutAnchoringBounds range:NSMakeRange(0, listingDataString.length)];
	if (tables.count == 0) {
		[[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationRecordingsUpdated object:nil];
		loadingProgramListLabel.stringValue = @"Incorrect Media Key";
		return;
	}
	NSTextCheckingResult *table = [tables objectAtIndex:0];
	listingDataString = [listingDataString substringWithRange:[table rangeAtIndex:1]];
	NSArray *rows = [rowRx matchesInString:listingDataString options:NSMatchingWithoutAnchoringBounds range:NSMakeRange(0, listingDataString.length)];
	NSTextCheckingResult *cell;
	NSRange cellRange;
	int cellIndex = 0;
	NSString *title = @"", *description = @"", *downloadURL = @"", *idString = @"", *size = @"";
	NSRange rangeToCheck;
	for (NSTextCheckingResult *row in rows) {
		title = @"";
		description = @"";
		downloadURL = @"";
		idString = @"";
		size = @"";
		cellIndex = 0;
		rangeToCheck = [row rangeAtIndex:1];
		cell = [cellRx firstMatchInString:listingDataString options:NSMatchingWithoutAnchoringBounds range:rangeToCheck];
		while (cell && cell.range.location != NSNotFound) {
			NSString *cellString = [listingDataString substringWithRange:cell.range];
			NSString *cellStringEnd = [cellString substringFromIndex:(cellString.length - 3)];
			if ([cellStringEnd caseInsensitiveCompare:@"<td"] == NSOrderedSame) {
				cellRange = NSMakeRange(cell.range.location , cell.range.length - 3);
			} else {
				cellRange = cell.range;
			}
			if (cellIndex == 2) {
				//We've got the title
				NSString *fullTitle = [listingDataString substringWithRange:[cell rangeAtIndex:1]];
				NSTextCheckingResult *titleResult = [titleRx firstMatchInString:fullTitle options:NSMatchingWithoutAnchoringBounds range:NSMakeRange(0, fullTitle.length)];
				title = [[fullTitle substringWithRange:[titleResult rangeAtIndex:1]] stringByDecodingHTMLEntities];
				NSTextCheckingResult *descriptionResult = [descriptionRx firstMatchInString:fullTitle options:NSMatchingWithoutAnchoringBounds range:NSMakeRange(0, fullTitle.length)];
				description = [[fullTitle substringWithRange:[descriptionResult rangeAtIndex:1]] stringByDecodingHTMLEntities];
			} 
			if (cellIndex == 4) {
				//We've got the size 
				NSString *fullString = [listingDataString substringWithRange:[cell rangeAtIndex:1]];
				NSTextCheckingResult *sizeResult = [descriptionRx firstMatchInString:fullString options:NSMatchingWithoutAnchoringBounds range:NSMakeRange(0, fullString.length)];
				if (sizeResult.range.location != NSNotFound) {
					size = [[fullString substringWithRange:[sizeResult rangeAtIndex:1]] stringByDecodingHTMLEntities];
				}
			}
			if (cellIndex == 5) {
				//We've got the download Reference
				NSString *fullString = [listingDataString substringWithRange:[cell rangeAtIndex:1]];
				NSTextCheckingResult *urlResult = [urlRx firstMatchInString:fullString options:NSMatchingWithoutAnchoringBounds range:NSMakeRange(0, fullString.length)];
				if (urlResult.range.location != NSNotFound) {
					downloadURL = [[fullString substringWithRange:[urlResult rangeAtIndex:1]] stringByDecodingHTMLEntities];
					//Add login information
					if (downloadURL.length > 10) {
						downloadURL = [NSString stringWithFormat:@"%@tivo:%@@%@",[downloadURL substringToIndex:7],mediaKeyLabel.stringValue,[downloadURL substringFromIndex:7]];
					}
					NSTextCheckingResult *idResult = [idRx firstMatchInString:downloadURL options:NSMatchingWithoutAnchoringBounds range:NSMakeRange(0, downloadURL.length)];
					if(idResult.range.location != NSNotFound){
						idString = [downloadURL substringWithRange:[idResult rangeAtIndex:1]];
					}
				}
			}
			//find the next cell
			rangeToCheck = NSMakeRange(cellRange.location + cellRange.length, listingDataString.length - (cellRange.location + cellRange.length));
			cell = [cellRx firstMatchInString:listingDataString options:NSMatchingWithoutAnchoringBounds range:rangeToCheck];
			cellIndex++;
			
		}
		if (downloadURL.length) {
			[_recordings addObject:[NSDictionary dictionaryWithObjectsAndKeys:
									title,@"Title",
									description, @"Description",
									downloadURL, @"URL",
									idString, @"ID",
									size, @"Size",
									nil]];
		}
	}
//	NSLog(@"Avialable Recordings are %@",_recordings);
    [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationRecordingsUpdated object:nil];
	loadingProgramListLabel.stringValue	 = @"";
}

#pragma mark - Bonjour browser delegate methods

- (void)netServiceBrowser:(NSNetServiceBrowser *)netServiceBrowser didFindService:(NSNetService *)netService moreComing:(BOOL)moreServicesComing
{
//	NSLog(@"Found Service %@",netService);
    [_tivoServices addObject:netService];
    netService.delegate = self;
    [netService resolveWithTimeout:2.0];
	[_tivoNames addObject:netService.name];
}

#pragma mark - NetService delegate methods

- (void)netServiceDidResolveAddress:(NSNetService *)sender
{
//    NSLog(@"Found hostname %@ for Service %@",sender.hostName,sender.name);
	if (tivoList.numberOfItems == 0) {
		mediaKeyLabel.stringValue = @"";
		if ([mediaKeys objectForKey:sender.name]) {
			mediaKeyLabel.stringValue = [mediaKeys objectForKey:sender.name];
		}
	}
	[tivoList addItemWithTitle:sender.name];
    [[tivoList lastItem] setRepresentedObject:sender];
    if (_videoListNeedsFilling) {
        [self fetchVideoListFromHost];
        _videoListNeedsFilling = NO;
    }
	if ([[NSUserDefaults standardUserDefaults] stringForKey:kMTSelectedTivo]) {
		if([[[NSUserDefaults standardUserDefaults] stringForKey:kMTSelectedTivo] compare:sender.name] == NSOrderedSame) {
			[tivoList selectItem:[tivoList lastItem]];
			[self fetchVideoListFromHost];
			mediaKeyLabel.stringValue = @"";
			if ([mediaKeys objectForKey:[tivoList lastItem].title]) {
				mediaKeyLabel.stringValue = [mediaKeys objectForKey:[tivoList lastItem].title];
			}
		}
	}
}

-(void)netService:(NSNetService *)sender didNotResolve:(NSDictionary *)errorDict
{
    NSLog(@"Service %@ failed to resolve",sender.name);
}

#pragma mark - NSURL Delegate Methods

-(void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data
{
	if (connection == programListURLConnection) {
		[listingData appendData:data];
//        NSLog(@"Current listing data = %@",[[[NSString alloc] initWithData:listingData encoding:NSUTF8StringEncoding] autorelease]);
	}
	if (connection == downloadURLConnection) {
		[downloadFile writeData:data];
//        NSLog(@"Data Downloaded = %lf",dataDownloaded);
		dataDownloaded += data.length;
		[self setProgressIndicatorForProgram:programDownloading withValue:dataDownloaded/referenceFileSize];
		[programDownloading setObject:[NSNumber numberWithBool:YES] forKey:kMTIsDownloading];
	
	}
}

- (BOOL)connection:(NSURLConnection *)connection canAuthenticateAgainstProtectionSpace:(NSURLProtectionSpace *)protectionSpace {
    return [protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust];
}

- (void)connection:(NSURLConnection *)connection didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge {
//    [challenge.sender useCredential:[NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust] forAuthenticationChallenge:challenge];
    [challenge.sender useCredential:[NSURLCredential credentialWithUser:@"tivo" password:mediaKeyLabel.stringValue persistence:NSURLCredentialPersistencePermanent] forAuthenticationChallenge:challenge];
    [challenge.sender continueWithoutCredentialForAuthenticationChallenge:challenge];
}

-(void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error
{
    NSLog(@"URL Connection Failed with error %@",error);
}


-(void)connectionDidFinishLoading:(NSURLConnection *)connection
{
//    NSLog(@"Received data from tivo %@",[[[NSString alloc] initWithData:listingData encoding:NSUTF8StringEncoding] autorelease]);
	if (connection == programListURLConnection) {
		[self parseListingData];
		[loadingProgramListIndicator stopAnimation:nil];
		[programListURLConnection release];
		programListURLConnection = nil;
		tivoConnectingTo = nil;
        NSLog(@"Finished program list URL");
	}
	if (connection == downloadURLConnection) {
		[downloadFile closeFile];
		[downloadFile release];
        downloadFile = nil;
		[downloadURLConnection release];
		downloadURLConnection = nil;
//		downloadingLabel.stringValue = [NSString stringWithFormat:@"Downloaded %@",[programDownloading objectForKey:@"Title"]];
//		[programDownloading setObject:[NSNumber numberWithBool:YES] forKey:kMTIsDownloaded];
//        [programDownloading setObject:@"Downloaded" forKey:kMTDownloadStatus];
        [self setProgressStatus:programDownloading withValue:@"Downloaded"];
        [programDownloading setObject:[NSNumber numberWithInt:kMTStatusDownloaded] forKey:kMTStatus];
		[self setProgressIndicatorForProgram:programDownloading withValue:1.0];
		programDownloading = nil;
		[[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationDownloadDidFinish object:nil];
		[self performSelector:@selector(manageDownloads) withObject:nil afterDelay:3.0];  // See if there are any more downloads to perform but wait some time for the tivo to recover and fully close the previous download
	}
}

#pragma mark - Text Editing Delegate

-(BOOL)control:(NSControl *)control textShouldEndEditing:(NSText *)fieldEditor
{
	NSString *tivoName = [tivoList selectedItem].title;
	[mediaKeys setObject:control.stringValue forKey:tivoName];
	[[NSUserDefaults standardUserDefaults] setObject:mediaKeys forKey:kMTMediaKeys];
	[self fetchVideoListFromHost];
	return YES;
}


@end
