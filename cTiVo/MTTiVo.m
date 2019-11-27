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
#import "NSArray+Map.h"

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
    BOOL volatile isConnecting, managingDownloads, firstUpdate, cancelRefresh;
    NSMutableData *urlData;
    NSMutableArray *newShows;
    SCNetworkReachabilityContext reachabilityContext;
    int totalItemsOnTivo;
    int lastChangeDate;
    int itemStart;
    int tivoBugDuplicatePossibleStart, tivoBugDuplicateCount;
    int itemCount;
    int numAddedThisBatch; //should be itemCount minus duplicates
    int authenticationTries;
    BOOL parsingShow, gettingContent, gettingDetails, gettingIcon;
    NSMutableString *element;
    MTTiVoShow *currentShow;
    NSDictionary *elementToPropertyMap;
    NSMutableDictionary *previousShowList;

}

@property (atomic, assign) BOOL oneBatch;
@property (nonatomic, strong) NSMutableArray<NSString *> * addedShows;
@property (nonatomic, strong) NSMutableArray<NSNumber *> * addedShowIndices;

@property (nonatomic, strong) NSDate *networkAvailability;
@property (nonatomic, strong) NSOperationQueue *opsQueue;
@property (nonatomic, strong) NSURLConnection *showURLConnection;
@property (nonatomic, strong) 	NSDate *currentNPLStarted;

@property (nonatomic, strong) NSMutableSet <MTTiVoShow *> * postponedCommercialShows;
@property SCNetworkReachabilityRef reachability;
@property (nonatomic, readonly) NSArray *downloadQueue;
@property (nonatomic, strong) MTTivoRPC * myRPC;
@property (atomic, strong) NSMutableDictionary <NSString *, MTTiVoShow *> * rpcIDs;

@end

@implementation MTTiVo
@synthesize enabled = _enabled;


__DDLOGHERE__

+(MTTiVo *)tiVoWithTiVo:(MTNetService *)tiVo
     withOperationQueue:(NSOperationQueue *)queue
       withSerialNumber:(NSString *)TSN {
    MTTiVo *thisTiVo = [[MTTiVo alloc] initWithTivo:tiVo withOperationQueue:(NSOperationQueue *)queue manual:NO withID:(int)0 withSerialNumber:TSN ];
    DDLogVerbose(@"Checking Enabled for %@", self);
    for (NSDictionary *description in tiVoManager.savedTiVos) {
		BOOL isManual = ((NSNumber *)description[kMTTiVoManualTiVo]).boolValue;
        if (! isManual && [description[kMTTiVoUserName] isEqual:thisTiVo.tiVo.name]) {
            thisTiVo.tiVoSerialNumber = description[kMTTiVoTSN];
			BOOL toEnable = [description[kMTTiVoEnabled] boolValue];
			NSString * possMediaKey = description[kMTTiVoMediaKey];
            if (possMediaKey.length == 0 || [possMediaKey isEqual:kMTTiVoNullKey]) {
				if (toEnable) {
					[NSNotificationCenter postNotificationNameOnMainThread:kMTNotificationMediaKeyNeeded object:@{@"tivo" : thisTiVo, @"reason" : @"new"}];
				}
			} else {
				thisTiVo.mediaKey = possMediaKey;
			}
			thisTiVo.enabled = toEnable;
            DDLogDetail(@"%@ is%@ Enabled", thisTiVo.tiVo.name,thisTiVo.enabled ? @"": @" not");
            return thisTiVo;
        }
    }
	[NSNotificationCenter postNotificationNameOnMainThread:kMTNotificationMediaKeyNeeded object:@{@"tivo" : thisTiVo, @"reason" : @"new"}];
	if (thisTiVo.mediaKey.length > 0) {
		thisTiVo.enabled = YES;
	}
    DDLogMajor(@"First time seeing %@ (previous: %@)",thisTiVo, [tiVoManager.savedTiVos maskMediaKeys]);
    return thisTiVo;
}

+(MTTiVo *)manualTiVoWithDescription:(NSDictionary *)description withOperationQueue:(NSOperationQueue *)queue {
    //recently added RPC, so shouldn't fail if it's missing, but default to 1413 instead.  Could check in future.
    if (![description[kMTTiVoUserPort]    intValue] ||
        ![description[kMTTiVoUserPortSSL] intValue] ||
        ![description[kMTTiVoUserName]    length] ||
        ![description[kMTTiVoIPAddress]   length]  ) {
        return nil;
    }

    MTNetService *tiVo = [[MTNetService alloc]  initWithName: description[kMTTiVoUserName]];
    tiVo.userPortSSL = (short)[description[kMTTiVoUserPortSSL] intValue];
    tiVo.userPortRPC = (short)[description[kMTTiVoUserPortRPC] ?: @1413 intValue];
    tiVo.userPort = (short)[description[kMTTiVoUserPort] intValue];
//    tiVo.userName = description[kMTTiVoUserName];
    tiVo.iPAddress = description[kMTTiVoIPAddress];
    MTTiVo *thisTiVo = [[MTTiVo alloc] initWithTivo:tiVo withOperationQueue:queue manual:YES withID:[description[kMTTiVoID] intValue] withSerialNumber:description[kMTTiVoTSN]];
    if ((description[kMTTiVoMediaKey])  && ![description[kMTTiVoMediaKey] isEqual:kMTTiVoNullKey]) {
        thisTiVo.mediaKey = description[kMTTiVoMediaKey];
    }
    if ([tiVoManager duplicateTiVoFor:thisTiVo]) {
        thisTiVo.enabled = NO;
        return nil;
    }
    thisTiVo.enabled = YES;
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
		self.showURLConnection = nil;
		_mediaKey = @"";
		isConnecting = NO;
        managingDownloads = NO;
        _manualTiVo = NO;
		firstUpdate = YES;
        _enabled = NO;
        _storeMediaKeyInKeychain = NO;
        itemStart = 0;
        itemCount = 50;
        tivoBugDuplicatePossibleStart = -1;
        reachabilityContext.version = 0;
        reachabilityContext.info = (__bridge void *)(self);
        reachabilityContext.retain = NULL;
        reachabilityContext.release = NULL;
        reachabilityContext.copyDescription = NULL;
        elementToPropertyMap = @{
            @"Title" :          @{kMTValue : @"seriesTitle",      kMTType : @(kMTStringType)},
            @"EpisodeTitle" :   @{kMTValue : @"episodeTitle",     kMTType : @(kMTStringType)},
            @"CopyProtected" :  @{kMTValue : @"protectedShow",    kMTType : @(kMTBoolType)},
            @"InProgress" :     @{kMTValue : @"inProgress",       kMTType : @(kMTBoolType)},
            @"SourceSize" :     @{kMTValue : @"fileSize",         kMTType : @(kMTNumberType)},
            @"Duration" :       @{kMTValue : @"showLengthString", kMTType : @(kMTStringType)},
			@"CaptureDate" :    @{kMTValue : @"showDate",         kMTType : @(kMTDateType)},
			@"ShowingStartTime":@{kMTValue : @"showDate",         kMTType : @(kMTDateType)},
            @"Description" :    @{kMTValue : @"showDescription",  kMTType : @(kMTStringType)},
            @"SourceChannel" :  @{kMTValue : @"channelString",    kMTType : @(kMTStringType)},
            @"SourceStation" :  @{kMTValue : @"stationCallsign",  kMTType : @(kMTStringType)},
            @"HighDefinition" : @{kMTValue : @"isHD",             kMTType : @(kMTBoolType)},
            @"ProgramId" :      @{kMTValue : @"programId",        kMTType : @(kMTStringType)},
            @"SeriesId" :       @{kMTValue : @"seriesId",         kMTType : @(kMTStringType)},
            @"TvRating" :       @{kMTValue : @"tvRating",         kMTType : @(kMTNumberType)},
            @"MpaaRating" :     @{kMTValue : @"mpaaRating",       kMTType : @(kMTNumberType)},
            @"SourceType" :     @{kMTValue : @"sourceType",       kMTType : @(kMTStringType)},
            @"IdGuideSource" :  @{kMTValue : @"idGuidSource",     kMTType : @(kMTStringType)}};
		elementToPropertyMap = [[NSDictionary alloc] initWithDictionary:elementToPropertyMap];
		_currentNPLStarted = nil;
		_lastDownloadEnded = [NSDate date];
		_manualTiVoID = -1;
        self.rpcIDs = [NSMutableDictionary dictionary];
	}
	return self;
	
}

-(id) initWithTivo:(MTNetService *)tiVo withOperationQueue:(NSOperationQueue *)queue manual:(BOOL)isManual withID:(int)manualTiVoID withSerialNumber:(NSString *)TSN {
	DDLogReport(@"Initing new TiVo with %@", tiVo);
	self = [self init];
	if (self) {
		self.tiVo = tiVo;
		DDLogReport(@"Created new TiVo %@ with %@", self, tiVo);
		_enabled = NO;
        _manualTiVo = isManual;
        self.manualTiVoID = manualTiVoID;
		self.opsQueue = queue;
        _tiVoSerialNumber = TSN;
		DDLogReport(@"Created new TiVo %@ with %@", self, tiVo);
        if (isManual) {
            DDLogMajor(@"testing reachability for tivo %@ with address %@",self.tiVo.name, self.tiVo.iPAddress);
            _reachability = SCNetworkReachabilityCreateWithName(kCFAllocatorDefault, [self.tiVo.iPAddress UTF8String]);
        } else {
            DDLogMajor(@"testing reachability for tivo %@ with address %@",self.tiVo.name, self.tiVo.addresses[0]);
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
    DDLogReport(@"Tivo %@ is now %@", thisTivo.tiVo.name, thisTivo.isReachable ? @"online" : @"offline");
    if (thisTivo.isReachable) {
		thisTivo.networkAvailability = [NSDate date];
		[NSObject cancelPreviousPerformRequestsWithTarget:thisTivo selector:@selector(manageDownloads:) object:thisTivo];
		if (thisTivo.supportsRPC) {
			[thisTivo.myRPC launchServer];
		} else {
        	[thisTivo scheduleNextUpdateAfterDelay: kMTTiVoAccessDelay];
		}
		[thisTivo performSelector:@selector(manageDownloads) withObject:nil afterDelay:kMTTiVoAccessDelay+2];
	} else {
		[thisTivo.myRPC stopServer];
	}
    [NSNotificationCenter postNotificationNameOnMainThread: kMTNotificationNetworkChanged object:nil];
}

-(void)setupNotifications
{
	if (self.isMini) return;
	NSNotificationCenter *defaultCenter = [NSNotificationCenter defaultCenter];
	[defaultCenter addObserver:self selector:@selector(manageDownloads:) name:kMTNotificationDownloadQueueUpdated object:nil];
	[defaultCenter addObserver:self selector:@selector(manageDownloads:) name:kMTNotificationTransferDidFinish object:nil];
	[defaultCenter addObserver:self selector:@selector(manageDownloads:) name:kMTNotificationDecryptDidFinish object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(appWillTerminate:)
												 name:NSApplicationWillTerminateNotification
											   object:nil];
}

-(void) saveLastLoadTime:(NSDate *) newDate{
	if (!newDate) return;
    if (!self.tiVo.name.length) return;
	NSDate * currentDate = tiVoManager.lastLoadedTivoTimes[self.tiVo.name];

	if (!currentDate || [newDate isGreaterThan: currentDate]) {
		DDLogReport (@"Updating last load time from %@ to %@", currentDate, newDate);
		tiVoManager.lastLoadedTivoTimes[self.tiVo.name] = newDate;
	}

}

-(NSString * ) description
{
    if (self.manualTiVo) {
        return [NSString stringWithFormat:@"%@ (%@:%hd/%hd/%hd) %@",
            self.tiVo.name,
            self.tiVo.iPAddress,
            self.tiVo.userPort,
            self.tiVo.userPortSSL,
            self.tiVo.userPortRPC,
            self.enabled ? @"": @" disabled"
            ];
    } else {
		return [self.tiVo.name stringByAppendingString: self.enabled ? @"": @" disabled"];
    }
}

-(void) checkRPC {
	if (self.enabled && !self.myRPC.isActive) {
		if (self.supportsRPC && self.mediaKey.length > 0) {
			int port = self.manualTiVo ? self.tiVo.userPortRPC : 1413;
			self.myRPC = [[MTTivoRPC alloc] initServer:self.tiVo.hostName tsn:self.tiVoSerialNumber onPort: port andMAK:self.mediaKey forDelegate:self];
		}
	} else if (!self.enabled && self.myRPC){
		[self.myRPC stopServer];
		self.myRPC = nil;
	}
}

-(void)setEnabled:(BOOL) enabled {
	if (enabled && [tiVoManager duplicateTiVoFor:self]) {
		enabled = NO;
	}
	BOOL didChange = enabled == _enabled;
	@synchronized (self) {
		_enabled = enabled;
	}
	[self checkRPC];
	if (didChange && !self.isMini) {
		[tiVoManager channelsChanged:self];
	}
    if (didChange) [tiVoManager updateTiVoDefaults:self];
}

-(BOOL) isMini {
	return [self.tiVoSerialNumber hasPrefix:@"A9"] && ![self.tiVoSerialNumber hasPrefix: @"A94"]; //not streams
}

-(BOOL) isOlderTiVo {
	if (self.isMini) return NO;
	char digit = (char)[self.tiVoSerialNumber characterAtIndex:0] ; //unicode irrelevant
	return digit != 'A' && digit < '8';
}

-(BOOL) enabled {
    @synchronized (self) {
        return _enabled;
    }
}

-(void) setTiVoSerialNumber:(NSString *)TSN {
    if ([TSN hasPrefix:@"tsn:"]) {
        TSN = [TSN substringWithRange:NSMakeRange(4, TSN.length-4)];
    }
    if (TSN.length == 0) return;
    if ([TSN isEqualToString:_tiVoSerialNumber]) return;
    _tiVoSerialNumber = TSN;
    if (self.enabled && [tiVoManager duplicateTiVoFor:self]) {
        self.enabled = NO;
    } else {
        [tiVoManager updateTiVoDefaults:self];
    }
}

-(NSDictionary *)descriptionDictionary
{
    NSDictionary *retValue = nil;
    if (_manualTiVo) {
        retValue = @{kMTTiVoManualTiVo :   @YES,
                     kMTTiVoUserName :      self.tiVo.name ?: @"TiVo Default",
                     kMTTiVoUserPort :    @(self.tiVo.userPort),
                     kMTTiVoUserPortSSL : @(self.tiVo.userPortSSL),
                     kMTTiVoTSN :           self.tiVoSerialNumber ?: @"",
                     kMTTiVoUserPortRPC : @(self.tiVo.userPortRPC),
                     kMTTiVoIPAddress :     self.tiVo.iPAddress ?: @"0.0.0.0",
                     kMTTiVoEnabled :     @(self.enabled),
                     kMTTiVoID :          @(self.manualTiVoID),
                     kMTTiVoMediaKey :      self.mediaKey.length ? self.mediaKey: kMTTiVoNullKey
                     };
    } else {
        retValue = @{kMTTiVoManualTiVo :   @NO,
                     kMTTiVoUserName :      self.tiVo.name ?: @"TiVo Default",
                     kMTTiVoTSN :           self.tiVoSerialNumber ?: @"",
                     kMTTiVoEnabled :     @(self.enabled),
					 kMTTiVoMediaKey :      self.mediaKey.length ? self.mediaKey: kMTTiVoNullKey
                     };
    }
    return retValue;
}

-(void) updateWithDescription:(NSDictionary *) newTiVo {
    BOOL newlyEnabled = ((NSNumber *) newTiVo[kMTTiVoEnabled]).boolValue && !self.enabled;
    BOOL shouldUpdate = newlyEnabled;

    if (self.manualTiVo) {
		BOOL rpcChanged = newlyEnabled;
		NSString * newName = newTiVo[kMTTiVoUserName];
		if (newName.length > 0 && [self.tiVo.userName  compare:newName] != NSOrderedSame) {
			self.tiVo.userName = newTiVo[kMTTiVoUserName];
            shouldUpdate = YES;
		}

		if (newTiVo[kMTTiVoIPAddress] && [self.tiVo.iPAddress caseInsensitiveCompare:newTiVo[kMTTiVoIPAddress]] != NSOrderedSame ) {
			self.tiVo.iPAddress = newTiVo[kMTTiVoIPAddress];
            shouldUpdate = YES;
			rpcChanged = YES;
		}

		if (newTiVo[kMTTiVoUserPort] && self.tiVo.userPort != [newTiVo[kMTTiVoUserPort] intValue]) {
			self.tiVo.userPort =  (short)[newTiVo[kMTTiVoUserPort] intValue];
            shouldUpdate = YES;
		}

		if (newTiVo[kMTTiVoUserPortSSL] && self.tiVo.userPortSSL != [newTiVo[kMTTiVoUserPortSSL] intValue]) {
			self.tiVo.userPortSSL = (short)[newTiVo[kMTTiVoUserPortSSL] intValue];
            shouldUpdate = YES;
		}

		if (newTiVo[kMTTiVoUserPortRPC] && self.tiVo.userPortRPC != [newTiVo[kMTTiVoUserPortRPC] intValue]) {
			self.tiVo.userPortRPC = (short)[newTiVo[kMTTiVoUserPortRPC] intValue];
            shouldUpdate = YES;
			rpcChanged = YES;
		}
		if (rpcChanged) self.myRPC = nil; //will be restarted by "enabled"
    }
	
	NSString * possMediaKey = newTiVo[kMTTiVoMediaKey];
    if ((possMediaKey.length > 0 && ! [possMediaKey isEqualToString: self.mediaKey] && ![possMediaKey isEqual:kMTTiVoNullKey])) {
        self.mediaKey = possMediaKey;
        shouldUpdate = YES;
    }
	
    if ((newTiVo[kMTTiVoTSN]      && ! [newTiVo[kMTTiVoTSN]      isEqualToString: self.tiVoSerialNumber]) ) {
        self.tiVoSerialNumber = (NSString *)newTiVo[kMTTiVoTSN];  //must be after enabled?
        shouldUpdate = YES;
    }

	self.enabled = [newTiVo[kMTTiVoEnabled] boolValue ]; //side effects of launching RPC

    if (shouldUpdate ) {
        DDLogDetail(@"Updated  TiVo %@ with %@",self, [newTiVo maskMediaKeys]);
       //Turn off label in UI
        [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationTiVoUpdated object:self];
        //RE-update shows
        if (newlyEnabled) [self scheduleNextUpdateAfterDelay:0];
    }
}

-(BOOL) isEqualToDescription:(NSDictionary *) tiVoDescrip {
	if (self.enabled != ((NSNumber *) tiVoDescrip[kMTTiVoEnabled]).boolValue) return NO;
	if (((NSString *)tiVoDescrip[kMTTiVoTSN]).length && ![self.tiVoSerialNumber isEqualToString: tiVoDescrip[kMTTiVoTSN]]) return NO;
	if (![self.mediaKey 		isEqualToString: tiVoDescrip[kMTTiVoMediaKey]]) return NO;

	BOOL manual = ((NSNumber *) tiVoDescrip[kMTTiVoManualTiVo]).boolValue;
	if (manual != self.manualTiVo) return NO;
	if (manual) {
		if (
			[self.tiVo.iPAddress caseInsensitiveCompare:tiVoDescrip[kMTTiVoIPAddress]] != NSOrderedSame ||
            [self.tiVo.userName  compare:tiVoDescrip[kMTTiVoUserName]] != NSOrderedSame ||
            self.tiVo.userPort    != ((NSNumber *) tiVoDescrip[kMTTiVoUserPort])   .intValue ||
            self.tiVo.userPortSSL != ((NSNumber *) tiVoDescrip[kMTTiVoUserPortSSL]).intValue ||
			self.tiVo.userPortRPC != ((NSNumber *) tiVoDescrip[kMTTiVoUserPortRPC]).intValue) {
			return NO;

		}
	} else {
		if (![self.tiVo.name isEqualToString:tiVoDescrip[kMTTiVoUserName]]) return NO;
	}
	return YES;
}

-(void)getMediaKey
{
	DDLogDetail(@"Getting media key for %@", self);
    NSArray *savedTiVos = tiVoManager.savedTiVos;
    if (savedTiVos.count == 0) {
        DDLogDetail(@"No Media Key to Crib");
        return;
    }
	BOOL foundMediaKey = NO;
	//check for this tivo
	for (NSDictionary *tiVo in savedTiVos) {
		NSString * possMediaKey = tiVo[kMTTiVoMediaKey];
		if ([tiVo[kMTTiVoUserName] isEqual:self.tiVo.name] &&
			![possMediaKey isEqual:kMTTiVoNullKey] &&
			possMediaKey.length > 0) {
			self.mediaKey = possMediaKey;
			foundMediaKey = YES;
			break;
		}
	}
	if (!foundMediaKey) { //look for any with a key
		for (NSDictionary * tiVo in savedTiVos) {
			NSString *possMediaKey = tiVo[kMTTiVoMediaKey];
			if (possMediaKey.length && ![possMediaKey isEqualToString:kMTTiVoNullKey]) {
				self.mediaKey = possMediaKey;
				foundMediaKey = YES;
				break;
			}
		}
		if (foundMediaKey) {
			//Need to update defaults
			[tiVoManager performSelectorOnMainThread:@selector(updateTiVoDefaults:) withObject:self waitUntilDone:YES];
		}
	}
	if (foundMediaKey) {
		[self checkRPC];
	}
}

#pragma mark - RPC delegate

-(void) receivedRPCData:(MTRPCData *)rpcData {
	MTTiVoShow * owner = self.rpcIDs[rpcData.rpcID];
	if (!owner) {
		DDLogDetail(@"Metadata before XML for %@", rpcData);
		return;
	}
    if ([NSThread isMainThread]) {
        owner.rpcData = rpcData;
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
        owner.rpcData = rpcData;
    });
    }
}

-(MTRPCData *) registerRPCforShow: (MTTiVoShow *) show  {
    NSString * rpcKey = [NSString stringWithFormat:@"%@|%@",self.tiVo.hostName, show.idString];
    [self.rpcIDs setObject:show forKey:rpcKey ];
    return [show.tiVo.myRPC rpcDataForID:show.idString];
}

- (void)rpcResync {
	//maybe a show moved in list, suggesting that it was a suggestion, and now isn't
	DDLogDetail(@"Resynching shows due to skipMode notification");
	[self reloadRecentShows];
	[self updateShows:self];
}

-(void) tivoReports: (NSInteger) numShows
		       withNewShows:(NSArray<NSString *> *)addedShows
              atTiVoIndices: (NSArray <NSNumber *> *) addedShowIndices
            andDeletedShows:(NSDictionary < NSString *, MTRPCData *> *)deletedIds
			  isFirstLaunch:(BOOL)firstLaunch {
    //In future, addedShowIndices could become NSIndexSet
    NSAssert(addedShowIndices.count == addedShows.count, @"Added RPC show problem");
    if (isConnecting) {
        //change during a Tivo XML refresh; need to restart after termination
		if (!cancelRefresh) {
			if (firstUpdate && firstLaunch) {
				//expected first RPC list during first NPL download; just ignore
				DDLogDetail(@"Ignoring first RPC during first XML download %@ ", self);
			} else {
				DDLogMajor(@"Show list change during Tivo %@ XML refresh", self);
				cancelRefresh = YES;
			}
		}
        return;
    }
    DDLogDetail(@"Updating Tivo %@ from RPC", self);
    DDLogVerbose(@"Adding %@ and deleting %@", addedShows, deletedIds);
	if (addedShows.count + deletedIds.count >= 10) {
		DDLogMajor(@"Too many RPC changes; reloading %@", self);
		[self updateShows:self];
		return;
	}
	if (self.shows.count + addedShows.count - deletedIds.count != (NSUInteger) numShows ) {
		DDLogMajor(@"NPL and RPC out of sync; reloading %@", self);
		[self updateShows:self];
        return;
    }
    NSMutableArray <MTTiVoShow *> * showsAfterDeletions = [NSMutableArray arrayWithCapacity:self.shows.count];
	NSMutableArray <NSString *> * showsToLookFor = [addedShows mutableCopy];
	NSMutableArray <NSNumber *> * indicesToLookFor = [addedShowIndices mutableCopy];
    [self.shows enumerateObjectsUsingBlock:^(MTTiVoShow * _Nonnull show, NSUInteger showsIndex, BOOL * _Nonnull stop) {
        if (deletedIds[show.idString ] ){
            [self markDeletedDownloadShow:show];
        } else if (show.inProgress.boolValue) {
            //this is tricky.
            //pretend inProgress have been deleted and then added back in
            //so insert them into showsToLookFor.
            //matching indicesToLookFor is where it should end up.
            //everyone before this show is either in showsAfterDeletion OR in
            //showsToLookFor with an index less than ours.
            NSUInteger addedIndex = [indicesToLookFor indexOfObjectPassingTest:^BOOL(NSNumber * _Nonnull obj, NSUInteger indicesIdx, BOOL * _Nonnull stop2) {
                return obj.unsignedIntegerValue > showsAfterDeletions.count+indicesIdx;
            }];
           if (addedIndex == NSNotFound) addedIndex = showsToLookFor.count;
            DDLogDetail(@"adding In Progress show %@(%@) to RPC added list at %d", show, show.idString, (int)addedIndex);
            [showsToLookFor insertObject:show.idString atIndex:addedIndex];
            [indicesToLookFor insertObject:@(showsAfterDeletions.count + addedIndex) atIndex:addedIndex];
        } else {
            [showsAfterDeletions addObject:show];
        }
    }];
    self.shows = showsAfterDeletions;
    DDLogVerbose(@"Previous shows after deletions were: %@:",showsAfterDeletions); 

    if (showsToLookFor.count > 0) {
        self.addedShows = showsToLookFor;
        self.addedShowIndices = indicesToLookFor;
        [self startNPLDownload:NO];
    } else {
    	[self reloadRecentShows]; //not going to be done by NPLDownload, so do it now.
        [NSNotificationCenter  postNotificationNameOnMainThread:kMTNotificationTiVoShowsUpdated object:nil];
    }
}

-(NSRange) getFirstRange:(NSArray <NSNumber *> *)indices {
    if (indices.count == 0) return NSMakeRange(0, 0);;
    NSUInteger end = 0;
    //look for sequence
    while (end+1 < indices.count && indices[end].unsignedIntegerValue +1 == indices[end+1].unsignedIntegerValue) end++;
    NSUInteger startValue = indices[0].unsignedIntegerValue;
    NSUInteger endValue = indices[end].unsignedIntegerValue;
    NSRange result = NSMakeRange(startValue,
                       endValue-startValue+1);
    return result;
}

-(void) startNPLDownload:(BOOL) getAll {
	if (self.isMini) return;
	
    if (isConnecting || !self.enabled) {
        DDLogDetail(@"But was %@", isConnecting? @"Connecting!": @"Disabled!");
        return;
    }
    if (self.showURLConnection) {
        [self.showURLConnection cancel];
        self.showURLConnection = nil;
    }
    isConnecting = YES;
    cancelRefresh = NO;
    [newShows removeAllObjects];

    [NSNotificationCenter  postNotificationNameOnMainThread:kMTNotificationTiVoUpdating object:self];
    if (self.currentNPLStarted) {
        [self saveLastLoadTime:self.currentNPLStarted]; //remember previous successful load time
    }
    self.currentNPLStarted = [NSDate date];
    self.oneBatch = !getAll;
    if (getAll) {
		previousShowList = [NSMutableDictionary dictionary];
		for (MTTiVoShow * show in _shows) {
			if(!show.inProgress.boolValue){
				[previousShowList setValue:show forKey:show.idString];
			}
		}
		DDLogVerbose(@"Previous shows were: %@:",previousShowList);
		tivoBugDuplicatePossibleStart = -1;
        [self updateShowsForRange:NSMakeRange(0, kMTNumberShowToGetFirst)];
    } else {
        [self updateShowsForRange:[self getFirstRange: self.addedShowIndices]];
    }
}

#pragma mark - TiVoRPC switchboard

-(void) reloadShowInfoForShows: (NSArray <MTTiVoShow *> *) shows {
    NSMutableArray <NSString *> * showIDs = [NSMutableArray arrayWithCapacity:shows.count];
    for (MTTiVoShow * eachShow in shows) {
        [showIDs addObject:eachShow.idString];
    }
    [self.myRPC purgeShows:showIDs ];
    [self.myRPC getShowInfoForShows:showIDs];  //rely on setting rpcData for each show
}

-(BOOL) supportsTransportStream {
    NSString * TSN = self.tiVoSerialNumber;
    return TSN.length == 0 || [TSN characterAtIndex:0] > '6' || [TSN hasPrefix:@"663"] || [TSN hasPrefix:@"658"] || [TSN hasPrefix:@"652"];
}

-(BOOL) supportsRPC {
    return self.tiVoSerialNumber.length == 0 || [self.tiVoSerialNumber characterAtIndex:0] > '6' ;
}


BOOL channelChecking = NO;
-(void) connectionChanged {
	[NSNotificationCenter postNotificationNameOnMainThread:kMTNotificationTiVoListUpdated object:nil];
	if (self.rpcActive && !self.channelList && !self.isMini && !channelChecking) {
		channelChecking = YES;
		__weak __typeof__(self) weakSelf = self;
		[self.myRPC channelListWithCompletion:^(NSDictionary <NSString *, NSDictionary <NSString *, NSString *> *> *channels) {
			__typeof__(self) strongSelf = weakSelf;
			strongSelf.channelList = channels;
			[tiVoManager channelsChanged:strongSelf];
			channelChecking = NO;
		}];
	}
}

-(BOOL) rpcActive {
    return self.myRPC != nil && self.myRPC.isActive;
}

-(NSArray < NSString *> *) recordingIDsForShows: (NSArray <MTTiVoShow *> *) shows {
    NSArray * recordingIds = [shows mapObjectsUsingBlock:^id(MTTiVoShow * show, NSUInteger idx) {
        if (show.tiVo != self) {
            return nil;
        } else {
            return show.rpcData.recordingID;
        }
    }];
    return recordingIds;
}

-(void) deleteTiVoShows: (NSArray <MTTiVoShow *> *) shows {
    [self.myRPC deleteShowsWithRecordIds:[self recordingIDsForShows:shows]];
}

-(void) stopRecordingTiVoShows: (NSArray <MTTiVoShow *> *) shows {
    [self.myRPC stopRecordingShowsWithRecordIds:[self recordingIDsForShows:shows]];
}

-(void) sendKeyEvent: (NSString *) keyEvent {
	[self.myRPC sendKeyEvent: keyEvent withCompletion:nil];
}

-(void) sendURL: (NSString *) URL {
	[self.myRPC sendURL:URL];
}

-(void) playShow:(MTTiVoShow *)show {
    if ([show.tiVo isEqual:self] &&
		show.rpcData.recordingID.length > 0) {
		[self.myRPC playOnTiVo:show.rpcData.recordingID withCompletionHandler:nil];
    }
}

-(void) reboot {
	[self.myRPC rebootTiVo];
}

-(void) whatsOnWithCompletion:  (void (^)(MTWhatsOnType whatsOn, NSString * recordingID, NSString * channelNumber)) completionHandler {
	[self.myRPC whatsOnSearchWithCompletion:completionHandler];
}

-(void) findCommercialsForShow: (MTTiVoShow *) show interrupting:(BOOL) interrupt {
	if (!show || show.rpcData.edlList.count > 0) return;
	BOOL notAlreadyWaitingForCommercials = self.postponedCommercialShows == nil;
	if (notAlreadyWaitingForCommercials) {
		self.postponedCommercialShows = [NSMutableSet setWithObject:show];
	} else {
		[self.postponedCommercialShows addObject:show];
	}
	if (interrupt) {
		[self reallyFindCommercialsForShows]; //as long as we're interrupting, send ones that were waiting as well
	} else if (notAlreadyWaitingForCommercials) {
		//let any other shows get into queue before launching.
		[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(findCommercialsNoInterrupt) object:nil ];
		[self performSelector:@selector(findCommercialsNoInterrupt) withObject:nil afterDelay:2];
	} else {
		//we're already waiting, so let it continue.
	}
}

-(void) tiVoInfoWithCompletion:  (void (^)(NSString * status)) completionHandler {
	__weak __typeof__(self) weakSelf = self;

	[self.myRPC tiVoInfoWithCompletion:^(NSString * rpcText) {
		
		[weakSelf.myRPC whatsOnSearchWithCompletion:^(MTWhatsOnType whatsOn, NSString *recordingID, NSString * channelNumber) {
			__typeof__(self) strongSelf = weakSelf;
			NSMutableString * outString = [NSMutableString string];
			NSArray * myShows = strongSelf.shows;
			
			if (self.isMini) {
				[outString appendString:@"TiVo Mini\n\n"];
			} else {
				NSPredicate * suggestedPredicate = [NSPredicate predicateWithFormat:@"isSuggestion == NO"];
				NSArray * regularShows = [tiVoManager.tiVoShows filteredArrayUsingPredicate:suggestedPredicate];
				int totalShows = (int)myShows.count;
				int regShows = (int)regularShows.count;
				[outString appendFormat:@"Recordings: %d  (%d Regular; %d Suggestions)\n\n",  totalShows, regShows, totalShows-regShows];
				
			}
			NSString * result = nil;
			NSString * channelString = channelNumber ? [NSString stringWithFormat:@" (channel: %@)",channelNumber] : @"";
			switch (whatsOn) {
				case MTWhatsOnUnknown:
					result = @"Unknown";
					break;
				case MTWhatsOnLiveTV:
					result = [NSString stringWithFormat: @"Showing live TV%@", channelString];;
					break;
				case MTWhatsOnRecording:
					if (strongSelf.isMini) myShows = tiVoManager.tiVoShows;
					for (MTTiVoShow * show in myShows) {
						if ([show.rpcData.recordingID isEqualToString:recordingID]) {
							NSString * tivoName = @"";
							if (strongSelf != show.tiVo ) {
								tivoName = [NSString stringWithFormat:@" (%@)",show.tiVoName];
							}
							result = [NSString stringWithFormat:  @"Showing a recording:\n     %@%@%@%@"
									  ,show.showTitle,tivoName,channelString,[show.protectedShow boolValue]?@"-Protected":@""];
							break;
						}
					}
					if (!result) result = @"Showing an unknown recording";
					break;
				case MTWhatsOnStreamingOrMenus:
					result = @"Menus or streaming";
					break;
				case MTWhatsOnLoopset:
					result = @"Screensaver";
					break;
				default:
					break;
			}
			if (result.length > 0) {
				[outString appendFormat:@"Current Activity: %@\n\n", result];
			}
			[outString appendString:rpcText];
			[outString appendFormat:@"Serial Number: %@\n\n", strongSelf.tiVoSerialNumber];
			[outString appendFormat:@"Local Address: %@\n\n", strongSelf.tiVo.hostName];

			if (completionHandler) completionHandler([outString copy]);
		}];
	} ];
}

-(void) cancelCommercialingForShow: (MTTiVoShow *) show {
	[self.postponedCommercialShows removeObject:show];
}

-(void) findCommercialsNoInterrupt {
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(findCommercialsNoInterrupt) object:nil ];
	if (self.postponedCommercialShows.count == 0 || !tiVoManager.autoSkipModeScanAllowedNow) {
		self.postponedCommercialShows = nil;
	} else {
		__weak __typeof__(self) weakSelf = self;
		[self whatsOnWithCompletion:^(MTWhatsOnType whatsOn, NSString *recordingID, NSString * channelNumber) {
			__typeof__(self) strongSelf = weakSelf;
			if (whatsOn == MTWhatsOnLiveTV || whatsOn == MTWhatsOnStreamingOrMenus || whatsOn == MTWhatsOnLoopset) {
				[strongSelf reallyFindCommercialsForShows];
			} else {
				DDLogDetail(@"Waiting for TiVo UI to be available");
				[strongSelf performSelector:@selector(findCommercialsNoInterrupt) withObject:nil afterDelay:60];
			}
		}];
	}
}

-(void) reallyFindCommercialsForShows {
	NSSortDescriptor * sorter = [NSSortDescriptor sortDescriptorWithKey:@"hasSkipModeInfo" ascending:NO];
	NSArray <MTTiVoShow *> * hasInfoFirst = [self.postponedCommercialShows sortedArrayUsingDescriptors:@[sorter]];
	self.postponedCommercialShows = nil;
	for (MTTiVoShow * show in hasInfoFirst) {
		if (show.tiVo == self) {
			if ( !show.inProgress.boolValue && show.mightHaveSkipModeInfo && (show.rpcData.edlList.count == 0)) {
            	DDLogMajor(@"Asking for SkipMode data for %@ on %@", show, self);
				show.rpcData.tempLength = show.showLength; //hint in case tivo isn't reporting this
            	[self.myRPC findSkipModeEDLForShow:show.rpcData];
        	} else {
				DDLogDetail(@"No need for SkipMode data for %@ on %@: %@ %@", show, self, show.isSuggestion ? @"Suggestion" : @"", show.inProgress.boolValue ? @"In progress" : show.rpcData.edlList.count > 0 ? @"Already have" : !show.mightHaveSkipModeInfo ? @"won't have for other reason" : @"Error" );
			}
        }
	}
}

-(NSString *) skipModeStatus {
	NSArray <MTRPCData *> * skipModeQueue = [self.myRPC showsWaitingForSkipMode];
	if (skipModeQueue.count == 0) return @"";
	NSString * title = skipModeQueue[0].series;
	if (!title.length) {
		DDLogReport(@"Missing SkipMode title: %@", skipModeQueue[0]);
		return [NSString stringWithFormat: @"%@ (%d)", self.tiVo.name, (int)skipModeQueue.count];
	}
	if (skipModeQueue.count == 1) {
		return [NSString stringWithFormat: @"%@ (%@)", self.tiVo.name, title];
	} else {
		return [NSString stringWithFormat: @"%@ (%@ + %d)", self.tiVo.name, title, (int)(skipModeQueue.count - 1)];
	}
}
			
-(void) scheduleNextUpdateAfterDelay:(NSInteger)delay {
    [MTTiVo cancelPreviousPerformRequestsWithTarget:self
                                           selector:@selector(updateShows:)
                                             object:nil ];
    if (delay < 0) {
        NSInteger minDelay =  [[NSUserDefaults standardUserDefaults] integerForKey:kMTUpdateIntervalMinutesNew];
        if (minDelay == 0) {
            minDelay = (self.rpcActive ?  kMTUpdateIntervalMinDefault : kMTUpdateIntervalMinDefaultNonRPC);
        }
        delay = minDelay*60;
    }
    DDLogDetail(@"Scheduling Update with delay of %lu seconds", (long)delay);
    [self performSelector:@selector(updateShows:) withObject:nil afterDelay:delay ];
}

-(void)updateShows:(id)sender
{
	DDLogDetail(@"Updating Tivo %@", self);
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(updateShows:) object:nil];
    [self startNPLDownload:YES];
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

-(void) updateShowsForRange:(NSRange) range {
    NSString *portString = @"";
    if ([_tiVo isKindOfClass:[MTNetService class]]) {
        portString = [NSString stringWithFormat:@":%d",_tiVo.userPortSSL];
    }
    if (self.oneBatch && tivoBugDuplicatePossibleStart > 0 && range.location >= (NSUInteger) tivoBugDuplicatePossibleStart) {
        //Tivo bug: for a requested show range above a certain number, TiVo will return shows "slipped" down by one.
        //e.g. if number is 30, then range accesses  31 - 35 will actually returns 30-34.
        //You'll see this when we pull the whole show list, some shows will be thrown away as a duplicate
        //That's sufficent for NPL, but if we are told by RPC that there's a new show at #75 (e.g. a Tivo Suggestion), then
        //when we request only that show's XML, we get the wrong one.
        //To work around, we remember the range prior to that one, and when looking for a single show, we ask for more instead of one, and ignore the extras. Worst case, if tivo fixes bug but leaves dups, we only pull a couple extra shows.
        range.length = range.length + tivoBugDuplicateCount;
       DDLogDetail(@"Increasing length by %@ to %@ due to possible TiVo Range bug",@(tivoBugDuplicateCount), NSStringFromRange(range));
    }

    NSString *tivoURLString = [[NSString stringWithFormat:@"https://%@%@/TiVoConnect?Command=QueryContainer&Container=%%2FNowPlaying&Recurse=Yes&AnchorOffset=%d&ItemCount=%d",_tiVo.hostName,portString,(int)range.location,(int)range.length] stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    if (self.oneBatch) {
        DDLogMajor(@"Loading RPC info from TiVo %@ shows from %d to %d at URL %@",self, (int)range.location, (int)NSMaxRange(range)-1, tivoURLString);
    } else if (previousShowList.count ==0 && range.location ==0) {
        //first time for this tivo:
        DDLogReport(@"Initial loading from TiVo %@ at URL %@",self, tivoURLString);
    } else {
        DDLogMajor(@"Loading from TiVo %@ shows from %d to %d at URL %@",self, (int)range.location, (int)NSMaxRange(range)-1, tivoURLString);
    }
    NSURL *tivoURL = [NSURL URLWithString:tivoURLString];
    NSURLRequest *tivoURLRequest = [NSURLRequest requestWithURL:tivoURL];
    self.showURLConnection = [NSURLConnection connectionWithRequest:tivoURLRequest delegate:self];
    [urlData setData:[NSData data]];
    authenticationTries = 0;
    [self.showURLConnection start];
}

-(void)resetAllDetails
{
    [self.myRPC emptyCaches];
    self.shows = nil;
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

-(void)parser:(NSXMLParser *)parser didEndElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName
{
	[self endElement:elementName];
}

-(void) endElement:(NSString *) elementName {
	//just gives a shorter method name for DDLog

    DDLogVerbose(@"%@:  %@ --> %@",_tiVo.name,elementName,element);
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
            DDLogVerbose(@"Done loading XML for %@",currentShow);
            for (MTTiVoShow * oldShow in newShows) {
                if ([oldShow isEqual:currentShow]) {
                    DDLogDetail(@"Skipping duplicate new %@show %@ (%@) at %@",currentShow.isSuggestion ? @"suggested ":@"", currentShow.showTitle, currentShow.showDateString, @(newShows.count));
					if (!self.oneBatch) {
						if (tivoBugDuplicatePossibleStart < 0) {
                        	tivoBugDuplicatePossibleStart = itemStart - itemCount;
							tivoBugDuplicateCount = 1;
						} else {
							tivoBugDuplicateCount++;
						}
					}
                    currentShow = nil;
                    return;
                }
            }
            if (currentShow.inProgress.boolValue) {
                //can't use actual npl time, must use just before earliest in-progress so when it finishes, we'll pick it up next time
                NSDate * backUpToTime = [ currentShow.showDate dateByAddingTimeInterval:-1];
                if ([backUpToTime isLessThan:self.currentNPLStarted]) {
                    self.currentNPLStarted = backUpToTime;
                }
            }
            NSString * newShowID = currentShow.idString;
            MTTiVoShow *thisShow = nil;
           if (self.oneBatch) {
               for (NSString * showID in [self.addedShows copy]) {
                    if ([newShowID isEqualToString:showID]) {
						thisShow = [tiVoManager replaceProxyInQueue:currentShow]; //check for undeleted
                        DDLogMajor(@"RPC Adding %@ at %@", currentShow, newShowID);
                        [self.addedShows removeObject:showID];
                       break;
                    }
               }
               if (!thisShow) {
				   DDLogDetail(@"Ignoring show %@: %@", newShowID, currentShow);
                }
            } else {
                thisShow = [previousShowList valueForKey:newShowID];
                if (thisShow) {
                    DDLogDetail(@"Updated show %@", currentShow.showTitle);
                    [previousShowList removeObjectForKey:newShowID];
					if (thisShow.inProgress.boolValue) {
						thisShow = currentShow;
					} else {
						//need to update from latest version. (Only thing in tivo xml that may change)
						if (thisShow.isSuggestion && ! currentShow.isSuggestion) {
							//set by imageString
							[self loadSkipModeInfoForShow: currentShow];
						}
						thisShow.imageString = currentShow.imageString;
					}
                } else {
                    DDLogDetail(@"Added new %@show %@ (%@) at %@",currentShow.isSuggestion ? @"suggested " : @"", currentShow.showTitle, currentShow.showDateString, @(newShows.count));
                    //Now check and see if this was in the oldQueue (from last ctivo execution) OR an undeletedShow
					thisShow = [tiVoManager replaceProxyInQueue:currentShow];
                }
           }
            if (thisShow) {
                [newShows addObject:thisShow];
                numAddedThisBatch++;
                if (!thisShow.gotDetails) {
                   NSInvocationOperation *nextDetail = [[NSInvocationOperation alloc] initWithTarget:thisShow selector:@selector(getShowDetail) object:nil];
                    [self.opsQueue addOperation:nextDetail];

                }
           }
			currentShow = nil;
        }
    } else {
        if ([elementName compare:@"TotalItems"] == NSOrderedSame) {
            totalItemsOnTivo = [element intValue];
			DDLogDetail(@"TotalItems: %d",totalItemsOnTivo);
        } else if ([elementName compare:@"ItemStart"] == NSOrderedSame) {
            itemStart = [element intValue];
			DDLogDetail(@"ItemStart: %d",itemStart);
        } else if ([elementName compare:@"ItemCount"] == NSOrderedSame) {
            itemCount = [element intValue];
			DDLogDetail(@"ItemCount: %d",itemCount);
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

-(void) markDeletedDownloadShow: (MTTiVoShow *) deletedShow {
	[self cancelCommercialingForShow:deletedShow];
	deletedShow.imageString = @"deleted";
    if (deletedShow.isQueued) {
        NSArray <MTDownload *> * downloads = [tiVoManager downloadsForShow:deletedShow];
        for (MTDownload * download in downloads) {
			if (download.isNew) {
            	download.downloadStatus = @(kMTStatusDeleted); //never gonna happen
			} else if (download.downloadStatus.intValue == kMTStatusWaiting ){ //might as well cancel
				[download cancel];
				download.downloadStatus = @(kMTStatusDeleted);
			} else { // should finish, but need to update Status column in download.
				[[NSNotificationCenter defaultCenter] postNotificationName: kMTNotificationDownloadRowChanged object:download];
        	}
		}
    }
}

-(void) loadSkipModeInfoForShow:(MTTiVoShow *) show {
	[self.myRPC getShowInfoForShows:@[show.idString] ];
}

-(void) reloadRecentShows {
//	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(reloadRecentShows) object:nil];
    //so when we get an RPC, it might signal a metadata change, so reload recent ones.
	NSMutableArray <NSString *> * recentIDs = [NSMutableArray array];
	NSMutableArray <MTTiVoShow *> * recentShows = [NSMutableArray array];
	NSTimeInterval recentTime = 60 * ( [[NSUserDefaults standardUserDefaults] integerForKey: kMTWaitForSkipModeInfoTime] + 60); //round up an hour
	for (MTTiVoShow * show in self.shows) {
		if (-[show.showDate timeIntervalSinceNow] < (show.showLength+recentTime)) {
			if (!show.protectedShow.boolValue && ![show hasSkipModeInfo] && show.mightHaveSkipModeInfo) {
				[recentIDs addObject:show.idString];
				[recentShows addObject:show];
			}
		}
	}
	if (recentIDs.count > 0) {
		DDLogMajor(@"reloading shows for metadata: %@", recentShows);
		[self.myRPC getShowInfoForShows:[recentIDs copy] ];
	}
}

-(void)parserDidEndDocument:(NSXMLParser *)parser
{
	//Check if we're done yet
    int numDuplicates =itemCount-numAddedThisBatch;
    if (itemCount == 0) {
        if (self.oneBatch) {
            DDLogReport(@"TiVo returned ZERO of %d requested shows for RPC!", (int)[self getFirstRange:self.addedShowIndices].length);
            cancelRefresh = YES;
        } else {
            DDLogReport(@"TiVo returned ZERO requested shows! Ignoring shows from %d to %d", itemStart, totalItemsOnTivo);
        }
    } else if (numDuplicates == 0) {
        DDLogMajor(@"Finished batch for %@. Found %d shows.", self, numAddedThisBatch);
    } else if (numAddedThisBatch == 0) {  //Streaming Movies reported as shows bug
        DDLogMajor(@"Finished batch for %@. Only duplicated shows.", self);
    } else {
        DDLogMajor(@"Finished batch for %@. Found %d shows, but %d duplicate%@.", self, numAddedThisBatch, numDuplicates, numDuplicates == 1 ? @"": @"s" );
    }
    if (cancelRefresh) {
        //had some kind of sync problem, so start all over.
        DDLogReport(@"Resynching TiVo %@!", self);
        isConnecting = NO;
		self.currentNPLStarted = nil; //don't remember this update time
        [NSNotificationCenter postNotificationNameOnMainThread:kMTNotificationTiVoUpdated object:self];
       [self scheduleNextUpdateAfterDelay:0];
    } else if (self.oneBatch) {
        NSRange currentBatch = [self getFirstRange:self.addedShowIndices];
        if (currentBatch.length != newShows.count ||
            currentBatch.location > self.shows.count) {
            DDLogMajor(@"TiVo %@ out of RPC sync!", self);
            isConnecting = NO;
            [NSNotificationCenter postNotificationNameOnMainThread:kMTNotificationTiVoUpdated object:self];
            [self scheduleNextUpdateAfterDelay:0];
        } else {
            DDLogDetail(@"got next batch %@ of RPC: %@", NSStringFromRange(currentBatch), newShows);
            NSMutableArray * updatedShows = [self.shows mutableCopy];
            [updatedShows insertObjects:newShows atIndexes:[NSIndexSet indexSetWithIndexesInRange:currentBatch]];
            self.shows = updatedShows;
            [newShows removeAllObjects];
            [self.addedShowIndices removeObjectsInRange:NSMakeRange(0, currentBatch.length)];
            if (self.addedShowIndices.count > 0) {
                [self updateShowsForRange :[self getFirstRange:self.addedShowIndices]];
            } else {
                isConnecting = NO;
                [NSNotificationCenter postNotificationNameOnMainThread:kMTNotificationTiVoUpdated object:self];
            }
        }
		[self reloadRecentShows];
    } else if (self.enabled  && (itemCount > 0 && itemStart+itemCount < totalItemsOnTivo)) { // && numAddedThisBatch > 0) {
        DDLogDetail(@"More shows to load from %@", self);
        if (newShows.count > _shows.count) {
            self.shows = [NSArray arrayWithArray:newShows];
        }
        [self updateShowsForRange :NSMakeRange( itemStart + itemCount,kMTNumberShowToGet)];
    } else {
        isConnecting = NO;
        DDLogMajor(@"TiVo %@ completed full update", self);
        self.shows = [NSArray arrayWithArray:newShows];
        if (firstUpdate) {
            [tiVoManager checkDownloadQueueForDeletedEntries:self];
            firstUpdate = NO;
        }
        [self scheduleNextUpdateAfterDelay:-1];
        DDLogDetail(@"Deleted shows: %@",previousShowList);
        for (MTTiVoShow * deletedShow in [previousShowList objectEnumerator]){
            [self markDeletedDownloadShow:deletedShow];
        };
        [NSNotificationCenter postNotificationNameOnMainThread:kMTNotificationTiVoUpdated object:self];
		[self reloadRecentShows];
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
    [NSNotificationCenter postNotificationNameOnMainThread:kMTNotificationTiVoUpdated object:self];

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

-(void)manageDownloads:(NSNotification *)notification
{
//    if ([tiVoManager.hasScheduledQueueStart boolValue]  && [tiVoManager.queueStartTime compare:[NSDate date]] == NSOrderedDescending) { //Don't start unless we're after the scheduled time if we're supposed to be scheduled.
//        DDLogMajor(@"%@ Delaying download until %@",self,tiVoManager.queueStartTime);
//		return;
//    }
	if ([tiVoManager checkForExit]) return;
	id object = notification.object;
	if (!object || object == self ||
		([object isKindOfClass:[MTTiVoShow class]] && ((MTTiVoShow *)object).tiVo == self)) {
		DDLogDetail(@"%@ got manageDownload notification %@",self, notification.name);
		[self manageDownloads];
	} else {
		DDLogDetail(@"%@ ignoring notification %@ for %@",self,notification.name, notification.object);
	}
}

-(void)manageDownloads
{
	if (managingDownloads) {
        return;
    }
	managingDownloads = YES;
	if (!self.isReachable || !self.enabled ||
		tiVoManager.numEncoders >= [[NSUserDefaults standardUserDefaults] integerForKey: kMTMaxNumEncoders]) {
		managingDownloads = NO;
		return;
	}
    //We are only going to have one each of Downloading, Encoding, and Decrypting.  So scan to see what currently happening
//	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(manageDownloads) object:nil];
    BOOL isDownloading = NO;
    for (MTDownload *download in self.downloadQueue) {
        if (download.isDownloading) {
            isDownloading = YES;
			break;
		}
	}
	if (!tiVoManager.processingPaused.boolValue) {
		DDLogDetail(@"%@ Checking for new download", self);
		BOOL launchedOne = NO; //true after we launched one, to allow us to scan for skipMode's needed in rest of queue without ever launching 2
		for (MTDownload *download in self.downloadQueue) {
			if ([download.show.protectedShow boolValue] ) {
				//protectedShow is used in downloadQueue during startup to indicate not loaded yet.
				if ([download isDone]) {
					continue;  //ignore completed ones
				} else {
					break; //but don't process if we have uncompleted, unloaded ones
				}
			}
			int status = download.downloadStatus.intValue;
			if (status == kMTStatusWaiting ||
				status == kMTStatusSkipModeWaitEnd) {
				[download skipModeCheck]; //note: may call us recursively, but status will = New or postcommercial
			}
			if (!launchedOne) {
				if ((status == kMTStatusNew  && !isDownloading ) ||
					(status == kMTStatusAwaitingPostCommercial)) {
					launchedOne = YES;
					BOOL isNew = status == kMTStatusNew;
					tiVoManager.numEncoders++;
					DDLogMajor(@"Number of encoders after %@ show \"%@\"  is %d",isNew ? @"launching" : @"commercial launch" ,download.show.showTitle, tiVoManager.numEncoders);
					if (isNew) {
						[download launchDownload];
					} else {
						[download launchPostCommercial];
					}
				}
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
	if (challenge.previousFailureCount == 0) {
		DDLogDetail(@"%@ password ask",self);
        if (challenge.proposedCredential) {
            DDLogDetail(@"Got mediaKey from keyChain");
            NSString * newPassword = challenge.proposedCredential.password;
            if (newPassword && ![newPassword isEqualToString:self.mediaKey]) {
                self.mediaKey = newPassword;
                [tiVoManager performSelectorOnMainThread:@selector(updateTiVoDefaults:) withObject:self waitUntilDone:NO];
            }

            [challenge.sender useCredential:challenge.proposedCredential forAuthenticationChallenge:challenge];
        } else {
            DDLogDetail(@"sending mediaKey from userDefaults");
           NSURLCredentialPersistence persistance = NSURLCredentialPersistenceForSession;
            if (self.storeMediaKeyInKeychain) {
                persistance = NSURLCredentialPersistencePermanent;
            }
            NSURLCredential *myCredential = [NSURLCredential credentialWithUser:@"tivo" password:self.mediaKey persistence:persistance];
            [challenge.sender useCredential:myCredential forAuthenticationChallenge:challenge];
        }
	} else {
		DDLogReport(@"%@ challenge failed",self);
		[challenge.sender cancelAuthenticationChallenge:challenge];
		BOOL noMAK = self.mediaKey.length == 0;
		DDLogMajor(@"%@ MAK, so failing URL Authentication %@",noMAK ? @"No" : @"Invalid", self);
		[self.showURLConnection cancel];
		self.showURLConnection = nil;
		isConnecting = NO;
        [NSNotificationCenter postNotificationNameOnMainThread:kMTNotificationTiVoUpdated object:self];
		[NSNotificationCenter postNotificationNameOnMainThread:kMTNotificationMediaKeyNeeded object:@{@"tivo" : self, @"reason" : noMAK ?@"new" : @"incorrect"}];
	}
}

-(void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error
{
    DDLogReport(@"TiVo URL Connection Failed with error %@",[error maskMediaKeys]);
    NSNumber * streamError = error.userInfo[@"_kCFStreamErrorCodeKey"];
    DDLogDetail(@"URL ErrorCode: %@, streamErrorCode: %@ (%@)", @(error.code), streamError, [streamError class]);
	if ([streamError isKindOfClass:[NSNumber class]] &&
			((error.code == -1004  && streamError.intValue == 49) ||
			 (error.code == -1200  && streamError.intValue == 49) ||
			 (error.code == -1005  && streamError.intValue == 57))) {
     	[self notifyUserWithTitle: @"Warning: Could not reach TiVo!"
						 subTitle: @"Antivirus program may be blocking connection"];
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

	if (urlData.length == 0) {
		DDLogReport(@"No data received from %@ on %@", self, connection);
		isConnecting = NO;
		[NSNotificationCenter postNotificationNameOnMainThread:kMTNotificationTiVoUpdated object:self];
		[self scheduleNextUpdateAfterDelay:-1];
	} else {
		NSXMLParser *parser = [[NSXMLParser alloc] initWithData:urlData];
		parser.delegate = self;
		[parser parse];
	}
    self.showURLConnection = nil;
}

#pragma mark - Memory Management

-(void) appWillTerminate: (id) notification {
	NSArray <MTTiVoShow *> * shows = self.shows;
	NSMutableArray <NSString *> * showIDs = [NSMutableArray arrayWithCapacity:shows.count];
	for (MTTiVoShow * show in shows) {
		//get rid of shows that might be updated by the next time we run
		if (!show.rpcData.edlList && !show.rpcData.clipMetaDataId && [show mightHaveSkipModeInfoLongest]) {
			DDLogDetail(@"Purging RPC for show %@",show);
			[showIDs addObject:show.idString];
		}
	}
	[self.myRPC purgeShows:showIDs];
}

-(void)dealloc
{
    DDLogDetail(@"Deallocing TiVo %@",self);
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[[[NSWorkspace sharedWorkspace] notificationCenter] removeObserver: self];
	SCNetworkReachabilityUnscheduleFromRunLoop(_reachability, CFRunLoopGetMain(), kCFRunLoopDefaultMode);
	if (_reachability) {
		CFRelease(_reachability);
	}
    _reachability = nil;
    [self.myRPC stopServer];
    self.tiVo = nil;
    self.myRPC.delegate = nil;
    self.myRPC = nil;
}

@end
