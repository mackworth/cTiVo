//
//  MTTiVo.m
//  cTiVo
//
//  Created by Scott Buchanan on 1/5/13.
//  Copyright (c) 2013 Scott Buchanan. All rights reserved.
//

#import "MTTiVo.h"
#import "MTTiVoShow.h"
#import "NSString+HTML.h"
#import "MTTiVoManager.h"

@interface MTTiVo ()
@property SCNetworkReachabilityRef reachability;
@property (nonatomic, assign) NSArray *downloadQueue;
@end

@implementation MTTiVo

+(MTTiVo *)tiVoWithTiVo:(NSNetService *)tiVo withOperationQueue:(NSOperationQueue *)queue
{
	return [[[MTTiVo alloc] initWithTivo:tiVo withOperationQueue:(NSOperationQueue *)queue] autorelease];
}
	
-(id)init
{
	self = [super init];
	if (self) {
		self.shows = [NSMutableArray array];
		urlData = [NSMutableData new];
		_tiVo = nil;
		self.lastUpdated = [NSDate dateWithTimeIntervalSinceReferenceDate:0];
		_mediaKey = @"";
		isConnecting = NO;
		_mediaKeyIsGood = NO;
        managingDownloads = NO;
        reachabilityContext.version = 0;
        reachabilityContext.info = self;
        reachabilityContext.retain = NULL;
        reachabilityContext.release = NULL;
        reachabilityContext.copyDescription = NULL;
	}
	return self;
	
}

-(id) initWithTivo:(NSNetService *)tiVo withOperationQueue:(NSOperationQueue *)queue
{
	self = [self init];
	if (self) {
		self.tiVo = tiVo;
		self.queue = queue;
        _reachability = SCNetworkReachabilityCreateWithAddress(NULL, [tiVo.addresses[0] bytes]);
		self.networkAvailability = [NSDate date];
        SCNetworkReachabilitySetCallback(_reachability, tivoNetworkCallback, &reachabilityContext);
		BOOL didSchedule = SCNetworkReachabilityScheduleWithRunLoop(_reachability, CFRunLoopGetMain(), kCFRunLoopDefaultMode);
		_isReachable = YES;
		NSLog(@"%@ reachability for tivo %@",didSchedule ? @"Scheduled" : @"Failed to schedule", _tiVo.name);
		[self getMediaKey];
		if (_mediaKey.length == 0) {
			[[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationMediaKeyNeeded object:self];
		} else {
			[self updateShows:nil];
		}
        NSNotificationCenter *defaultCenter = [NSNotificationCenter defaultCenter];
        [defaultCenter addObserver:self selector:@selector(manageDownloads:) name:kMTNotificationDownloadQueueUpdated object:nil];
        [defaultCenter addObserver:self selector:@selector(manageDownloads:) name:kMTNotificationDownloadDidFinish object:nil];
        [defaultCenter addObserver:self selector:@selector(manageDownloads:) name:kMTNotificationDecryptDidFinish object:nil];
	}
	return self;
}

void tivoNetworkCallback    (SCNetworkReachabilityRef target,
							 SCNetworkReachabilityFlags flags,
							 void *info)
{
    MTTiVo *thisTivo = (MTTiVo *)info;
	thisTivo.isReachable = (flags >>17) && 1 ;
	if (thisTivo.isReachable) {
		thisTivo.networkAvailability = [NSDate date];
		[NSObject cancelPreviousPerformRequestsWithTarget:[MTTiVoManager sharedTiVoManager] selector:@selector(manageDownloads) object:nil];
        NSLog(@"calling managedownloads from MTTiVo:tivoNetworkCallback with delay+2");
		[[MTTiVoManager sharedTiVoManager] performSelector:@selector(manageDownloads) withObject:nil afterDelay:kMTTiVoAccessDelay+2];
		[thisTivo performSelector:@selector(updateShows:) withObject:nil afterDelay:kMTTiVoAccessDelay];
	} 
    [[NSNotificationCenter defaultCenter] postNotificationName: kMTNotificationNetworkChanged object:nil];
	NSLog(@"Tivo %@ is now %@", thisTivo.tiVo.name, thisTivo.isReachable ? @"online" : @"offline");
}

-(NSString * ) description {
    return self.tiVo.name;
}

//-(void) reportNetworkFailure {
//    [[NSNotificationCenter defaultCenter] postNotificationName: kMTNotificationNetworkNotAvailable object:self];
////    [self performSelector:@selector(updateShows:) withObject:nil afterDelay:kMTRetryNetworkInterval];
//}

//-(BOOL) isReachable {
//    uint32_t    networkReachabilityFlags;
//    SCNetworkReachabilityGetFlags(self.reachability , &networkReachabilityFlags);
//    BOOL result = (networkReachabilityFlags >>17) && 1 ;  //if the 17th bit is set we are reachable.
//    return result;
//}
//
-(void)getMediaKey
{
	NSString *mediaKeyString = @"";
    NSMutableDictionary *mediaKeys = [NSMutableDictionary dictionary];
    if ([[NSUserDefaults standardUserDefaults] dictionaryForKey:kMTMediaKeys]) {
        mediaKeys = [NSMutableDictionary dictionaryWithDictionary:[[NSUserDefaults standardUserDefaults] dictionaryForKey:kMTMediaKeys]];
    }
    if ([mediaKeys objectForKey:_tiVo.name]) {
        mediaKeyString = [mediaKeys objectForKey:_tiVo.name];
    }else {
        NSArray *keys = [mediaKeys allKeys];
        if (keys.count) {
            mediaKeyString = [mediaKeys objectForKey:[keys objectAtIndex:0]];
            [mediaKeys setObject:mediaKeyString forKey:_tiVo.name];
            [[NSUserDefaults standardUserDefaults] setObject:mediaKeys  forKey:kMTMediaKeys];
        }
    }
    self.mediaKey = mediaKeyString;
}

-(void)updateShows:(id)sender
{
	if (isConnecting) {
		return;
	}
//	if (!sender && [[NSDate date] compare:[_lastUpdated dateByAddingTimeInterval:kMTUpdateIntervalMinutes * 60]] == NSOrderedAscending) {
//		return;
//	}
	if (showURLConnection) {
		[showURLConnection cancel];
		[showURLConnection release];
		showURLConnection = nil;
	}
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(updateShows:) object:nil];
//	if (![self isReachable]){
//        [self reportNetworkFailure];
//        return;
//    }
    isConnecting = YES;

	[[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationShowListUpdating object:self];
	NSString *tivoURLString = [[NSString stringWithFormat:@"https://tivo:%@@%@/nowplaying/index.html?Recurse=Yes",_mediaKey,_tiVo.hostName] stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
//	NSLog(@"Tivo URL String %@",tivoURLString);
	NSURL *tivoURL = [NSURL URLWithString:tivoURLString];
	NSURLRequest *tivoURLRequest = [NSURLRequest requestWithURL:tivoURL];
	showURLConnection = [[NSURLConnection connectionWithRequest:tivoURLRequest delegate:self] retain];
	[urlData setData:[NSData data]];
	[showURLConnection start];
		
}

-(void)parseListingData
{
    NSMutableDictionary * previousShowList = [NSMutableDictionary dictionary];
	for (MTTiVoShow * show in _shows) {
		NSString * idString = [NSString stringWithFormat:@"%d",show.showID];
//		NSLog(@"prevID: %@ %@",idString,show.showTitle);
		[previousShowList setValue:show forKey:idString];
	}
    [_shows removeAllObjects];
	NSString *urlDataString = [[[NSString alloc] initWithData:urlData encoding:NSUTF8StringEncoding] autorelease];
	NSRegularExpression *tableRx = [NSRegularExpression regularExpressionWithPattern:@"<table[^>]*>(.*?)</table>" options:NSRegularExpressionCaseInsensitive error:nil];
	NSRegularExpression *rowRx = [NSRegularExpression regularExpressionWithPattern:@"<tr[^>]*>(.*?)</tr>" options:NSRegularExpressionCaseInsensitive error:nil];
	NSRegularExpression *cellRx = [NSRegularExpression regularExpressionWithPattern:@"<td[^>]*>(.*?)(</td>|<td)" options:NSRegularExpressionCaseInsensitive error:nil];
	NSRegularExpression *titleRx = [NSRegularExpression regularExpressionWithPattern:@"<b[^>]*>(.*?)</b>" options:NSRegularExpressionCaseInsensitive error:nil];
	NSRegularExpression *descriptionRx = [NSRegularExpression regularExpressionWithPattern:@"<br>(.*)" options:NSRegularExpressionCaseInsensitive error:nil];
	NSRegularExpression *dateRx = [NSRegularExpression regularExpressionWithPattern:@"(.*)<br>(.*)" options:NSRegularExpressionCaseInsensitive error:nil];
	NSRegularExpression *twoFieldRx = [NSRegularExpression regularExpressionWithPattern:@"(.*)<br>(.*)" options:NSRegularExpressionCaseInsensitive error:nil];
	NSRegularExpression *urlRx = [NSRegularExpression regularExpressionWithPattern:@"<a href=\"([^\"]*)\">Download MPEG-PS" options:NSRegularExpressionCaseInsensitive error:nil];
	NSRegularExpression *idRx = [NSRegularExpression regularExpressionWithPattern:@"id=(\\d+)" options:NSRegularExpressionCaseInsensitive error:nil];
	NSArray *tables = [tableRx matchesInString:urlDataString options:NSMatchingWithoutAnchoringBounds range:NSMakeRange(0, urlDataString.length)];
	if (tables.count == 0) {
		[[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationTiVoShowsUpdated object:self];
		_mediaKeyIsGood = NO;
		[[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationMediaKeyNeeded object:self];
		return;
	}
	_mediaKeyIsGood = YES;
	NSTextCheckingResult *table = [tables objectAtIndex:0];
	urlDataString = [urlDataString substringWithRange:[table rangeAtIndex:1]];
	NSArray *rows = [rowRx matchesInString:urlDataString options:NSMatchingWithoutAnchoringBounds range:NSMakeRange(0, urlDataString.length)];
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
		cell = [cellRx firstMatchInString:urlDataString options:NSMatchingWithoutAnchoringBounds range:rangeToCheck];
		while (cell && cell.range.location != NSNotFound && cellIndex < 6) {
			NSString *cellString = [urlDataString substringWithRange:cell.range];
			NSString *cellStringEnd = [cellString substringFromIndex:(cellString.length - 3)];
			if ([cellStringEnd caseInsensitiveCompare:@"<td"] == NSOrderedSame) {
				cellRange = NSMakeRange(cell.range.location , cell.range.length - 3);
			} else {
				cellRange = cell.range;
			}
			if (cellIndex == 2) {
				//We've got the title
				NSString *fullTitle = [urlDataString substringWithRange:[cell rangeAtIndex:1]];
				NSTextCheckingResult *titleResult = [titleRx firstMatchInString:fullTitle options:NSMatchingWithoutAnchoringBounds range:NSMakeRange(0, fullTitle.length)];
				title = [[fullTitle substringWithRange:[titleResult rangeAtIndex:1]] stringByDecodingHTMLEntities];
				NSTextCheckingResult *descriptionResult = [descriptionRx firstMatchInString:fullTitle options:NSMatchingWithoutAnchoringBounds range:NSMakeRange(0, fullTitle.length)];
				description = [[fullTitle substringWithRange:[descriptionResult rangeAtIndex:1]] stringByDecodingHTMLEntities];
			}
			if (cellIndex == 3) {
				//We've got the date
				NSString *fullString = [urlDataString substringWithRange:[cell rangeAtIndex:1]];
				NSTextCheckingResult *dateResult = [dateRx firstMatchInString:fullString options:NSMatchingWithoutAnchoringBounds range:NSMakeRange(0, fullString.length)];
				if (dateResult.range.location != NSNotFound) {
					NSString *day = [[fullString substringWithRange:[dateResult rangeAtIndex:1]] stringByDecodingHTMLEntities];
					NSString *date = [[fullString substringWithRange:[dateResult rangeAtIndex:2]] stringByDecodingHTMLEntities];
					showDateString = [NSString stringWithFormat:@"%@ %@",day, date];
				}
                
			}
			if (cellIndex == 4) {
				//We've got the length and size
				NSString *fullString = [urlDataString substringWithRange:[cell rangeAtIndex:1]];
				NSTextCheckingResult *sizeResult = [twoFieldRx firstMatchInString:fullString options:NSMatchingWithoutAnchoringBounds range:NSMakeRange(0, fullString.length)];
				if (sizeResult.range.location != NSNotFound) {
					showLength = [[fullString substringWithRange:[sizeResult rangeAtIndex:1]] stringByDecodingHTMLEntities];
					size = [[fullString substringWithRange:[sizeResult rangeAtIndex:2]] stringByDecodingHTMLEntities];
				}
				
			}
			if (cellIndex == 5) {
				//We've got the download Reference
				NSString *fullString = [urlDataString substringWithRange:[cell rangeAtIndex:1]];
				NSTextCheckingResult *urlResult = [urlRx firstMatchInString:fullString options:NSMatchingWithoutAnchoringBounds range:NSMakeRange(0, fullString.length)];
				if (urlResult.range.location != NSNotFound) {
					downloadURL = [[fullString substringWithRange:[urlResult rangeAtIndex:1]] stringByDecodingHTMLEntities];
					//Add login information
					if (downloadURL.length > 10) {
						downloadURL = [NSString stringWithFormat:@"%@tivo:%@@%@",[downloadURL substringToIndex:7],[[[NSUserDefaults standardUserDefaults] objectForKey:kMTMediaKeys] objectForKey:_tiVo.name ],[downloadURL substringFromIndex:7]];
					}
					NSTextCheckingResult *idResult = [idRx firstMatchInString:downloadURL options:NSMatchingWithoutAnchoringBounds range:NSMakeRange(0, downloadURL.length)];
					if(idResult.range.location != NSNotFound){
						idString = [downloadURL substringWithRange:[idResult rangeAtIndex:1]];
					}
				}
			}
			//find the next cell
			rangeToCheck = NSMakeRange(cellRange.location + cellRange.length, urlDataString.length - (cellRange.location + cellRange.length));
			cell = [cellRx firstMatchInString:urlDataString options:NSMatchingWithoutAnchoringBounds range:rangeToCheck];
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
                thisShow.tiVo = self;
				thisShow.mediaKey = _mediaKey;
                NSInvocationOperation *nextDetail = [[[NSInvocationOperation alloc] initWithTarget:thisShow selector:@selector(getShowDetail) object:nil] autorelease];
                [_queue addOperation:nextDetail];
				//			[thisShow getShowDetail];
			} else {
//              NSLog(@"cache hit: %@ thisShow: %@", idString, thisShow.showTitle);
			}
			[_shows addObject:thisShow];
		}
	}
	if ([self.lastUpdated compare:[NSDate dateWithTimeIntervalSinceReferenceDate:0]] == NSOrderedSame) {
		[self performSelector:@selector(findShowsToDownload) withObject:nil afterDelay:10];

	}	self.lastUpdated = [NSDate date];  // Record when we updated
	[self performSelector:@selector(updateShows:) withObject:nil afterDelay:(kMTUpdateIntervalMinutes * 60.0) + 1.0];
//	NSLog(@"Avialable Recordings are %@",_recordings);
	[[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationTiVoShowsUpdated object:nil];
}

#pragma mark - Download Management

-(NSArray *)downloadQueue
{
    return [tiVoManager downloadQueueForTiVo:self];
}

-(void)manageDownloads:(NSNotification *)notification
{
    NSLog(@"calling managedownloads from notification %@",notification.name);
    [self manageDownloads];
    
}

-(void)manageDownloads
{
    if (managingDownloads) {
        return;
    }
    managingDownloads = YES;
    //We are only going to have one each of Downloading, Encoding, and Decrypting.  So scan to see what currently happening
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(manageDownloads) object:nil];
    BOOL isDownloading = NO, isDecrypting = NO;
    for (MTTiVoShow *s in self.downloadQueue) {
        if ([s.downloadStatus intValue] == kMTStatusDownloading) {
            isDownloading = YES;
        }
        if ([s.downloadStatus intValue] == kMTStatusDecrypting) {
            isDecrypting = YES;
        }
    }
    if (!isDownloading) {
        for (MTTiVoShow *s in self.downloadQueue) {
            if ([s.downloadStatus intValue] == kMTStatusNew && (tiVoManager.numEncoders < kMTMaxNumDownloaders || !s.simultaneousEncode)) {
                if(s.tiVo.isReachable) {
                    if (s.simultaneousEncode) {
                        tiVoManager.numEncoders++;
                    }
					[s download];
                    //                } else {    //We'll try again in kMTRetryNetworkInterval seconds at a minimum;
                    //                    [s.tiVo reportNetworkFailure];
                    //                    NSLog(@"Could not reach %@ tivo will try later",s.tiVo.tiVo.name);
                    //                    [self performSelector:@selector(manageDownloads) withObject:nil afterDelay:kMTRetryNetworkInterval];
                }
                break;
            }
        }
    }
    if (!isDecrypting) {
        for (MTTiVoShow *s in self.downloadQueue) {
            if ([s.downloadStatus intValue] == kMTStatusDownloaded && !s.simultaneousEncode) {
                [s decrypt];
                break;
            }
        }
    }
    if (tiVoManager.numEncoders < kMTMaxNumDownloaders) {
        for (MTTiVoShow *s in self.downloadQueue) {
            if ([s.downloadStatus intValue] == kMTStatusDecrypted && tiVoManager.numEncoders < kMTMaxNumDownloaders) {
				tiVoManager.numEncoders++;
                [s encode];
            }
        }
    }
    managingDownloads = NO;
}


#define kMTQueueShow @"MTQueueShow"
//only used in next two methods, marks shows that have already been requeued
-(MTTiVoShow *) findNextShow:(NSInteger) index {
	for (NSInteger nextIndex = index+1; nextIndex  < tiVoManager.oldQueue.count; nextIndex++) {
		MTTiVoShow * nextShow = tiVoManager.oldQueue[nextIndex][kMTQueueShow];
		if (nextShow != nil) {
			return nextShow;
		}
	}
	return nil;
}

-(void) findShowsToDownload {
	for (NSInteger index = 0; index < tiVoManager.oldQueue.count; index++) {
		NSDictionary * queueEntry = tiVoManager.oldQueue[index];
		//So For each queueEntry, if we haven't found it before, and it's this TiVo
		if (queueEntry[kMTQueueShow] == nil && [self.tiVo.name compare: queueEntry [KMTQueueTivo]] == NSOrderedSame) {
			for (MTTiVoShow * show in self.shows) {
				//see if it's available in shows
				if ([show isSameAs: queueEntry]) {
					[show restoreDownloadData:queueEntry];
					MTTiVoShow * nextShow = [self findNextShow:index];
					[tiVoManager addProgramsToDownloadQueue: [NSArray arrayWithObject: show] beforeShow:nextShow];
					[queueEntry setValue: show forKey:kMTQueueShow];
				}
			}
		}
	}
	for (NSDictionary * queueEntry in tiVoManager.oldQueue) {
		if (queueEntry[kMTQueueShow]== nil) {
			NSLog(@"TiVo no longer has show: %@", queueEntry[kMTQueueTitle]);
		}
	}

}

#pragma mark - Helper Methods

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


#pragma mark - NSURL Delegate Methods

-(void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data
{
	[urlData appendData:data];
}

- (BOOL)connection:(NSURLConnection *)connection canAuthenticateAgainstProtectionSpace:(NSURLProtectionSpace *)protectionSpace {
    return [protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust];
}

- (void)connection:(NSURLConnection *)connection didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge {
//    [challenge.sender useCredential:[NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust] forAuthenticationChallenge:challenge];
    [challenge.sender useCredential:[NSURLCredential credentialWithUser:@"tivo" password:[[[NSUserDefaults standardUserDefaults] objectForKey:kMTMediaKeys] objectForKey:_tiVo.name] persistence:NSURLCredentialPersistencePermanent] forAuthenticationChallenge:challenge];
    [challenge.sender continueWithoutCredentialForAuthenticationChallenge:challenge];
}

-(void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error
{
    NSLog(@"URL Connection Failed with error %@",error);
    [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationShowListUpdated object:self];
//    [self reportNetworkFailure];
    
    isConnecting = NO;
	
}


-(void)connectionDidFinishLoading:(NSURLConnection *)connection
{
    isConnecting = NO;
    [self parseListingData];
    [showURLConnection release];
    showURLConnection = nil;
    [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationShowListUpdated object:self];
}

#pragma mark - Memory Management

-(void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
	SCNetworkReachabilityUnscheduleFromRunLoop(_reachability, CFRunLoopGetMain(), kCFRunLoopDefaultMode);
	self.networkAvailability = nil;
    CFRelease(_reachability);
    _reachability = nil;
	self.mediaKey = nil;
	[urlData release];
	self.shows = nil;
	self.lastUpdated = nil;
	self.tiVo = nil;
	[super dealloc];
}

@end
