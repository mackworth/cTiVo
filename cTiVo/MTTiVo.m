//
//  MTTiVo.m
//  cTiVo
//
//  Created by Scott Buchanan on 1/5/13.
//  Copyright (c) 2013 Scott Buchanan. All rights reserved.
//

#import "MTTiVo.h"
#import "MTTiVoShow.h"
#import "MTDownload.h"
#import "NSString+HTML.h"
#import "MTTiVoManager.h"
#include <sys/xattr.h>

#define kMTStringType 0
#define kMTBoolType 1
#define kMTNumberType 2
#define kMTDateType 3

#define kMTValue @"KeyValue"
#define kMTType @"KeyType"

//no more than 128 at a time
#define kMTNumberShowToGet 50
#define kMTNumberShowToGetFirst 15


@interface MTTiVo ()
@property SCNetworkReachabilityRef reachability;
@property (nonatomic, weak) NSArray *downloadQueue;
@end

@implementation MTTiVo

@synthesize showURLConnection;

__DDLOGHERE__

+(MTTiVo *)tiVoWithTiVo:(id)tiVo withOperationQueue:(NSOperationQueue *)queue
{
	return [[MTTiVo alloc] initWithTivo:tiVo withOperationQueue:(NSOperationQueue *)queue];
}
	
-(id)init
{
	self = [super init];
	if (self) {
		self.shows = [NSMutableArray array];
		urlData = [NSMutableData new];
		newShows = [NSMutableArray new];
		_tiVo = nil;
		previousShowList = nil;
		showURLConnection = nil;
		_mediaKey = @"";
		isConnecting = NO;
		_mediaKeyIsGood = NO;
        managingDownloads = NO;
        _manualTiVo = NO;
		firstUpdate = YES;
		_enabled = YES;
        itemStart = 0;
        itemCount = 50;
        reachabilityContext.version = 0;
        reachabilityContext.info = (__bridge void *)(self);
        reachabilityContext.retain = NULL;
        reachabilityContext.release = NULL;
        reachabilityContext.copyDescription = NULL;
        elementToPropertyMap = @{
            @"Title" : @{kMTValue : @"seriesTitle", kMTType : [NSNumber numberWithInt:kMTStringType]},
            @"EpisodeTitle" : @{kMTValue : @"episodeTitle", kMTType : [NSNumber numberWithInt:kMTStringType]},
            @"CopyProtected" : @{kMTValue : @"protectedShow", kMTType : [NSNumber numberWithInt:kMTBoolType]},
            @"InProgress" : @{kMTValue : @"inProgress", kMTType : [NSNumber numberWithInt:kMTBoolType]},
            @"SourceSize" : @{kMTValue : @"fileSize", kMTType : [NSNumber numberWithInt:kMTNumberType]},
            @"Duration" : @{kMTValue : @"showLengthString", kMTType : [NSNumber numberWithInt:kMTStringType]},
            @"CaptureDate" : @{kMTValue : @"showDate", kMTType : [NSNumber numberWithInt:kMTDateType]},
            @"Description" : @{kMTValue : @"showDescription", kMTType : [NSNumber numberWithInt:kMTStringType]},
            @"SourceChannel" : @{kMTValue : @"channelString", kMTType : [NSNumber numberWithInt:kMTStringType]},
            @"SourceStation" : @{kMTValue : @"stationCallsign", kMTType : [NSNumber numberWithInt:kMTStringType]},
            @"HighDefinition" : @{kMTValue : @"isHD", kMTType : [NSNumber numberWithInt:kMTBoolType]},
            @"ProgramId" : @{kMTValue : @"programId", kMTType : [NSNumber numberWithInt:kMTStringType]},
            @"SeriesId" : @{kMTValue : @"seriesId", kMTType : [NSNumber numberWithInt:kMTStringType]},
            @"TvRating" : @{kMTValue : @"tvRating", kMTType : [NSNumber numberWithInt:kMTStringType]},
            @"SourceType" : @{kMTValue : @"sourceType", kMTType : [NSNumber numberWithInt:kMTStringType]},
            @"IdGuideSource" : @{kMTValue : @"idGuidSource", kMTType : [NSNumber numberWithInt:kMTStringType]}};
		elementToPropertyMap = [[NSDictionary alloc] initWithDictionary:elementToPropertyMap];
	}
	return self;
	
}

-(id) initWithTivo:(id)tiVo withOperationQueue:(NSOperationQueue *)queue
{
	self = [self init];
	if (self) {
		DDLogDetail(@"Creating TiVo %@",tiVo);
		self.tiVo = tiVo;
		self.queue = queue;
        _reachability = SCNetworkReachabilityCreateWithAddress(NULL, [self.tiVo.addresses[0] bytes]);
		self.networkAvailability = [NSDate date];
		BOOL didSchedule = NO;
		if (_reachability) {
			SCNetworkReachabilitySetCallback(_reachability, tivoNetworkCallback, &reachabilityContext);
			didSchedule = SCNetworkReachabilityScheduleWithRunLoop(_reachability, CFRunLoopGetMain(), kCFRunLoopDefaultMode);
		}
		_isReachable = YES;
		DDLogMajor(@"%@ reachability for tivo %@",didSchedule ? @"Scheduled" : @"Failed to schedule", _tiVo.name);
		[self getMediaKey];
//		if (_mediaKey.length == 0) {
//			DDLogDetail(@"Failed to get MAK for %@",tiVo);
//			[[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationMediaKeyNeeded object:self];
//		} else {
		[self updateShows:nil];
//		}
		[self setupNotifications];
	}
	return self;
}

void tivoNetworkCallback    (SCNetworkReachabilityRef target,
							 SCNetworkReachabilityFlags flags,
							 void *info)
{
    MTTiVo *thisTivo = (__bridge MTTiVo *)info;
	thisTivo.isReachable = (flags >>17) && 1 ;
	if (thisTivo.isReachable) {
		thisTivo.networkAvailability = [NSDate date];
		[NSObject cancelPreviousPerformRequestsWithTarget:thisTivo selector:@selector(manageDownloads:) object:thisTivo];
//        NSLog(@"QQQcalling managedownloads from MTTiVo:tivoNetworkCallback with delay+2");
		[thisTivo performSelector:@selector(manageDownloads:) withObject:thisTivo afterDelay:kMTTiVoAccessDelay+2];
		[thisTivo performSelector:@selector(updateShows:) withObject:nil afterDelay:kMTTiVoAccessDelay];
	} 
    [[NSNotificationCenter defaultCenter] postNotificationName: kMTNotificationNetworkChanged object:nil];
	DDLogCReport(@"Tivo %@ is now %@", thisTivo.tiVo.name, thisTivo.isReachable ? @"online" : @"offline");
}

-(void)setupNotifications
{
	NSNotificationCenter *defaultCenter = [NSNotificationCenter defaultCenter];
	[defaultCenter addObserver:self selector:@selector(manageDownloads:) name:kMTNotificationDownloadQueueUpdated object:nil];
	[defaultCenter addObserver:self selector:@selector(manageDownloads:) name:kMTNotificationDownloadDidFinish object:nil];
	[defaultCenter addObserver:self selector:@selector(manageDownloads:) name:kMTNotificationDecryptDidFinish object:nil];
	
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
	DDLogDetail(@"Getting media key for %@", self);
	NSString *mediaKeyString = @"";
    NSMutableDictionary *mediaKeys = [NSMutableDictionary dictionary];
    if ([[NSUserDefaults standardUserDefaults] dictionaryForKey:kMTMediaKeys]) {
        DDLogVerbose(@"Got all media keys %@", self);
		mediaKeys = [NSMutableDictionary dictionaryWithDictionary:[[NSUserDefaults standardUserDefaults] dictionaryForKey:kMTMediaKeys]];
    }
    if ([mediaKeys objectForKey:_tiVo.name]) {
        mediaKeyString = [mediaKeys objectForKey:_tiVo.name];
		DDLogVerbose(@"Found media key for %@", self);
    }else {
        NSArray *keys = [mediaKeys allKeys];
        if (keys.count) {
			DDLogVerbose(@"Defaulting to first key for %@", self);
			mediaKeyString = [mediaKeys objectForKey:[keys objectAtIndex:0]];
            [mediaKeys setObject:mediaKeyString forKey:_tiVo.name];
            [[NSUserDefaults standardUserDefaults] setObject:mediaKeys  forKey:kMTMediaKeys];
        }
    }
    self.mediaKey = mediaKeyString;
}

-(void)updateShows:(id)sender
{
	if (_mediaKey.length == 0) {
		DDLogDetail(@"Failed to get MAK for %@",self);
		[[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationMediaKeyNeeded object:self];
		return;
	}
	DDLogMajor(@"Updating Tivo %@", self);
	if (isConnecting) {
		return;
	}
//	if (!sender && [[NSDate date] compare:[_lastUpdated dateByAddingTimeInterval:kMTUpdateIntervalMinutes * 60]] == NSOrderedAscending) {
//		return;
//	}
	if (showURLConnection) {
		[showURLConnection cancel];
		self.showURLConnection = nil;
	}
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(updateShows:) object:nil];
//	if (![self isReachable]){
//        [self reportNetworkFailure];
//        return;
//    }
    isConnecting = YES;
	if (previousShowList) {
		 previousShowList = nil;
	}
	previousShowList = [NSMutableDictionary dictionary];
	for (MTTiVoShow * show in _shows) {
		NSString * idString = [NSString stringWithFormat:@"%d",show.showID];
//		NSLog(@"prevID: %@ %@",idString,show.showTitle);
		if(!show.inProgress.boolValue){
			[previousShowList setValue:show forKey:idString];
		}
	}
    DDLogVerbose(@"Previous shows were: %@:",previousShowList);
	[newShows removeAllObjects];
//	[_shows removeAllObjects];
	[[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationShowListUpdating object:self];
	[self updateShowsStartingAt:0 withCount:kMTNumberShowToGetFirst];
}

-(NSInteger)isProcessing
{
    for (MTDownload *download in self.downloadQueue) {
        if (download.isInProgress) {
			return YES;
        }
    }
    return NO;
}

-(void)rescheduleAllShows
{
    for (MTDownload *download in self.downloadQueue) {
        if (download.isInProgress) {
            [download prepareForDownload:NO];
        }
    }

}

-(void)updateShowsStartingAt:(int)anchor withCount:(int)count
{
	DDLogDetail(@"Getting %@ shows from %d to %d",self, anchor, anchor+count);
	NSString *portString = @"";
	if ([_tiVo isKindOfClass:[MTNetService class]]) {
		DDLogDetail(@"On TiVo %@; port %d",self, _tiVo.userPortSSL);
		portString = [NSString stringWithFormat:@":%d",_tiVo.userPortSSL];
	}
	
	NSString *tivoURLString = [[NSString stringWithFormat:@"https://%@%@/TiVoConnect?Command=QueryContainer&Container=%%2FNowPlaying&Recurse=Yes&AnchorOffset=%d&ItemCount=%d",_tiVo.hostName,portString,anchor,count] stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
	DDLogDetail(@"Tivo %@ URL String %@",self, tivoURLString);
	NSURL *tivoURL = [NSURL URLWithString:tivoURLString];
	NSURLRequest *tivoURLRequest = [NSURLRequest requestWithURL:tivoURL];
	self.showURLConnection = [NSURLConnection connectionWithRequest:tivoURLRequest delegate:self];
	[urlData setData:[NSData data]];
	[showURLConnection start];
		
}

#pragma mark - NSXMLParser Delegate Methods

-(void)parserDidStartDocument:(NSXMLParser *)parser
{
    parsingShow = NO;
    gettingContent = NO;
    gettingDetails = NO;
}

-(void) startElement:(NSString *) elementName {
	//just gives a shorter method name for DDLog
	 DDLogVerbose(@"%@ Start: %@",self, elementName);
}

-(void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName attributes:(NSDictionary *)attributeDict
{
    if (LOG_VERBOSE) [self startElement:elementName];
	element = [NSMutableString string];
    if ([elementName compare:@"Item"] == NSOrderedSame) {
        parsingShow = YES;
        currentShow = [[MTTiVoShow alloc] init];
        gettingContent = NO;
        gettingDetails = NO;
        gettingIcon = NO;
    } else if ([elementName compare:@"Content"] == NSOrderedSame) {
        gettingContent = YES;
    } else if ([elementName compare:@"TiVoVideoDetails"] == NSOrderedSame) {
        gettingDetails = YES;
    } else if ([elementName compare:@"CustomIcon"] == NSOrderedSame) {
		gettingIcon = YES;
	}
}

-(void)parser:(NSXMLParser *)parser foundCharacters:(NSString *)string
{
    [element appendString:string];
}

-(void)parserElement:(NSString*) elementName {
	//just gives a shorter method name for DDLog
	DDLogVerbose(@"%@:  %@ --> %@",_tiVo.name,elementName,element);
}

-(void)parser:(NSXMLParser *)parser didEndElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName
{
	[self endElement:elementName];
}

-(void) endElement:(NSString *) elementName {
	//just gives a shorter method name for DDLog

	[self parserElement: elementName];
    if (parsingShow) {
        //extract show parameters here
//        [currentShow setValue:element forKey:elementToPropertyMap[elementName]];
		if ([elementName compare:@"TiVoVideoDetails"] == NSOrderedSame) {
			gettingDetails = NO;
		} else if ([elementName compare:@"Content"] == NSOrderedSame) {
			gettingContent = NO;
		} else if ([elementName compare:@"CustomIcon"] == NSOrderedSame) {
			gettingIcon = NO;
		} else if (gettingDetails) {
            //Get URL for details here
			if ([elementName caseInsensitiveCompare:@"Url"] == NSOrderedSame) {
				//If a manual tivo put in port information
				if (self.manualTiVo) {
					[self updatePortsInURLString:element];
				}
				[currentShow setValue:[NSURL URLWithString:element] forKey:@"detailURL"];
				DDLogVerbose(@"Detail URL is %@",currentShow.detailURL);
			}
        } else if (gettingContent) {
            //Get URL for Content here
			if ([elementName caseInsensitiveCompare:@"Url"] == NSOrderedSame) {
				NSRegularExpression *idRx = [NSRegularExpression regularExpressionWithPattern:@"id=(\\d+)" options:NSRegularExpressionCaseInsensitive error:nil];
				NSTextCheckingResult *idResult = [idRx firstMatchInString:element options:NSMatchingWithoutAnchoringBounds range:NSMakeRange(0, element.length)];
				if(idResult.range.location != NSNotFound){
					currentShow.showID = [[element substringWithRange:[idResult rangeAtIndex:1]] intValue];
				}
				if (self.manualTiVo) {
					[self updatePortsInURLString:element];
				}
				[currentShow setValue:[NSURL URLWithString:element] forKey:@"downloadURL"];
				DDLogVerbose(@"Content URL is %@",currentShow.downloadURL);
			}
        } else if (gettingIcon) {
            //Get URL for Content here
			if ([elementName caseInsensitiveCompare:@"Url"] == NSOrderedSame) {
				NSString *introURL = @"urn:tivo:image:";
				if ([element hasPrefix: introURL]){
					currentShow.imageString = [element substringFromIndex:introURL.length];
				} 
				DDLogVerbose(@"Image String is %@",currentShow.imageString);
			}
        } else if ([elementToPropertyMap objectForKey:elementName]){
//        [currentShow setValue:element forKey:elementToPropertyMap[elementName]];
			int type = [elementToPropertyMap[elementName][kMTType] intValue];
			id valueToSet = nil;
			NSString * keyToSet = elementToPropertyMap[elementName][kMTValue];
			switch (type) {
                case kMTStringType:
                    //Process String Type here
					valueToSet = element;
					break;
                    
                case kMTBoolType:
                    //Process Boolean Type here
					valueToSet = [NSNumber numberWithBool:[element boolValue]];
                    break;
                                        
                case kMTNumberType:
                    //Process Number Type here
 					valueToSet = [NSNumber numberWithDouble:[element doubleValue]];
                   break;
                    
			   case kMTDateType: {
                    //Process date type which are hex timestamps
				   double timestamp = 0;
					[[NSScanner scannerWithString:element] scanHexDouble:&timestamp];
//					timestamp = [element doubleValue];
					valueToSet = [NSDate dateWithTimeIntervalSince1970:timestamp];
                   break;
			   }
                default:
                    break;
            }
			if (valueToSet) [currentShow setValue:valueToSet forKey:keyToSet];
			DDLogVerbose(@"set %@ (type %d) to %@ for %@",keyToSet, type, valueToSet, elementName);

        } else if ([elementName compare:@"Item"] == NSOrderedSame) {
            MTTiVoShow *thisShow = [previousShowList valueForKey:[NSString stringWithFormat:@"%d",currentShow.showID]];
			if (!thisShow) {
				currentShow.tiVo = self;
				DDLogDetail(@"Added new show %@",currentShow.showTitle);
				[newShows addObject:currentShow];
				NSInvocationOperation *nextDetail = [[NSInvocationOperation alloc] initWithTarget:currentShow selector:@selector(getShowDetail) object:nil];
				[_queue addOperation:nextDetail];
				//Now check and see if this was in the oldQueue (from last time we ran)
				if(firstUpdate)[tiVoManager replaceProxyInQueue:currentShow];
				
			} else {
				DDLogDetail(@"Updated show %@", currentShow.showTitle);
				[newShows addObject:thisShow];
				[previousShowList removeObjectForKey:[NSString stringWithFormat:@"%d",currentShow.showID]];
			}
			currentShow = nil;
            parsingShow = NO;
        }
    } else {
        if ([elementName compare:@"TotalItems"] == NSOrderedSame) {
            totalItemsOnTivo = [element intValue];
			DDLogVerbose(@"TotalItems: %d",totalItemsOnTivo);
        } else if ([elementName compare:@"ItemStart"] == NSOrderedSame) {
            itemStart = [element intValue];
			DDLogVerbose(@"ItemStart: %d",itemStart);
        } else if ([elementName compare:@"ItemCount"] == NSOrderedSame) {
            itemCount = [element intValue];
			DDLogVerbose(@"ItemCount: %d",itemCount);
        } else if ([elementName compare:@"LastChangeDate"] == NSOrderedSame) {
            int newLastChangeDate = [element intValue];
            if (newLastChangeDate != lastChangeDate) {
				DDLogVerbose(@"Oops. Date changed under us: was: %d now: %d",lastChangeDate, newLastChangeDate);
                //Implement start over here
				//except that a show in progress updates this value
            }
            lastChangeDate = newLastChangeDate;
        } else {
			DDLogVerbose(@"Unrecognized element: %@-->%@",elementName,element);
			
		}
    }
}


-(void)updatePortsInURLString:(NSMutableString *)elementToUpdate
{
	NSRegularExpression *portRx = [NSRegularExpression regularExpressionWithPattern:@"\\:(\\d+)\\/" options:NSRegularExpressionCaseInsensitive error:nil];
	NSTextCheckingResult *portMatch = [portRx firstMatchInString:elementToUpdate options:0 range:NSMakeRange(0, elementToUpdate.length)];
	if (portMatch.numberOfRanges == 2) {
		NSString *portString = [elementToUpdate substringWithRange:[portMatch rangeAtIndex:1]];
		NSString *portReplaceString = portString;
		if ([portString compare:@"443"] == NSOrderedSame) {
			portReplaceString = [NSString stringWithFormat:@"%d",self.tiVo.userPortSSL];
		}
		if ([portString compare:@"80"] == NSOrderedSame) {
			portReplaceString = [NSString stringWithFormat:@"%d",self.tiVo.userPort];
		}
		DDLogVerbose(@"Replacing port %@ with %@",portString,portReplaceString);
		[elementToUpdate replaceOccurrencesOfString:portString withString:portReplaceString options:0 range:NSMakeRange(0, elementToUpdate.length)];
	}
}

-(void)parserDidEndDocument:(NSXMLParser *)parser
{
	//Check if we're done yet
	if (itemStart+itemCount < totalItemsOnTivo) {
		DDLogDetail(@"TiVo %@ finished batch", self);
		if (newShows.count > _shows.count) {
			self.shows = [NSMutableArray arrayWithArray:newShows];
		}
		[self updateShowsStartingAt:itemStart + itemCount withCount:kMTNumberShowToGet];
	} else {
		DDLogMajor(@"TiVo %@ completed parsing", self);
		isConnecting = NO;
		self.shows = [NSMutableArray arrayWithArray:newShows];
		if (firstUpdate) {
			[tiVoManager checkDownloadQueueForDeletedEntries:self];
			firstUpdate = NO;
		}
		[[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationShowListUpdated object:self];
		[self performSelector:@selector(updateShows:) withObject:nil afterDelay:(kMTUpdateIntervalMinutes * 60.0) + 1.0];
		DDLogVerbose(@"Deleted shows: %@",previousShowList);
		for (MTTiVoShow * show in [previousShowList objectEnumerator]){
			if (show.isQueued) {
				MTDownload * download = [tiVoManager findInDownloadQueue:show];
				if (download.isNew) {
					download.downloadStatus = [NSNumber numberWithInt:kMTStatusDeleted];
				}
				show.imageString = @"deleted";
			}
		}
		 previousShowList = nil;
	}
	[[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationTiVoShowsUpdated object:nil];
	[[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationDownloadQueueUpdated object:self];
     parser = nil;
}


#pragma mark - Download Management

-(NSArray *)downloadQueue
{
    return [tiVoManager downloadQueueForTiVo:self];
}

-(void)manageDownloads:(id)info
{
//    if ([tiVoManager.hasScheduledQueueStart boolValue]  && [tiVoManager.queueStartTime compare:[NSDate date]] == NSOrderedDescending) { //Don't start unless we're after the scheduled time if we're supposed to be scheduled.
//        DDLogMajor(@"%@ Delaying download until %@",self,tiVoManager.queueStartTime);
//		return;
//    }
	if ([tiVoManager.processingPaused boolValue] || [tiVoManager.quitWhenCurrentDownloadsComplete boolValue]) {
		return;
	}
	if ([info isKindOfClass:[NSNotification class]]) {
		NSNotification *notification = (NSNotification *)info;
		if (!notification.object || notification.object == self) {
			DDLogDetail(@"%@ got manageDownload notification %@",self, notification.name);
			[self manageDownloads];
		} else {
			DDLogDetail(@"%@ ignoring notification %@ for %@",self,notification.name, notification.object);
		}
	} else if ([info isKindOfClass:[self class]] && info == self ) {
			[self manageDownloads];
	} else {
		DDLogMajor(@"Unrecognized info to launch manageDownloads %@",info);
	}

}

-(void)manageDownloads
{
	DDLogMajor(@"Checking %@ queue", self);
	if (managingDownloads) {
        return;
    }
    managingDownloads = YES;
    //We are only going to have one each of Downloading, Encoding, and Decrypting.  So scan to see what currently happening
//	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(manageDownloads) object:nil];
    BOOL isDownloading = NO;
    for (MTDownload *s in self.downloadQueue) {
        if ([s.downloadStatus intValue] == kMTStatusDownloading) {
            isDownloading = YES;
        }
    }
    if (!isDownloading) {
		DDLogDetail(@"%@ Checking for new download", self);
		for (MTDownload *s in self.downloadQueue) {
			if ([s.show.protectedShow boolValue]) {
				managingDownloads = NO;
				return;
			}
            if (s.isNew && (tiVoManager.numEncoders < kMTMaxNumDownloaders)) {
                if(s.show.tiVo.isReachable) {  //isn't this self.isReachable?
//                    if (s.shouldSimulEncode) {
                        tiVoManager.numEncoders++;
                        DDLogMajor(@"Incrementing num decoders value in TiVo %@ for show %@ after is %d",self.tiVo.name,s.show.showTitle, tiVoManager.numEncoders);
//                    }
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
    managingDownloads = NO;
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
	DDLogVerbose(@"TiVo %@ sent data",self);
	[urlData appendData:data];
}

- (BOOL)connection:(NSURLConnection *)connection canAuthenticateAgainstProtectionSpace:(NSURLProtectionSpace *)protectionSpace {
//    return [protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust];
	return YES;  //Ignore self-signed certificate
}

- (void)connection:(NSURLConnection *)connection didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge {
	NSString *password = [[NSUserDefaults standardUserDefaults] objectForKey:kMTMediaKeys][_tiVo.name];
	if (challenge.previousFailureCount == 0) {
		DDLogDetail(@"%@ password ask",self);
		NSURLCredential *myCredential = [NSURLCredential credentialWithUser:@"tivo" password:password persistence:NSURLCredentialPersistenceForSession];
		[challenge.sender useCredential:myCredential forAuthenticationChallenge:challenge];
	} else {
		DDLogDetail(@"%@ challenge failed",self);
		[challenge.sender cancelAuthenticationChallenge:challenge];
		[showURLConnection cancel];
		self.showURLConnection = nil;
		isConnecting = NO;
		[[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationMediaKeyNeeded object:self];
	}
}

-(void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error
{
    DDLogReport(@"URL Connection Failed with error %@",error);
    [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationShowListUpdated object:self];
//    [self reportNetworkFailure];
    self.showURLConnection = nil;
    
    isConnecting = NO;
	
}


-(void)connectionDidFinishLoading:(NSURLConnection *)connection
{
	DDLogMajor(@"%@ URL Connection completed ",self);
    DDLogVerbose(@"Data received is %@",[[NSString alloc] initWithData:urlData encoding:NSUTF8StringEncoding]);

    NSXMLParser *parser = [[NSXMLParser alloc] initWithData:urlData];
	parser.delegate = self;
	[parser parse];
    self.showURLConnection = nil;
}

#pragma mark - Memory Management

-(void)dealloc
{
    DDLogDetail(@"Deallocing TiVo %@",self);
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	SCNetworkReachabilityUnscheduleFromRunLoop(_reachability, CFRunLoopGetMain(), kCFRunLoopDefaultMode);
	if (_reachability) {
		CFRelease(_reachability);
	}
    _reachability = nil;
}

@end
