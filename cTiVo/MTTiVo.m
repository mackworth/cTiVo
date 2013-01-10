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
	}
	return self;
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
	self.lastUpdated = [NSDate date];  // Record when we updated
	[self performSelector:@selector(updateShows:) withObject:nil afterDelay:(kMTUpdateIntervalMinutes * 60.0) + 1.0];
//	NSLog(@"Avialable Recordings are %@",_recordings);
	[[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationTiVoShowsUpdated object:nil];
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
