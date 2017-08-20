//
//  MTTiVo.m
//  cTiVo
//
//  Created by Scott Buchanan on 1/5/13.
//  Copyright (c) 2013 Scott Buchanan. All rights reserved.
//

#import "MTTiVo.h"
#import "MTTivoRPC.h"
#import "MTTiVoShow.h"
#import "MTDownload.h"
#import "NSString+HTML.h"
#import "MTTiVoManager.h"
#import "NSNotificationCenter+Threads.h"

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
{
    BOOL volatile isConnecting, managingDownloads, firstUpdate, canPing;
    NSURLConnection *showURLConnection;
    NSMutableData *urlData;
    NSMutableArray *newShows;
    SCNetworkReachabilityContext reachabilityContext;
    int totalItemsOnTivo;
    int lastChangeDate;
    int itemStart;
    int itemCount;
    int numAddedThisBatch; //should be itemCount minus duplicates
    int authenticationTries;
    BOOL parsingShow, gettingContent, gettingDetails, gettingIcon;
    NSMutableString *element;
    MTTiVoShow *currentShow;
    NSDictionary *elementToPropertyMap;
    NSMutableDictionary *previousShowList;

}

@property (nonatomic, strong) NSDate *networkAvailability;
@property (nonatomic, strong) NSOperationQueue *opsQueue;
@property (nonatomic, strong) NSURLConnection *showURLConnection;
@property BOOL isResponding;
@property (nonatomic, strong) 	NSDate *currentNPLStarted;

@property SCNetworkReachabilityRef reachability;
@property (nonatomic, readonly) NSArray *downloadQueue;
@property (nonatomic, strong) MTTivoRPC * myRPC;

@end

@implementation MTTiVo

@synthesize showURLConnection;

__DDLOGHERE__

+(MTTiVo *)tiVoWithTiVo:(MTNetService *)tiVo withOperationQueue:(NSOperationQueue *)queue
{
    return [MTTiVo tiVoWithTiVo:tiVo withOperationQueue:queue manual:NO  withID:0];
}

+(MTTiVo *)tiVoWithTiVo:(MTNetService *)tiVo withOperationQueue:(NSOperationQueue *)queue manual:(BOOL)isManual withID:(int)manualTiVoID
    {
	return [[MTTiVo alloc] initWithTivo:tiVo withOperationQueue:(NSOperationQueue *)queue manual:isManual withID:(int)manualTiVoID];
}

+(MTTiVo *)manualTiVoWithDescription:(NSDictionary *)description withOperationQueue:(NSOperationQueue *)queue
{
    if (!description[kMTTiVoUserPort] ||
        !description[kMTTiVoUserPortSSL] ||
        !description[kMTTiVoUserName] ||
        !description[kMTTiVoIPAddress]
        ) {
        return nil;
    }
    MTNetService *tiVo = [MTNetService new];
    tiVo.userPortSSL = (short)[description[kMTTiVoUserPortSSL] intValue];
    tiVo.userPort = (short)[description[kMTTiVoUserPort] intValue];
    tiVo.userName = description[kMTTiVoUserName];
    tiVo.iPAddress = description[kMTTiVoIPAddress];
    MTTiVo *thisTiVo = [MTTiVo tiVoWithTiVo:tiVo withOperationQueue:queue manual:YES withID:[description[kMTTiVoID] intValue]];
    if (!(description[kMTTiVoMediaKey])  && ![description[kMTTiVoMediaKey] isEqualTo:kMTTiVoNullKey]) {
        thisTiVo.mediaKey = description[kMTTiVoMediaKey];
    }
    thisTiVo.enabled = [description[kMTTiVoEnabled] boolValue];
    thisTiVo.manualTiVoID = [description[kMTTiVoID] intValue];
    return thisTiVo;
}
	
-(id)init
{
	self = [super init];
	if (self) {
		self.shows = [NSArray array];
		urlData = [NSMutableData new];
		newShows = [NSMutableArray new];
		_tiVo = nil;
		previousShowList = nil;
		showURLConnection = nil;
		_mediaKey = @"";
		isConnecting = NO;
		_mediaKeyIsGood = NO;
        managingDownloads = NO;
        _supportsTransportStream = YES;
        _manualTiVo = NO;
		firstUpdate = YES;
		_enabled = YES;
        _storeMediaKeyInKeychain = NO;
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
            @"TvRating" : @{kMTValue : @"tvRating", kMTType : [NSNumber numberWithInt:kMTNumberType]},
            @"MpaaRating" : @{kMTValue : @"mpaaRating", kMTType : [NSNumber numberWithInt:kMTNumberType]},
            @"SourceType" : @{kMTValue : @"sourceType", kMTType : [NSNumber numberWithInt:kMTStringType]},
            @"IdGuideSource" : @{kMTValue : @"idGuidSource", kMTType : [NSNumber numberWithInt:kMTStringType]}};
		elementToPropertyMap = [[NSDictionary alloc] initWithDictionary:elementToPropertyMap];
		_currentNPLStarted = nil;
		_lastDownloadEnded = [NSDate dateWithTimeIntervalSince1970:0];
		_manualTiVoID = -1;
	}
	return self;
	
}

-(id) initWithTivo:(MTNetService *)tiVo withOperationQueue:(NSOperationQueue *)queue manual:(BOOL)isManual withID:(int)manualTiVoID
{
	self = [self init];
	if (self) {
		self.tiVo = tiVo;
        self.manualTiVo = isManual;
        self.manualTiVoID = manualTiVoID;
		self.opsQueue = queue;
        DDLogMajor(@"testing reachability for tivo %@ with address %@",self.tiVo.name, self.tiVo.addresses[0]);
        if (isManual) {
            _reachability = SCNetworkReachabilityCreateWithName(kCFAllocatorDefault, [self.tiVo.iPAddress UTF8String]);
        } else {
            _reachability = SCNetworkReachabilityCreateWithAddress(NULL, [self.tiVo.addresses[0] bytes]);
        }
		self.networkAvailability = [NSDate date];
		BOOL didSchedule = NO;
		if (_reachability) {
			SCNetworkReachabilitySetCallback(_reachability, tivoNetworkCallback, &reachabilityContext);
			didSchedule = SCNetworkReachabilityScheduleWithRunLoop(_reachability, CFRunLoopGetMain(), kCFRunLoopDefaultMode);
		}
		_isReachable = didSchedule;
		if (!_isReachable) DDLogReport(@"Failed to schedule reachability for tivo %@", _tiVo.name);
		[self performSelectorOnMainThread:@selector(getMediaKey) withObject:nil waitUntilDone:YES];
		[self checkEnabled];
		[self setupNotifications];
	}
	return self;
}

void tivoNetworkCallback    (SCNetworkReachabilityRef target,
							 SCNetworkReachabilityFlags flags,
							 void *info)
{
    MTTiVo *thisTivo = (__bridge MTTiVo *)info;
    BOOL isReachable = ((flags & kSCNetworkFlagsReachable) != 0);
    BOOL needsConnection = ((flags & kSCNetworkFlagsConnectionRequired) != 0);

    thisTivo.isReachable = isReachable && !needsConnection ;
    if (thisTivo.isReachable) {
		thisTivo.networkAvailability = [NSDate date];
		[NSObject cancelPreviousPerformRequestsWithTarget:thisTivo selector:@selector(manageDownloads:) object:thisTivo];
		[thisTivo performSelector:@selector(manageDownloads:) withObject:thisTivo afterDelay:kMTTiVoAccessDelay+2];
        [thisTivo scheduleNextUpdateAfterDelay: kMTTiVoAccessDelay];
	} 
    [NSNotificationCenter postNotificationNameOnMainThread: kMTNotificationNetworkChanged object:nil];
    DDLogCReport(@"Tivo %@ is now %@", thisTivo.tiVo.name, thisTivo.isReachable ? @"online" : @"offline");
}

-(void)setupNotifications
{
	NSNotificationCenter *defaultCenter = [NSNotificationCenter defaultCenter];
	[defaultCenter addObserver:self selector:@selector(manageDownloads:) name:kMTNotificationDownloadQueueUpdated object:nil];
	[defaultCenter addObserver:self selector:@selector(manageDownloads:) name:kMTNotificationTransferDidFinish object:nil];
	[defaultCenter addObserver:self selector:@selector(manageDownloads:) name:kMTNotificationDecryptDidFinish object:nil];
	
}

-(void) saveLastLoadTime:(NSDate *) newDate{
	if (!newDate) return;
    if (!self.tiVo.name.length) return;
	NSDate * currentDate = tiVoManager.lastLoadedTivoTimes[self.tiVo.name];

	if (!currentDate || [newDate isGreaterThan: currentDate]) {
		tiVoManager.lastLoadedTivoTimes[self.tiVo.name] = newDate;
	}

}

-(NSString * ) description
{
    if (self.manualTiVo) {
        return [NSString stringWithFormat:@"%@ (%@:%hd/%hd)",
            self.tiVo.name,
            self.tiVo.iPAddress,
            self.tiVo.userPort,
            self.tiVo.userPortSSL
            ];
    } else {
		return self.tiVo.name;
    }
}

-(NSDictionary *)defaultsDictionary
{
    NSDictionary *retValue = nil;
    if (_manualTiVo) {
        retValue = @{kMTTiVoManualTiVo : @YES,
                     kMTTiVoUserName : self.tiVo.name,
                     kMTTiVoUserPort : [NSNumber numberWithInt:(int)self.tiVo.userPort],
                     kMTTiVoUserPortSSL : [NSNumber numberWithInt:(int)self.tiVo.userPortSSL],
                     kMTTiVoIPAddress : self.tiVo.iPAddress,
                     kMTTiVoEnabled : [NSNumber numberWithBool:self.enabled],
                     kMTTiVoID : [NSNumber numberWithInt:self.manualTiVoID],
                     kMTTiVoMediaKey : self.mediaKey
                     };
    } else {
        retValue = @{kMTTiVoManualTiVo : @NO,
                     kMTTiVoUserName : self.tiVo.name,
                     kMTTiVoEnabled : [NSNumber numberWithBool:self.enabled],
                     kMTTiVoMediaKey : self.mediaKey
                     };
    }
    return retValue;
}

-(void)checkEnabled
{
	DDLogVerbose(@"Checking Enabled for %@", self);
    NSArray *savedTiVos = tiVoManager.savedTiVos;
    if (savedTiVos.count == 0) {
        DDLogVerbose(@"No saved TiVos to check for enabled");
        return;
    }
    for (NSDictionary *tiVo in savedTiVos) {
        if ([tiVo[kMTTiVoUserName] isEqualTo:self.tiVo.name]) {
			self.enabled = [tiVo[kMTTiVoEnabled] boolValue];
			DDLogDetail(@"%@ is%@ Enabled", self,self.enabled ? @"": @" not");
			return;
		}
	}
	DDLogReport(@"Warning: didn't find %@ in %@", self, savedTiVos);
}

-(void)getMediaKey
{
	DDLogDetail(@"Getting media key for %@", self);
    BOOL foundMediaKey = NO;
    NSArray *savedTiVos = tiVoManager.savedTiVos;
    if (savedTiVos.count == 0) {
        DDLogDetail(@"No Media Key to Crib");
        return;
    }

    if (savedTiVos[0][kMTTiVoMediaKey] && ![savedTiVos[0][kMTTiVoMediaKey] isEqualToString:kMTTiVoNullKey]) self.mediaKey = savedTiVos[0][kMTTiVoMediaKey];
    
    for (NSDictionary *tiVo in savedTiVos) {
        if ([tiVo[kMTTiVoUserName] isEqual:self.tiVo.name] && ![tiVo[kMTTiVoMediaKey] isEqual:kMTTiVoNullKey] && [tiVo[kMTTiVoMediaKey] length] > 0) {
            self.mediaKey = tiVo[kMTTiVoMediaKey];
            foundMediaKey = YES;
        }
    }
    if (foundMediaKey) {
        self.myRPC = [[MTTivoRPC alloc] initServer:self.tiVo.hostName onPort:1413 andMAK:self.mediaKey];
    } else {
        //Need to update defaults
        [tiVoManager performSelectorOnMainThread:@selector(updateTiVoDefaults:) withObject:self waitUntilDone:YES];
    }
}

-(MTRPCData *) rpcDataForID: (NSString *) idString {
    return [self.myRPC rpcDataForID:idString];
}

-(void) scheduleNextUpdateAfterDelay:(NSInteger)delay {
    [MTTiVo cancelPreviousPerformRequestsWithTarget:self
                                           selector:@selector(updateShows:)
                                             object:nil ];
    NSInteger updateTime = [[NSUserDefaults standardUserDefaults] integerForKey:kMTUpdateIntervalMinutes] * 60.0;
    if (updateTime > 0) {
        if (delay < 0) delay = updateTime;
        DDLogDetail(@"Scheduling Update with delay of %lu seconds", (long)delay);
        [self performSelector:@selector(updateShows:) withObject:nil afterDelay:delay ];
    }
}

-(void)updateShows:(id)sender
{
	DDLogDetail(@"Updating Tivo %@", self);
	if (isConnecting || !self.enabled) {
        DDLogDetail(@"But was %@", isConnecting? @"Connecting": @"Disabled");
		return;
	}
	if (showURLConnection) {
		[showURLConnection cancel];
		self.showURLConnection = nil;
	}
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(updateShows:) object:nil];
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
	[NSNotificationCenter  postNotificationNameOnMainThread:kMTNotificationTiVoUpdating object:self];
	if (self.currentNPLStarted) {
		[self saveLastLoadTime:self.currentNPLStarted];
	}
	self.currentNPLStarted = [NSDate date];
	[self updateShowsStartingAt:0 withCount:kMTNumberShowToGetFirst];
}

-(NSInteger)isProcessing
{
    for (MTDownload *download in self.downloadQueue) {
        if (download.isInProgress && (download.downloadStatus.intValue != kMTStatusWaiting)) {
			return YES;
        }
    }
    return NO;
}

-(void)rescheduleAllShows
{
    for (MTDownload *download in self.downloadQueue) {
        if (download.isInProgress ) {
            [download prepareForDownload:NO];
        }
    }
}

-(void)updateShowsStartingAt:(int)anchor withCount:(int)count
{
    NSString *portString = @"";
    if ([_tiVo isKindOfClass:[MTNetService class]]) {
        portString = [NSString stringWithFormat:@":%d",_tiVo.userPortSSL];
    }

    NSString *tivoURLString = [[NSString stringWithFormat:@"https://%@%@/TiVoConnect?Command=QueryContainer&Container=%%2FNowPlaying&Recurse=Yes&AnchorOffset=%d&ItemCount=%d",_tiVo.hostName,portString,anchor,count] stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    if (previousShowList.count ==0 && anchor ==0) {
        //first time for this tivo:
        DDLogReport(@"Initial loading from TiVo %@ at URL %@",self, tivoURLString);
    } else {
        DDLogMajor(@"Loading from TiVo %@ shows from %d to %d at URL %@",self, anchor, anchor+count, tivoURLString);
    }
    NSURL *tivoURL = [NSURL URLWithString:tivoURLString];
    NSURLRequest *tivoURLRequest = [NSURLRequest requestWithURL:tivoURL];
    self.showURLConnection = [NSURLConnection connectionWithRequest:tivoURLRequest delegate:self];
    [urlData setData:[NSData data]];
    authenticationTries = 0;
    [showURLConnection start];
}

-(void)resetAllDetails
{
    for (MTTiVoShow *show in _shows) {
        show.gotTVDBDetails = NO;
        show.gotDetails = NO;
    }
    [self.myRPC emptyCaches];
}

#pragma mark - NSXMLParser Delegate Methods

-(void)parserDidStartDocument:(NSXMLParser *)parser
{
    parsingShow = NO;
    gettingContent = NO;
    gettingDetails = NO;
    numAddedThisBatch = 0;
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
        currentShow.tiVo = self;
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
            //Get name of Icon here
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
            parsingShow = NO;
            for (MTTiVoShow * oldShow in newShows) {
                if ([oldShow isEqualTo:currentShow]) {
                    DDLogDetail(@"Skipping duplicate new %@show %@ (%@) ",currentShow.isSuggestion ? @"suggested ":@"", currentShow.showTitle, currentShow.showDateString);
                    currentShow = nil;
                    return;
                }
            }
            numAddedThisBatch++;
            MTTiVoShow *thisShow = [previousShowList valueForKey:[NSString stringWithFormat:@"%d",currentShow.showID]];
            if (!thisShow) {
                DDLogDetail(@"Added new %@show %@ (%@) ",currentShow.isSuggestion ? @"suggested ":@"", currentShow.showTitle, currentShow.showDateString);
				[newShows addObject:currentShow];
				if (currentShow.inProgress.boolValue) {
					//can't use actual npl time, must use just before earliest in-progress so when it finishes, we'll pick it up next time
					NSDate * backUpToTime = [ currentShow.showDate dateByAddingTimeInterval:-1]; 
					if ([backUpToTime isLessThan:self.currentNPLStarted]) {
						self.currentNPLStarted = backUpToTime;  
					}
				}
				NSInvocationOperation *nextDetail = [[NSInvocationOperation alloc] initWithTarget:currentShow selector:@selector(getShowDetail) object:nil];
				[self.opsQueue addOperation:nextDetail];
				//Now check and see if this was in the oldQueue (from last time we ran)
				if(firstUpdate)[tiVoManager replaceProxyInQueue:currentShow];
				
			} else {
				DDLogDetail(@"Updated show %@", currentShow.showTitle);
				if (!thisShow.gotDetails || !thisShow.gotTVDBDetails) {
					NSInvocationOperation *nextDetail = [[NSInvocationOperation alloc] initWithTarget:thisShow selector:@selector(getShowDetail) object:nil];
					[self.opsQueue addOperation:nextDetail];

				}
				[newShows addObject:thisShow];
				[previousShowList removeObjectForKey:[NSString stringWithFormat:@"%d",currentShow.showID]];
			}
			currentShow = nil;
        }
    } else {
        if ([elementName compare:@"TotalItems"] == NSOrderedSame) {
            totalItemsOnTivo = [element intValue];
			DDLogDetail(@"TotalItems: %d",totalItemsOnTivo);
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
        NSRange portRange = [portMatch rangeAtIndex:1];
		NSString *portString = [elementToUpdate substringWithRange:portRange];
        short port = -1;

		if ([portString compare:@"443"] == NSOrderedSame) {
            port = self.tiVo.userPortSSL;
        } else if ([portString compare:@"80"] == NSOrderedSame) {
            port = self.tiVo.userPort;
		}
        if ( port > 0 ) {
            NSString * portReplaceString = [NSString stringWithFormat:@"%d", port];
            DDLogVerbose(@"Replacing port %@ with %@",portString, portReplaceString);
            [elementToUpdate replaceCharactersInRange:portRange withString:portReplaceString] ;
        }
	}
}

-(void)parserDidEndDocument:(NSXMLParser *)parser
{
	//Check if we're done yet
    int numDuplicates =itemCount-numAddedThisBatch;
    if (itemCount == 0) {
        DDLogReport(@"TiVo returned ZERO requested shows! Ignoring shows from %d to %d", itemStart, totalItemsOnTivo);
    } else if (numDuplicates == 0) {
        DDLogMajor(@"Finished batch for %@. Added %d shows.", self, numAddedThisBatch);
    } else if (numAddedThisBatch == 0) {  //Streaming Movies reported as shows bug
        DDLogMajor(@"Finished batch for %@. Only duplicated shows.", self);
    } else {
        DDLogMajor(@"Finished batch for %@. Added %d shows, but %d duplicate%@.", self, numAddedThisBatch, numDuplicates, numDuplicates == 1 ? @"": @"s" );
    }

    if (itemCount > 0 && itemStart+itemCount < totalItemsOnTivo) { // && numAddedThisBatch > 0) {
 		if (newShows.count > _shows.count) {
			self.shows = [NSArray arrayWithArray:newShows];
		}
		[self updateShowsStartingAt:itemStart + itemCount withCount:kMTNumberShowToGet];
	} else {
 		DDLogMajor(@"TiVo %@ completed parsing", self);
		isConnecting = NO;
		self.shows = [NSArray arrayWithArray:newShows];
		if (firstUpdate) {
			[tiVoManager checkDownloadQueueForDeletedEntries:self];
			firstUpdate = NO;
		}
		[NSNotificationCenter postNotificationNameOnMainThread:kMTNotificationTiVoUpdated object:self];
        [self scheduleNextUpdateAfterDelay:-1];
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
        //allows reporting when all other ops completed
        NSInvocationOperation *nextDetail = [[NSInvocationOperation alloc] initWithTarget:self selector:@selector(detailsComplete) object:nil];
        [self.opsQueue addOperation:nextDetail];

	}
    [NSNotificationCenter postNotificationNameOnMainThread:kMTNotificationTiVoShowsUpdated object:nil];
	[NSNotificationCenter postNotificationNameOnMainThread:kMTNotificationDownloadQueueUpdated object:self];

}

- (void)parser:(NSXMLParser *)parser parseErrorOccurred:(NSError *)parseError {
    DDLogReport(@"TiVo %@ had parsing error: %@", self, parseError.localizedDescription);
    isConnecting = NO;

    [self scheduleNextUpdateAfterDelay:-1];
    previousShowList = nil;

}


-(void) detailsComplete {
    //called when each show completes its details
    //DDLogReport (@"Ops Count = %lu; shows = %lu; connection: %@; queue = %@", (unsigned long)self.opsQueue.operationCount, self.shows.count, self.showURLConnection, self.opsQueue);

    if (self.opsQueue.operationCount <= 1 && !tiVoManager.tvdb.isActive && !isConnecting) {
        DDLogMajor(@"Got all details for %@",self.tiVo.name);
        DDLogDetail(@"Statistics for TVDB since start or reset: %@",[tiVoManager.tvdb stats]);

        //        for testing the movidedB
        //        for (MTTiVoShow * show in [self.shows copy]) {
        //            if (show.isMovie) {
        //                [show retrieveTheMovieDBArtworkIntoPath: [tiVoManager.tmpFilesDirectory stringByAppendingPathComponent:show.seriesTitle]];
        //                usleep(50000);
        //            }
        //        }
    }
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
	if ([tiVoManager checkForExit]) return;
	if (tiVoManager.processingPaused.boolValue) return;

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
        if (s.isDownloading) {
            isDownloading = YES;
            break;
        }
    }
    if (!isDownloading) {
		DDLogDetail(@"%@ Checking for new download", self);
		for (MTDownload *s in self.downloadQueue) {
			if ([s.show.protectedShow boolValue]) {
				managingDownloads = NO;
				return;
			}
            if (s.isNew && (tiVoManager.numEncoders < [[NSUserDefaults standardUserDefaults] integerForKey: kMTMaxNumEncoders])) {
                if(s.show.tiVo.isReachable) {  //isn't this self.isReachable?
					tiVoManager.numEncoders++;
					DDLogMajor(@"Num encoders after increment in MTTiVo %@ for show \"%@\"  is %d",self.tiVo.name,s.show.showTitle, tiVoManager.numEncoders);
					[s launchDownload];
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

-(void)notifyUserWithTitle:(NSString *) title subTitle: (NSString*) subTitle { // notification of Tivo problem
    [tiVoManager notifyForName: self.tiVo.name
              withTitle: title
               subTitle: subTitle
               isSticky: YES
        forNotification:kMTGrowlPossibleProblem
     ];
}

-(void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data
{
	DDLogVerbose(@"TiVo %@ sent data",self);
    if(self.manualTiVo) _isReachable = YES;
	[urlData appendData:data];
}

- (void)connection:(NSURLConnection *)connection willSendRequestForAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
{
	NSString *password = self.mediaKey;
	if (challenge.previousFailureCount == 0) {
		DDLogDetail(@"%@ password ask",self);
        if (challenge.proposedCredential) {
            DDLogDetail(@"Got mediaKey from keyChain");
            self.mediaKey = challenge.proposedCredential.password;
            [tiVoManager performSelectorOnMainThread:@selector(updateTiVoDefaults:) withObject:self waitUntilDone:NO];

            [challenge.sender useCredential:challenge.proposedCredential forAuthenticationChallenge:challenge];
        } else {
            DDLogDetail(@"sending mediaKey from userDefaults");
           NSURLCredentialPersistence persistance = NSURLCredentialPersistenceForSession;
            if (self.storeMediaKeyInKeychain) {
                persistance = NSURLCredentialPersistencePermanent;
            }
            NSURLCredential *myCredential = [NSURLCredential credentialWithUser:@"tivo" password:password persistence:persistance];
            [challenge.sender useCredential:myCredential forAuthenticationChallenge:challenge];
        }
	} else {
		DDLogReport(@"%@ challenge failed",self);
		[challenge.sender cancelAuthenticationChallenge:challenge];
		[showURLConnection cancel];
		self.showURLConnection = nil;
		isConnecting = NO;
		[NSNotificationCenter postNotificationNameOnMainThread:kMTNotificationMediaKeyNeeded object:@{@"tivo" : self, @"reason" : @"incorrect"}];
	}
}


-(void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error
{
    DDLogReport(@"TiVo URL Connection Failed with error %@",[error maskMediaKeys]);
    NSNumber * streamError = error.userInfo[@"_kCFStreamErrorCodeKey"];
    DDLogDetail(@"URL ErrorCode: %@, streamErrorCode: %@ (%@)", @(error.code), streamError, [streamError class]);
    if (error.code == -1004 && [streamError isKindOfClass:[NSNumber class]] && streamError.intValue == 49) {
        [self notifyUserWithTitle: @"Warning: Could not reach TiVo!"
                          subTitle:@"Antivirus program may be blocking connection"];
    }

    [NSNotificationCenter postNotificationNameOnMainThread: kMTNotificationTiVoUpdated object:self];
//    [self reportNetworkFailure];
    if(self.manualTiVo) _isReachable = NO;
    self.showURLConnection = nil;
    
    isConnecting = NO;
	
}


-(void)connectionDidFinishLoading:(NSURLConnection *)connection
{
	DDLogDetail(@"%@ URL Connection completed ",self);
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
