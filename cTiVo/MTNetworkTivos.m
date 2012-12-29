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
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	tivoBrowser = [[NSNetServiceBrowser alloc] init];
	tivoBrowser.delegate = self;
	[tivoBrowser scheduleInRunLoop:[NSRunLoop mainRunLoop] forMode:NSDefaultRunLoopMode];
	[tivoBrowser searchForServicesOfType:@"_tivo-videos._tcp" inDomain:@"local"];
	_tivoServices = [[NSMutableArray alloc] init];
	_videoListNeedsFilling = YES;
	listingData = [[NSMutableData alloc] init];
	_tiVoShows = [[NSMutableArray alloc] init];
	_tiVoList = [[NSMutableArray alloc] init];
	NSString *formatListPath = [[NSBundle mainBundle] pathForResource:@"formats" ofType:@"plist"];
	NSDictionary *formats = [NSDictionary dictionaryWithContentsOfFile:formatListPath];
	_formatList = [[NSMutableArray arrayWithArray:[formats objectForKey:@"formats"] ] retain];
    
    //Make sure there's a selected format, espeically on first launch
    _selectedFormat = nil;
    if ([defaults objectForKey:kMTSelectedFormat]) {
        NSString *formatName = [defaults objectForKey:kMTSelectedFormat];
        for (NSDictionary *fl in _formatList) {
            if ([formatName compare:[fl objectForKey:@"name"]] == NSOrderedSame) {
                self.selectedFormat = fl;
            }
        }
    }
    //If no selected format make it the first.
    if (!_selectedFormat) {
        self.selectedFormat = [_formatList objectAtIndex:0];
        
    }
	if (![defaults objectForKey:kMTMediaKeys]) {
		[defaults setObject:[NSDictionary dictionary] forKey:kMTMediaKeys];
	}
	if (![defaults objectForKey:kMTDownloadDirectory]) {
		NSString *ddir = [NSString stringWithFormat:@"%@/Downloads/",NSHomeDirectory()];
		[defaults setValue:ddir forKey:kMTDownloadDirectory];
	}
	_downloadDirectory = [defaults objectForKey:kMTDownloadDirectory];
    [self setProgramLoadingString:@""];
	_downloadQueue = [NSMutableArray new];
	_subscribedShows = [NSMutableArray new];
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
	numEncoders = 0;
	queue = [[NSOperationQueue alloc] init];
	queue.maxConcurrentOperationCount = 1;
	   
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(manageDownloads) name:kMTNotificationDownloadQueueUpdated object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(manageDownloads) name:kMTNotificationDownloadDidFinish object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(manageDownloads) name:kMTNotificationDecryptDidFinish object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(encodeFinished) name:kMTNotificationEncodeDidFinish object:nil];
	

}

-(NSMutableArray *) subscribedShows {
	if (_subscribedShows ==  nil) {
		_subscribedShows = [NSMutableArray arrayWithArray:[[NSUserDefaults standardUserDefaults] valueForKey:kMTSubscriptionList]];
	}
	return _subscribedShows;
}


-(void)setSelectedFormat:(NSDictionary *)selectedFormat
{
    if (selectedFormat == _selectedFormat) {
        return;
    }
    [_selectedFormat release];
    _selectedFormat = [selectedFormat retain];
    [[NSUserDefaults standardUserDefaults] setObject:[_selectedFormat objectForKey:@"name"] forKey:kMTSelectedFormat];
}


#pragma mark - Support methods

-(void)addProgramToDownloadQueue:(MTTiVoShow *)program
{
	BOOL programFound = NO;
	for (MTTiVoShow *p in _downloadQueue) {
		if (p.showID == program.showID	) {
			programFound = YES;
		}
	}
	
	if (!programFound) {
        if (_selectedFormat  && _selectedTiVo) {
            program.encodeFormat = _selectedFormat;
            program.tiVo = _selectedTiVo;
            program.mediaKey = [[[NSUserDefaults standardUserDefaults] objectForKey:kMTMediaKeys] objectForKey:program.tiVo.name];
            program.downloadDirectory = _downloadDirectory;
            [_downloadQueue addObject:program];
        }
	}
}

#pragma mark - Download Management

-(void)manageDownloads
{
    //We are only going to have one each of Downloading, Encoding, and Decrypting.  So scan to see what currently happening
    BOOL isDownloading = NO, isDecrypting = NO;
    for (MTTiVoShow *s in _downloadQueue) {
        if (s.downloadStatus == kMTStatusDownloading) {
            isDownloading = YES;
        }
        if (s.downloadStatus == kMTStatusDecrypting) {
            isDecrypting = YES;
        }
    }
    if (!isDownloading) {
        for (MTTiVoShow *s in _downloadQueue) {
            if (s.downloadStatus == kMTStatusNew && (numEncoders < kMTMaxNumDownloaders || !s.simultaneousEncode)) {
				if (s.simultaneousEncode) {
					numEncoders++;
				}
				[s download];
                break;
            }
        }
    }
    if (!isDecrypting) {
        for (MTTiVoShow *s in _downloadQueue) {
            if (s.downloadStatus == kMTStatusDownloaded && !s.simultaneousEncode) {
                [s decrypt];
                break;
            }
        }
    }
    if (numEncoders < kMTMaxNumDownloaders) {
        for (MTTiVoShow *s in _downloadQueue) {
            if (s.downloadStatus == kMTStatusDecrypted && numEncoders < kMTMaxNumDownloaders) {
				numEncoders++;
                [s encode];
            }
        }
    }
}

-(void)encodeFinished
{
	numEncoders--;
    [self manageDownloads];
    NSLog(@"num decoders after decrement is %d",numEncoders);
}

#pragma mark - Memory Management

-(void)dealloc
{
    [_tiVoShows release];
	[_downloadQueue release];
	[_formatList release];
	[tivoBrowser release];
    [_tiVoList release];
	[_tivoServices release];
    [listingData release];
	[queue release];
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[super dealloc];
}

-(void)fetchVideoListFromHost:(NSNetService *)newTivo;
{
	if (tivoConnectingTo && tivoConnectingTo == _selectedTiVo) {
		return;
	}
	if (newTivo == nil) {
		newTivo = _selectedTiVo;
	}
	if (newTivo != _selectedTiVo ) {
		[_tiVoShows removeAllObjects];
		[[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationTiVoShowsUpdated object:nil];
	}
	self.selectedTiVo = newTivo;
	if (programListURLConnection) {
		[programListURLConnection cancel];
		[programListURLConnection release];
		programListURLConnection = nil;
	}
    [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationShowListUpdating object:nil];
	tivoConnectingTo = _selectedTiVo;
    [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationTiVoShowsUpdated object:nil];
	NSString *host = _selectedTiVo.hostName;
	NSString *mediaKeyString = @"";
	if ([[[NSUserDefaults standardUserDefaults] objectForKey:kMTMediaKeys] objectForKey:_selectedTiVo.name]) {
		mediaKeyString = [[[NSUserDefaults standardUserDefaults] objectForKey:kMTMediaKeys] objectForKey:_selectedTiVo.name];
	}

    NSString *tivoURLString = [[NSString stringWithFormat:@"https://tivo:%@@%@/nowplaying/index.html?Recurse=Yes",mediaKeyString,host] stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    NSURL *tivoURL = [NSURL URLWithString:tivoURLString];
    NSURLRequest *tivoURLRequest = [NSURLRequest requestWithURL:tivoURL];
    programListURLConnection = [[NSURLConnection connectionWithRequest:tivoURLRequest delegate:self] retain];
    [listingData setData:[NSData data]];
    if (_selectedTiVo.name) [self setProgramLoadingString:[NSString stringWithFormat:@"Loading Programs - %@",_selectedTiVo.name]];
    [programListURLConnection start];
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(fetchVideoListFromHost:) object:nil];  //Do this to make sure we're not left with any from previous TiVo's
	[self performSelector:@selector(fetchVideoListFromHost:) withObject:nil afterDelay:kMTUpdateIntervalMinutes * 60];
                      
}



-(long) parseTime: (NSString *) timeString {
	NSRegularExpression *timeRx = [NSRegularExpression regularExpressionWithPattern:@"([0-9]{1,3}):([0-9]{1,2}):([0-9]{1,2})" options:NSRegularExpressionCaseInsensitive error:nil];
	NSTextCheckingResult *timeResult = [timeRx firstMatchInString:timeString options:NSMatchingWithoutAnchoringBounds range:NSMakeRange(0, timeString.length)];
	if (timeResult) {
		NSInteger hr = [timeString substringWithRange:[timeResult rangeAtIndex:1]].integerValue ;
		NSInteger min = [timeString substringWithRange:[timeResult rangeAtIndex:2]].integerValue ;
		NSInteger sec = [timeString substringWithRange:[timeResult rangeAtIndex:3]].integerValue ;
		return hr*3600+min*60+sec;
	} else {
		return 0;
	}
}

-(void)parseListingData
{
    NSMutableDictionary * previousShowList = [[[NSMutableDictionary alloc] initWithCapacity:_tiVoShows.count] autorelease];
	for (MTTiVoShow * show in _tiVoShows) {
		NSString * idString = [NSString stringWithFormat:@"%d",show.showID];
        //		NSLog(@"prevID: %@ %@",idString,show.showTitle);
		[previousShowList setValue:show forKey:idString];
	}
    [_tiVoShows removeAllObjects];
	NSString *listingDataString = [[[NSString alloc] initWithData:listingData encoding:NSUTF8StringEncoding] autorelease];
	NSRegularExpression *tableRx = [NSRegularExpression regularExpressionWithPattern:@"<table[^>]*>(.*?)</table>" options:NSRegularExpressionCaseInsensitive error:nil];
	NSRegularExpression *rowRx = [NSRegularExpression regularExpressionWithPattern:@"<tr[^>]*>(.*?)</tr>" options:NSRegularExpressionCaseInsensitive error:nil];
	NSRegularExpression *cellRx = [NSRegularExpression regularExpressionWithPattern:@"<td[^>]*>(.*?)(</td>|<td)" options:NSRegularExpressionCaseInsensitive error:nil];
	NSRegularExpression *titleRx = [NSRegularExpression regularExpressionWithPattern:@"<b[^>]*>(.*?)</b>" options:NSRegularExpressionCaseInsensitive error:nil];
	NSRegularExpression *descriptionRx = [NSRegularExpression regularExpressionWithPattern:@"<br>(.*)" options:NSRegularExpressionCaseInsensitive error:nil];
	NSRegularExpression *dateRx = [NSRegularExpression regularExpressionWithPattern:@"(.*)<br>(.*)" options:NSRegularExpressionCaseInsensitive error:nil];
	NSRegularExpression *twoFieldRx = [NSRegularExpression regularExpressionWithPattern:@"(.*)<br>(.*)" options:NSRegularExpressionCaseInsensitive error:nil];
	NSRegularExpression *urlRx = [NSRegularExpression regularExpressionWithPattern:@"<a href=\"([^\"]*)\">Download MPEG-PS" options:NSRegularExpressionCaseInsensitive error:nil];
	NSRegularExpression *idRx = [NSRegularExpression regularExpressionWithPattern:@"id=(\\d+)" options:NSRegularExpressionCaseInsensitive error:nil];
	NSArray *tables = [tableRx matchesInString:listingDataString options:NSMatchingWithoutAnchoringBounds range:NSMakeRange(0, listingDataString.length)];
	if (tables.count == 0) {
		[[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationTiVoShowsUpdated object:nil];
//		loadingProgramListLabel.stringValue = @"Incorrect Media Key";
        [self setProgramLoadingString:@"Incorrect Media Key"];
		return;
	}
	NSTextCheckingResult *table = [tables objectAtIndex:0];
	listingDataString = [listingDataString substringWithRange:[table rangeAtIndex:1]];
	NSArray *rows = [rowRx matchesInString:listingDataString options:NSMatchingWithoutAnchoringBounds range:NSMakeRange(0, listingDataString.length)];
	NSTextCheckingResult *cell;
	NSRange cellRange;
	int cellIndex = 0;
	NSString	*title = @"",
				*description = @"",
				*downloadURL = @"",
				*idString = @"",
				*showLength = @"",
				*size = @"",
				*showDateString = @"";
	NSRange rangeToCheck;
	for (NSTextCheckingResult *row in rows) {
		title = @"";
		description = @"";
		downloadURL = @"";
		idString = @"";
		size = @"";
		showLength = @"";
        showDateString = @"";
		cellIndex = 0;
		rangeToCheck = [row rangeAtIndex:1];
		cell = [cellRx firstMatchInString:listingDataString options:NSMatchingWithoutAnchoringBounds range:rangeToCheck];
		while (cell && cell.range.location != NSNotFound && cellIndex < 6) {
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
			if (cellIndex == 3) {
				//We've got the date
				NSString *fullString = [listingDataString substringWithRange:[cell rangeAtIndex:1]];
				NSTextCheckingResult *dateResult = [dateRx firstMatchInString:fullString options:NSMatchingWithoutAnchoringBounds range:NSMakeRange(0, fullString.length)];
				if (dateResult.range.location != NSNotFound) {
					NSString *day = [[fullString substringWithRange:[dateResult rangeAtIndex:1]] stringByDecodingHTMLEntities];
					NSString *date = [[fullString substringWithRange:[dateResult rangeAtIndex:2]] stringByDecodingHTMLEntities];
					showDateString = [NSString stringWithFormat:@"%@ %@",day, date];
				}
                
			}
			if (cellIndex == 4) {
				//We've got the length and size
				NSString *fullString = [listingDataString substringWithRange:[cell rangeAtIndex:1]];
				NSTextCheckingResult *sizeResult = [twoFieldRx firstMatchInString:fullString options:NSMatchingWithoutAnchoringBounds range:NSMakeRange(0, fullString.length)];
				if (sizeResult.range.location != NSNotFound) {
					showLength = [[fullString substringWithRange:[sizeResult rangeAtIndex:1]] stringByDecodingHTMLEntities];
					size = [[fullString substringWithRange:[sizeResult rangeAtIndex:2]] stringByDecodingHTMLEntities];
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
						downloadURL = [NSString stringWithFormat:@"%@tivo:%@@%@",[downloadURL substringToIndex:7],[[[NSUserDefaults standardUserDefaults] objectForKey:kMTMediaKeys] objectForKey:_selectedTiVo.name ],[downloadURL substringFromIndex:7]];
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
            MTTiVoShow *thisShow = [previousShowList valueForKey:idString];
			if (!thisShow) {
				thisShow = [[[MTTiVoShow alloc] init] autorelease];
                thisShow.showTitle = title;
                thisShow.showDescription = description;
                thisShow.urlString = downloadURL;
                thisShow.showID = [idString intValue];
                thisShow.showDateString = showDateString;
                thisShow.showLength= ([self parseTime: showLength]+30)/60; //round up to nearest minute
                double sizeValue;
                if (size.length <= 3) {
                    sizeValue = 0;
                } else {
                    sizeValue = [[size substringToIndex:size.length-3] doubleValue];
                    NSString *modifier = [size substringFromIndex:size.length-2];
                    if ([modifier caseInsensitiveCompare:@"MB"] == NSOrderedSame) {
                        sizeValue *= 1000 * 1000;
                    } else {
                        sizeValue *= 1000 * 1000 * 1000;
                    }
                }
                thisShow.fileSize = sizeValue;
                thisShow.tiVo = _selectedTiVo;
                thisShow.myTableView = _tiVoShowTableView;
                NSInvocationOperation *nextDetail = [[[NSInvocationOperation alloc] initWithTarget:thisShow selector:@selector(getShowDetailWithNotification) object:nil] autorelease];
                [queue addOperation:nextDetail];
//			[thisShow getShowDetail];
			} else {
				//NSLog(@"cache hit: %@ thisShow: %@", idString, thisShow.showTitle);
			}
			[_tiVoShows addObject:thisShow];
		}
	}
//	NSLog(@"Avialable Recordings are %@",_recordings);
    [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationTiVoShowsUpdated object:nil];
    [self setProgramLoadingString:@""];
}

#pragma mark - Bonjour browser delegate methods

- (void)netServiceBrowser:(NSNetServiceBrowser *)netServiceBrowser didFindService:(NSNetService *)netService moreComing:(BOOL)moreServicesComing
{
//	NSLog(@"Found Service %@",netService);
    [_tivoServices addObject:netService];
    netService.delegate = self;
    [netService resolveWithTimeout:2.0];
}

#pragma mark - NetService delegate methods

- (void)netServiceDidResolveAddress:(NSNetService *)sender
{
    [_tiVoList addObject:sender];
    [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationTiVoListUpdated object:nil];
    
}

-(void)netService:(NSNetService *)sender didNotResolve:(NSDictionary *)errorDict
{
    NSLog(@"Service %@ failed to resolve",sender.name);
}


#pragma mark - NSURL Delegate Methods

-(void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data
{
		[listingData appendData:data];
}

- (BOOL)connection:(NSURLConnection *)connection canAuthenticateAgainstProtectionSpace:(NSURLProtectionSpace *)protectionSpace {
    return [protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust];
}

- (void)connection:(NSURLConnection *)connection didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge {
//    [challenge.sender useCredential:[NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust] forAuthenticationChallenge:challenge];
    [challenge.sender useCredential:[NSURLCredential credentialWithUser:@"tivo" password:[[[NSUserDefaults standardUserDefaults] objectForKey:kMTMediaKeys] objectForKey:_selectedTiVo.name] persistence:NSURLCredentialPersistencePermanent] forAuthenticationChallenge:challenge];
    [challenge.sender continueWithoutCredentialForAuthenticationChallenge:challenge];
}

-(void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error
{
    NSLog(@"URL Connection Failed with error %@",error);
    [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationShowListUpdated object:nil];
    if (!_selectedTiVo.name) {
		[self setProgramLoadingString:@"Tivo not found"];
	} else {
		[self setProgramLoadingString:[NSString stringWithFormat:@"Connection to %@ TiVo Failed",_selectedTiVo.name]];
    }
    tivoConnectingTo = nil;

}


-(void)connectionDidFinishLoading:(NSURLConnection *)connection
{
    [self parseListingData];
    [programListURLConnection release];
    programListURLConnection = nil;
    tivoConnectingTo = nil;
    [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationShowListUpdated object:nil];
}


@end
