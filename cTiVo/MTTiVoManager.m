//
//  MTNetworkTivos.m
//  myTivo
//
//  Created by Scott Buchanan on 12/6/12.
//  Copyright (c) 2012 Scott Buchanan. All rights reserved.
//

#import "MTTiVoManager.h"
#import "MTiTivoImport.h"
#import "MTSubscription.h"
#import <Growl/Growl.h>

#include <arpa/inet.h>



@interface MTTiVoManager ()

@property (retain) MTNetService *updatingTiVo;
@property (nonatomic, retain) NSArray *hostAddresses;

@end


@implementation MTTiVoManager

@synthesize subscribedShows = _subscribedShows, numEncoders, numCommercials, tiVoList = _tiVoList;

__DDLOGHERE__

#pragma mark - Singleton Support Routines

static MTTiVoManager *sharedTiVoManager = nil;

+ (MTTiVoManager *)sharedTiVoManager {
    if (sharedTiVoManager == nil) {
        sharedTiVoManager = [[super allocWithZone:NULL] init];
        [sharedTiVoManager setupNotifications];
    }
    
    return sharedTiVoManager;
}

// We don't want to allocate a new instance, so return the current one.
+ (id)allocWithZone:(NSZone*)zone {
    return [[self sharedTiVoManager] retain];
}

// Equally, we don't want to generate multiple copies of the singleton.
- (id)copyWithZone:(NSZone *)zone {
    return self;
}

// Once again - do nothing, as we don't have a retain counter for this object.
//- (id)retain {
//    return self;
//}

//// Replace the retain counter so we can never release this object.
//- (NSUInteger)retainCount {
//    return NSUIntegerMax;
//}
//
//// This function is empty, as we don't want to let the user release this object.
//- (oneway void)release {
//    
//}
//
////Do nothing, other than return the shared instance - as this is expected from autorelease.
//- (id)autorelease {
//    return self;
//}
//

-(id)init
{
	self = [super init];
	if (self) {
		DDLogDetail(@"setting up TivoManager");
		NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
		_tivoServices = [NSMutableArray new];
		listingData = [NSMutableData new];
		_tiVoList = [NSMutableArray new];
		queue = [NSOperationQueue new];
		_downloadQueue = [NSMutableArray new];
        
        [self loadManualTiVos];
        [self searchForBonjourTiVos];

		NSString *formatListPath = [[NSBundle mainBundle] pathForResource:@"formats" ofType:@"plist"];
		NSDictionary *formats = [NSDictionary dictionaryWithContentsOfFile:formatListPath];
		_formatList = [NSMutableArray arrayWithArray:[formats objectForKey:@"formats"]];
		NSMutableArray *tmpArray = [NSMutableArray array];
		for (NSDictionary *fl in _formatList) {
			MTFormat *thisFormat = [MTFormat formatWithDictionary:fl];
			thisFormat.isFactoryFormat = [NSNumber numberWithBool:YES];
			[tmpArray addObject:thisFormat];
		}
		factoryFormatList = [tmpArray copy];
		_formatList = [tmpArray retain];
        DDLogVerbose(@"factory Formats: %@", factoryFormatList);
		
        //Set user desired hiding of the user pref, if any
        
        NSArray *hiddenFormatNames = [defaults objectForKey:kMTHiddenFormats];
        if (hiddenFormatNames) {
            //Un hide all 
            DDLogVerbose(@"Hiding formats: %@", hiddenFormatNames);
			for (MTFormat *f in _formatList) {
                f.isHidden = [NSNumber numberWithBool:NO];
            }
            //Hide what the user wants
            for (NSString *name in hiddenFormatNames) {
                MTFormat *f = [self findFormat:name];
                f.isHidden = [NSNumber numberWithBool:YES];
            }
        }
		
		//Load user formats from preferences if any
		NSArray *userFormats = [[NSUserDefaults standardUserDefaults] arrayForKey:kMTFormats];
		if (userFormats) {
			DDLogVerbose(@"User formats: %@", userFormats);
			for (NSDictionary *fl in userFormats) {
				[_formatList addObject:[MTFormat formatWithDictionary:fl]];
			}
		}
		
		//Make sure there's a selected format, espeically on first launch
		
		_selectedFormat = nil;
        if (![defaults objectForKey:kMTSelectedFormat]) {
            //What? No previous format,must be our first run. Let's see if there's any iTivo prefs.
            [MTiTiVoImport checkForiTiVoPrefs];
        }

		if ([defaults objectForKey:kMTSelectedFormat]) {
			NSString *formatName = [defaults objectForKey:kMTSelectedFormat];
			self.selectedFormat = [self findFormat:formatName];
			DDLogVerbose(@"defaultFormat %@", formatName);
		}
        
		//If no selected format make it the first.
		if (!_selectedFormat) {
			self.selectedFormat = [_formatList objectAtIndex:0];
		}
		
		if (![defaults objectForKey:kMTMediaKeys]) {
			[defaults setObject:[NSDictionary dictionary] forKey:kMTMediaKeys];
		}
		
		self.downloadDirectory  = [defaults objectForKey:kMTDownloadDirectory];
		DDLogVerbose(@"downloadDirectory %@", self.downloadDirectory);
		

		programEncoding = nil;
		programDecrypting = nil;
		programDownloading = nil;
		downloadURLConnection = nil;
		programListURLConnection = nil;
        _hostAddresses = nil;
		downloadFile = nil;
		decryptingTask = nil;
		encodingTask = nil;
		stdOutFileHandle = nil;
		tivoConnectingTo = nil;
		decryptTableCell = nil;
		downloadTableCell = nil;
		encodeTableCell = nil;
		
		numEncoders = 0;
		numCommercials = 0;
		queue.maxConcurrentOperationCount = 1;
		
		_videoListNeedsFilling = YES;
        updatingVideoList = NO;
		_processingPaused = @(NO);
		self.quitWhenCurrentDownloadsComplete = @(NO);
		
		[self loadGrowl];
//		NSLog(@"Getting Host Addresses");
//		hostAddresses = [[[NSHost currentHost] addresses] retain];
//        NSLog(@"Host Addresses = %@",self.hostAddresses);
//        NSLog(@"Host Names = %@",[[NSHost currentHost] names]);
//        NSLog(@"Host addresses for first name %@",[[NSHost hostWithName:[[NSHost currentHost] names][0]] addresses]);
        
	}
	return self;
}

-(void) restoreOldQueue {
	
	NSArray *oldQueue = [[NSUserDefaults standardUserDefaults] objectForKey:kMTQueue];
	DDLogMajor(@"Restoring old Queue(%ld elements)",oldQueue.count);
	
	NSMutableArray * newShows = [NSMutableArray arrayWithCapacity:oldQueue.count];
	for (NSDictionary * queueEntry in oldQueue) {
		DDLogDetail(@"Restoring show %@",queueEntry[kMTQueueTitle]);
		MTTiVoShow * newShow = [[[MTTiVoShow alloc] init] autorelease];
		[newShow prepareForDownload:NO];
		[newShow restoreDownloadData:queueEntry];
		[newShows addObject:newShow];
	}
	DDLogVerbose(@"Restored downloadQueue: %@",newShows);
	self.downloadQueue = newShows;

}

-(NSInteger) findProxyShowInDLQueue:(MTTiVoShow *) showTarget {
	NSString * targetTivoName = showTarget.tiVo.tiVo.name;
	return [self.downloadQueue indexOfObjectPassingTest:^BOOL(id obj, NSUInteger idx, BOOL *stop) {
		MTTiVoShow * possShow = (MTTiVoShow *) obj;
		return [targetTivoName isEqualToString:[possShow tempTiVoName]] &&
		showTarget.showID == possShow.showID;
		
	}];
}

-(void) checkProxyInQueue: (MTTiVoShow *) newShow {
	NSInteger DLIndex =[tiVoManager findProxyShowInDLQueue:newShow];
	if (DLIndex != NSNotFound) {
		MTTiVoShow * proxyShow = [tiVoManager downloadQueue][DLIndex];
		DDLogVerbose(@"Found proxy %@ at %ld on tiVo %@",newShow, DLIndex, proxyShow.tiVoName);
		[newShow updateFromProxyShow:proxyShow];
		[[tiVoManager downloadQueue] replaceObjectAtIndex:DLIndex withObject:newShow];
	} else {
		DDLogVerbose(@"Didn't find DL proxy for %@",newShow);
	}
}

-(void)checkDownloadQueueForDeletedEntries: (MTTiVo *) tiVo {
	NSString *targetTivoName = tiVo.tiVo.name;
	for (MTTiVoShow * show in self.downloadQueue) {
		if(show.protectedShow.boolValue &&
		   [targetTivoName isEqualToString:show.tiVoName]) {
			DDLogDetail(@"Marking %@ as deleted", show.showTitle);
			show.downloadStatus =@kMTStatusDeleted;
			show.protectedShow = @NO; //let them delete from queue
		}
	}

}


#pragma mark - TiVo Search Methods

-(void)loadManualTiVos
{
//    BOOL didFindTiVo = NO;
	DDLogDetail(@"LoadingTivos");
	NSMutableArray *bonjourTiVoList = [NSMutableArray arrayWithArray:[_tiVoList filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"manualTiVo == NO"]]];
	NSMutableArray *manualTiVoList = [NSMutableArray arrayWithArray:[_tiVoList filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"manualTiVo == YES"]]];
//	[_tiVoList removeObjectsInArray:manualTiVoList];
	
	NSArray *manualTiVoDescriptions = [self getManualTiVoDescriptions];
	
	//Update rebuild manualTiVoList reusing what can be reused.
	NSMutableArray *newManualTiVoList = [NSMutableArray array];
    for (NSDictionary *manualTiVoDescription in manualTiVoDescriptions) {
		if ([manualTiVoDescription[@"enabled"] boolValue]) {
			//Check for exisitng
			MTNetService *newTiVoService = nil;
			MTTiVo *newTiVo = nil;
			for (MTTiVo *tivo in manualTiVoList) {
				if ([tivo.tiVo.iPAddress compare:manualTiVoDescription[@"iPAddress"]] == NSOrderedSame) {
					DDLogDetail(@"Already have manual TiVo %@ - Updating values", tivo);
					newTiVo = tivo;
					newTiVo.tiVo.userName = manualTiVoDescription[@"userName"];
					newTiVo.tiVo.userPort = [manualTiVoDescription[@"userPort"] integerValue];
					newTiVo.tiVo.userPortSSL = [manualTiVoDescription[@"userPortSSL"] integerValue];
					newTiVo.enabled = [manualTiVoDescription[@"enabled"] boolValue];
					break;
				}
			}
			if (!newTiVo) {
				newTiVoService = [[[MTNetService alloc] init] autorelease];
				newTiVoService.userName = manualTiVoDescription[@"userName"];
				newTiVoService.iPAddress = manualTiVoDescription[@"iPAddress"];
				newTiVoService.userPort = [manualTiVoDescription[@"userPort"] integerValue];
				newTiVoService.userPortSSL = [manualTiVoDescription[@"userPortSSL"] integerValue];
				newTiVo = [MTTiVo tiVoWithTiVo:newTiVoService withOperationQueue:queue];
				newTiVo.manualTiVo = YES;
				newTiVo.enabled = [manualTiVoDescription[@"enabled"] boolValue];
				DDLogDetail(@"Adding new manual TiVo %@",newTiVo);
			}
			//Remove any matching ip address already in bonjour list
			NSMutableArray *itemsToRemove = [NSMutableArray array];
			for (MTTiVo *tiVo in bonjourTiVoList) {
				NSString *ipaddr = [self getStringFromAddressData:[tiVo.tiVo addresses][0]];
				if ([ipaddr compare:newTiVo.tiVo.iPAddress] == NSOrderedSame) {
					[itemsToRemove addObject:tiVo];
					DDLogDetail(@"Already had %@ at %@", tiVo, ipaddr);
				}
			}
			[bonjourTiVoList removeObjectsInArray:itemsToRemove];
			for (MTTiVo *tiVo in itemsToRemove) { //Deactive those we are removing
				[[NSNotificationCenter defaultCenter] removeObserver:tiVo];
				[NSObject cancelPreviousPerformRequestsWithTarget:tiVo];
			}
			[newManualTiVoList addObject:newTiVo];
//			if (itemsToRemove.count) {
//				[[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationTiVoShowsUpdated object:nil];
//			}
//			for (MTTiVo *tiVo in itemsToRemove) {
//				[[NSNotificationCenter defaultCenter] removeObserver:tiVo];
//				[NSObject cancelPreviousPerformRequestsWithTarget:tiVo];
//			}
//			didFindTiVo = YES;
		}
    }
	for (MTTiVo *tiVo in manualTiVoList) { //Deactivate those that are NOT in the newManualTiVoList
		if ([newManualTiVoList indexOfObject:tiVo] == NSNotFound) {
			[[NSNotificationCenter defaultCenter] removeObserver:tiVo];
			[NSObject cancelPreviousPerformRequestsWithTarget:tiVo];
		}
	}
	//Re build _tivoList
	[bonjourTiVoList addObjectsFromArray:newManualTiVoList];
	self.tiVoList = bonjourTiVoList;
	NSNotification *notification = [NSNotification notificationWithName:kMTNotificationTiVoListUpdated object:nil];
	[[NSNotificationCenter defaultCenter] performSelectorOnMainThread:@selector(postNotification:) withObject:notification waitUntilDone:NO];
	if (tivoBrowser) {
		DDLogDetail(@"Reloading bonjour tivos with tivoBrowser %@", tivoBrowser);
		[tivoBrowser stop];
		[_tivoServices removeAllObjects];
		[tivoBrowser searchForServicesOfType:@"_tivo-videos._tcp" inDomain:@"local"];
	}
}


//Found issues with corrupt, or manually edited entries in the manual array so use this to remove them
-(NSArray *)getManualTiVoDescriptions
{
	NSMutableArray *manualTiVoDescriptions = [NSMutableArray arrayWithArray:[[NSUserDefaults standardUserDefaults] arrayForKey:kMTManualTiVos]];
	NSMutableArray *itemsToRemove = [NSMutableArray array];
    for (NSDictionary *manualTiVoDescription in manualTiVoDescriptions) {
		if (manualTiVoDescription.count != 5 ||
			((NSString *)manualTiVoDescription[@"userName"]).length == 0 ||
			((NSString *)manualTiVoDescription[@"iPAddress"]).length == 0) {
			[itemsToRemove addObject:manualTiVoDescription];
			continue;
		}
	}
	if (itemsToRemove.count) {
		DDLogMajor(@"Removing manual Tivos %@", itemsToRemove);
		[manualTiVoDescriptions removeObjectsInArray:itemsToRemove];
		[[NSUserDefaults standardUserDefaults] setObject:manualTiVoDescriptions forKey:kMTManualTiVos];
	}
	return [NSArray arrayWithArray:manualTiVoDescriptions];
}


-(void)searchForBonjourTiVos
{
	DDLogDetail(@"searching for Bonjour");
    tivoBrowser = [NSNetServiceBrowser new];
    tivoBrowser.delegate = self;
    [tivoBrowser scheduleInRunLoop:[NSRunLoop mainRunLoop] forMode:NSDefaultRunLoopMode];
    [tivoBrowser searchForServicesOfType:@"_tivo-videos._tcp" inDomain:@"local"];
}

-(NSArray *)hostAddresses
{
    NSArray *ret = _hostAddresses;
    if (!_hostAddresses) {
        self.hostAddresses = [[NSHost currentHost] addresses];
		DDLogDetail(@"Host Addresses:  %@",self.hostAddresses);
        ret = _hostAddresses;
    }
    return ret;
}

-(NSArray *)tiVoAddresses
{
    NSMutableArray *addresses = [NSMutableArray array];
    for (MTTiVo *tiVo in _tiVoList) {
        if ([tiVo.tiVo addresses] && [tiVo.tiVo addresses].count) {
            NSString *ipAddress = [self getStringFromAddressData:[tiVo.tiVo addresses][0]];
            [addresses addObject:ipAddress];
        }
    }
	DDLogVerbose(@"Tivo Addresses:  %@",addresses);
    return addresses;
}

-(NSArray *)tiVoList {
	return _tiVoList;
}

-(void) setTiVoList: (NSArray *) tiVoList {
	if (_tiVoList != tiVoList) {
		[_tiVoList release];
		NSSortDescriptor *manualSort = [NSSortDescriptor sortDescriptorWithKey:@"manualTiVo" ascending:NO];
		NSSortDescriptor *nameSort = [NSSortDescriptor sortDescriptorWithKey:@"tiVo.name" ascending:YES];
		_tiVoList = [[tiVoList sortedArrayUsingDescriptors:[NSArray arrayWithObjects:manualSort,nameSort, nil]] retain];
		DDLogVerbose(@"resorting TiVoList %@", _tiVoList);
	}
}

-(void) setupNotifications {
    //have to wait until tivomanager is setup before calling subsidiary data models
	[self restoreOldQueue];
	
	DDLogVerbose(@"setting tivoManager notifications");
    NSNotificationCenter *defaultCenter = [NSNotificationCenter defaultCenter];
    
    [defaultCenter addObserver:self selector:@selector(encodeFinished) name:kMTNotificationEncodeDidFinish object:nil];
    [defaultCenter addObserver:self selector:@selector(encodeFinished) name:kMTNotificationEncodeWasCanceled object:nil];
    [defaultCenter addObserver:self selector:@selector(commercialFinished) name:kMTNotificationCommercialDidFinish object:nil];
    [defaultCenter addObserver:self selector:@selector(commercialFinished) name:kMTNotificationCommercialWasCanceled object:nil];
    [defaultCenter addObserver:self.subscribedShows selector:@selector(checkSubscription:) name: kMTNotificationDetailsLoaded object:nil];
    [defaultCenter addObserver:self.subscribedShows selector:@selector(updateSubscriptionWithDate:) name:kMTNotificationEncodeDidFinish object:nil];
    
	[[NSUserDefaults standardUserDefaults] addObserver:self forKeyPath:kMTQueuePaused options:NSKeyValueObservingOptionNew context:nil];
	[[NSUserDefaults standardUserDefaults] addObserver:self forKeyPath:kMTScheduledOperations options:NSKeyValueObservingOptionNew context:nil];
	[[NSUserDefaults standardUserDefaults] addObserver:self forKeyPath:kMTScheduledEndTime options:NSKeyValueObservingOptionNew context:nil];
	[[NSUserDefaults standardUserDefaults] addObserver:self forKeyPath:kMTScheduledStartTime options:NSKeyValueObservingOptionNew context:nil];
}

#pragma mark - Scheduling routine

-(void)determineCurrentProcessingState
{
	int secondsInADay = 3600 * 24;
	double currentSeconds = (int)[[NSDate date] timeIntervalSince1970] % secondsInADay;

	NSDate *startTime = [[NSUserDefaults standardUserDefaults] objectForKey:kMTScheduledStartTime];
	double startTimeSeconds = (int)[startTime timeIntervalSince1970] % secondsInADay;
	NSDate *endTime = [[NSUserDefaults standardUserDefaults] objectForKey:kMTScheduledEndTime];
	double endTimeSeconds = (int)[endTime timeIntervalSince1970] % secondsInADay;
	if (endTimeSeconds < startTimeSeconds) {
		endTimeSeconds += (double)secondsInADay;
	}
	BOOL schedulingActive = [[NSUserDefaults standardUserDefaults] boolForKey:kMTScheduledOperations];
	if ((startTimeSeconds > currentSeconds || currentSeconds > endTimeSeconds) && schedulingActive) { //We're NOT active
		[self setValue:@(YES) forKey:@"processingPaused"];
	} else {
		[self setValue:@(NO) forKey:@"processingPaused"];
	}
	
}

-(BOOL) anyTivoActive {
	for (MTTiVo *tiVo in _tiVoList) {
		if ([tiVo isProcessing]) {
			return YES;
		}
	}
	return NO;
}

-(void)pauseQueue:(NSNumber *)askUser
{
	self.processingPaused = @(YES);
//	return;
	if ([self anyTivoActive] && [askUser boolValue]) {
		NSAlert *scheduleAlert = [NSAlert alertWithMessageText:@"There are shows in process, and you are setting a scheduled time to start.  Should the current shows in process be rescheduled?" defaultButton:@"Reschedule" alternateButton:@"Complete stage of current shows" otherButton:nil informativeTextWithFormat:@""];
		NSInteger returnValue = [scheduleAlert runModal];
		DDLogDetail(@"User said %ld to cancel alert",returnValue);
		if (returnValue == 1) {
			//We're rescheduling shows
			for (MTTiVo *tiVo in _tiVoList) {
				[tiVo rescheduleAllShows];
			}
		}
	}
	[self configureSchedule];
}

-(void)unPauseQueue
{
	self.processingPaused = @(NO);
//	return;
	[self startAllTiVoQueues];
	[self configureSchedule];
}

-(void)configureSchedule
{
	[self setQueueStartTime];
	[self setQueueEndTime];
}

-(double) secondsUntilNextTimeOfDay:(NSDate *) date {
	//find the next timeOfDay that the timeOfDay represented by date will occur (could be a category on NSDate)
	const int secondsInADay = 3600 * 24;
	double now = [[NSDate date] timeIntervalSince1970];
	double currentSecondsOfToday = (int)now % secondsInADay;
	double secondsAtStartOfDay = now - currentSecondsOfToday;
	double startTimeOfDayinSeconds = (int)[date timeIntervalSince1970] % secondsInADay;
	//now advance it to a time after now
	while (startTimeOfDayinSeconds <= currentSecondsOfToday) startTimeOfDayinSeconds += (double) secondsInADay;
	return secondsAtStartOfDay + startTimeOfDayinSeconds - now;
}

-(void)setQueueStartTime
{
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(unPauseQueue) object:nil];
	if (![[NSUserDefaults standardUserDefaults] boolForKey:kMTScheduledOperations]) return;
	NSDate* startDate = [[NSUserDefaults standardUserDefaults] objectForKey:kMTScheduledStartTime];
	double targetSeconds = [self secondsUntilNextTimeOfDay:startDate];
	DDLogDetail(@"Will start queue in %f seconds, due to beginDate of %@",targetSeconds, startDate);
	[self performSelector:@selector(unPauseQueue) withObject:nil afterDelay:targetSeconds];
}

-(void)setQueueEndTime
{
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(pauseQueue:) object:@(NO)];
	if (![[NSUserDefaults standardUserDefaults] boolForKey:kMTScheduledOperations]) return;
	NSDate * endDate = [[NSUserDefaults standardUserDefaults] objectForKey:kMTScheduledEndTime];
	double targetSeconds = [self secondsUntilNextTimeOfDay:endDate];
	DDLogDetail(@"Will pause queue in %f seconds, due to endDate of %@",targetSeconds, endDate);
	[self performSelector:@selector(pauseQueue:) withObject:@(NO) afterDelay:targetSeconds];
}

-(void)startAllTiVoQueues
{
    for (MTTiVo *tiVo in _tiVoList) {
        DDLogDetail(@"Starting download on tiVo %@",tiVo.tiVo.name);
        [tiVo manageDownloads:tiVo];
    }
}

#pragma mark - Key Value Observing

-(void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
	if ([keyPath compare:kMTQueuePaused] == NSOrderedSame) {
		if ([[NSUserDefaults standardUserDefaults] boolForKey:kMTQueuePaused]) {
			[self pauseQueue:@(YES)];
		} else {
			[self unPauseQueue];
		}
	}
	if ([keyPath compare:kMTScheduledOperations] == NSOrderedSame) {
		[self configureSchedule];
	}
	if ([keyPath compare:kMTScheduledEndTime] == NSOrderedSame) {
		[self configureSchedule];
	}
	if ([keyPath compare:kMTScheduledStartTime] == NSOrderedSame) {
		[self configureSchedule];
	}
}

-(void)refreshAllTiVos
{
	DDLogMajor(@"Refreshing all Tivos");
	for (MTTiVo *tiVo in _tiVoList) {
		if (tiVo.isReachable) {
			[tiVo updateShows:nil];
		}
	}
}


-(NSMutableArray *) subscribedShows {
    
	if (_subscribedShows ==  nil) {

            _subscribedShows = [NSMutableArray new];
        [_subscribedShows loadSubscriptions];
		DDLogVerbose(@"Loaded subscriptions: %@", _subscribedShows);
	}
 
	return _subscribedShows;
}

#pragma mark - Format Handling

-(NSArray *)userFormatDictionaries
{
	NSMutableArray *tmpArray = [NSMutableArray array];
	for (MTFormat *f in self.userFormats) {
		[tmpArray addObject:[f toDictionary]];
	}
	return [NSArray arrayWithArray:tmpArray];
}

-(NSArray *)userFormats
{
    NSMutableArray *tmpFormats = [NSMutableArray arrayWithArray:_formatList];
    [tmpFormats filterUsingPredicate:[NSPredicate predicateWithFormat:@"isFactoryFormat == %@",[NSNumber numberWithBool:NO]]];
    return [NSArray arrayWithArray:tmpFormats];
}

-(NSArray *)hiddenBuiltinFormatNames
{
    NSMutableArray *tmpFormats = [NSMutableArray arrayWithArray:_formatList];
    [tmpFormats filterUsingPredicate:[NSPredicate predicateWithFormat:@"isFactoryFormat == %@ && isHidden == %@",[NSNumber numberWithBool:YES],[NSNumber numberWithBool:YES]]];
	NSMutableArray *tmpFormatNames = [NSMutableArray array];
	for (MTFormat *f in tmpFormats) {
		[tmpFormatNames addObject:f.name];
	}
    return [NSArray arrayWithArray:tmpFormatNames];
	
}

-(void)setSelectedFormat:(MTFormat *)selectedFormat
{
    if (selectedFormat == _selectedFormat) {
        return;
    }
    [_selectedFormat release];
    _selectedFormat = [selectedFormat retain];
    [[NSUserDefaults standardUserDefaults] setObject:_selectedFormat.name forKey:kMTSelectedFormat];
}

-(MTFormat *) findFormat:(NSString *) formatName {
    for (MTFormat *fd in _formatList) {
        if ([formatName compare:fd.name] == NSOrderedSame) {
            return fd;
        }
    }
    return nil;
}

-(void)addFormatsToList:(NSArray *)formats
{
	for (NSDictionary *f in formats) {
		MTFormat *newFormat = [MTFormat formatWithDictionary:f];
		//Lots of error checking here
        //Check that name is unique
        [newFormat checkAndUpdateFormatName:tiVoManager.formatList];
		[_formatList addObject:newFormat];
	}
	[[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationFormatListUpdated object:nil];
}


#pragma mark - Media Key Support

-(NSDictionary *)currentMediaKeys
{
	NSMutableDictionary *tmpDict = [NSMutableDictionary dictionary];
	for (MTTiVo *thisTiVo in _tiVoList) {
		[tmpDict setObject:thisTiVo.mediaKey forKey:thisTiVo.tiVo.name];
	}
	return [NSDictionary dictionaryWithDictionary:tmpDict];
}

-(void)updateMediaKeysDefaults
{
	NSMutableDictionary *tmpDict = [NSMutableDictionary dictionary];
	for (MTTiVo *tiVo in _tiVoList) {
		[tmpDict setValue:tiVo.mediaKey forKey:tiVo.tiVo.name];
	}
	[[NSUserDefaults standardUserDefaults] setValue:tmpDict forKey:kMTMediaKeys];
}

#pragma mark - Download Management

-(void)checkShowTitleUniqueness:(MTTiVoShow *)program
{
    //Make sure the title isn't the same and if it is add a -1 modifier
    for (MTTiVoShow *p in _downloadQueue) {
        if ([p.showTitle compare:program.showTitle] == NSOrderedSame) {
			NSRegularExpression *ending = [NSRegularExpression regularExpressionWithPattern:@"(.*)-([0-9]+)$" options:NSRegularExpressionCaseInsensitive error:nil];
            NSTextCheckingResult *result = [ending firstMatchInString:program.showTitle options:NSMatchingWithoutAnchoringBounds range:NSMakeRange(0, program.showTitle.length)];
            if (result) {
                int n = [[program.showTitle substringWithRange:[result rangeAtIndex:2]] intValue];
				DDLogVerbose(@"found show title %@, incrementing version number %d", program.showTitle, n);
				program.showTitle = [[program.showTitle substringWithRange:[result rangeAtIndex:1]] stringByAppendingFormat:@"-%d",n+1];
           } else {
                program.showTitle = [program.showTitle stringByAppendingString:@"-1"];
			   DDLogDetail(@"found show title %@, adding version number", program.showTitle);
            }
            [self checkShowTitleUniqueness:program];
        }
    }

}
-(NSIndexSet *) moveShowsInDownloadQueue:(NSArray *) shows
								 toIndex:(NSUInteger)insertIndex
{
	DDLogDetail(@"moving shows %@ to %ld", shows,insertIndex);
	NSIndexSet * fromIndexSet = [[tiVoManager downloadQueue] indexesOfObjectsPassingTest:
								 ^BOOL(id obj, NSUInteger idx, BOOL *stop) {
									return [shows indexOfObject:obj] != NSNotFound;
								 }];
	if (fromIndexSet.count ==0) return nil;
	
	// If any of the removed objects come before the insertion index,
	// we need to decrement the index appropriately
	NSMutableArray * dlQueue = [self downloadQueue];
	NSUInteger adjustedInsertIndex = insertIndex -
	[fromIndexSet countOfIndexesInRange:(NSRange){0, insertIndex}];
	NSRange destinationRange = NSMakeRange(adjustedInsertIndex, [fromIndexSet count]);
	NSIndexSet *destinationIndexes = [NSIndexSet indexSetWithIndexesInRange:destinationRange];
	
	NSArray *objectsToMove = [dlQueue objectsAtIndexes:fromIndexSet];
	DDLogVerbose(@"moving shows %@ from %@ to %@", objectsToMove,fromIndexSet, destinationIndexes);
	[dlQueue removeObjectsAtIndexes: fromIndexSet];
	[dlQueue insertObjects:objectsToMove atIndexes:destinationIndexes];
	DDLogDetail(@"Posting DLUpdated notifications");
	[[NSNotificationCenter defaultCenter ] postNotificationName:  kMTNotificationDownloadQueueUpdated object:nil];
	return destinationIndexes;
}

-(void) sortDownloadQueue {

	[self.downloadQueue sortUsingComparator:^NSComparisonResult(MTTiVoShow * show1, MTTiVoShow* show2) {
		int status1 = show1.downloadStatus.intValue; if (status1 > kMTStatusDone) status1= kMTStatusDone; //sort failed/done together
		int status2 = show2.downloadStatus.intValue;if (status2 > kMTStatusDone) status2= kMTStatusDone;
		return status1 > status2 ? NSOrderedAscending : status1 < status2 ? NSOrderedDescending : NSOrderedSame;
		
	}];
}

-(void)addProgramToDownloadQueue:(MTTiVoShow *) program {
	[self addProgramsToDownloadQueue:[NSArray arrayWithObject:program] beforeShow:nil];
}

-(void)addProgramsToDownloadQueue:(NSArray *)programs beforeShow:(MTTiVoShow *) nextShow {
	BOOL submittedAny = NO;
	for (MTTiVoShow *program in programs){
		if (![program.protectedShow boolValue]) {
            BOOL programFound = NO;
            for (MTTiVoShow *p in _downloadQueue) {
                if (p.showID == program.showID	) {
					if (p==program) {
						DDLogDetail(@" %@ already in queue",p);
					} else {
						DDLogReport(@"program %@ already in queue as %@ with same ID %d!",p, program, p.showID);
					}
					programFound = YES;
					break;
                }
            }
            
            if (!programFound) {
                //Make sure the title isn't the same and if it is add a -1 modifier
                submittedAny = YES;
                [self checkShowTitleUniqueness:program];
				[program prepareForDownload:NO];
				if (nextShow) {
                    NSUInteger index = [_downloadQueue indexOfObject:nextShow];
                    if (index == NSNotFound) {
						DDLogDetail(@"Prev show not found, adding %@ at end",program);
						[_downloadQueue addObject:program];
                        
                    } else {
						DDLogVerbose(@"inserting before %@ at %ld",nextShow, index);
                        [_downloadQueue insertObject:program atIndex:index];
                    }
                } else {
					DDLogVerbose(@"adding %@ at end",program);
                   [_downloadQueue addObject:program];
                }
            }
        }
	}
	if (submittedAny){
		DDLogDetail(@"Posting showsUpdated notifications");
		[[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationTiVoShowsUpdated object:nil];
        [[NSNotificationCenter defaultCenter ] postNotificationName:  kMTNotificationDownloadQueueUpdated object:nil];
	}
}


-(void) downloadShowsWithCurrentOptions:(NSArray *) shows beforeShow:(MTTiVoShow *) nextShow {
	for (MTTiVoShow * thisShow in shows) {
		DDLogDetail(@"Adding show: %@", thisShow);
		thisShow.encodeFormat = [self selectedFormat];
		thisShow.addToiTunesWhenEncoded = thisShow.encodeFormat.canAddToiTunes &&
											[[NSUserDefaults standardUserDefaults] boolForKey:kMTiTunesSubmit];
		thisShow.simultaneousEncode = thisShow.encodeFormat.canSimulEncode &&
											[[NSUserDefaults standardUserDefaults] boolForKey:kMTSimultaneousEncode];
		thisShow.skipCommercials = [thisShow.encodeFormat.comSkip boolValue] &&
											[[NSUserDefaults standardUserDefaults] boolForKey:@"RunComSkip"];
		thisShow.downloadDirectory = tiVoManager.downloadDirectory;
	}
	[self addProgramsToDownloadQueue:shows beforeShow:nextShow ];
}

-(void) deleteProgramsFromDownloadQueue:(NSArray *) programs {
    NSMutableIndexSet * itemsToRemove= [NSMutableIndexSet indexSet];
	DDLogDetail(@"Delete shows: %@", programs);
	for (MTTiVoShow * program in programs) {

		NSUInteger index = [_downloadQueue indexOfObject:program];
		if (index == NSNotFound) {
			for (MTTiVoShow *p in _downloadQueue) {  //this is probably unncessary
				if (p.showID == program.showID	) {
					DDLogMajor(@"Odd: two shows with same ID: %@ in queue v %@", program, p);
					index = [_downloadQueue indexOfObject:p];
					break;
				}
			}
		}
		if (index != NSNotFound) {
			MTTiVoShow *p = _downloadQueue[index];
			[p cancel];
			p.isQueued = NO;
			[itemsToRemove addIndex:index];
		}
	}
	
	if (itemsToRemove.count > 0) {
		DDLogVerbose(@"Deleted shows: %@", itemsToRemove);
		[_downloadQueue removeObjectsAtIndexes:itemsToRemove];
		[[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationTiVoShowsUpdated object:nil];
		[[NSNotificationCenter defaultCenter ] postNotificationName:  kMTNotificationDownloadStatusChanged object:nil];
		NSNotification *downloadQueueNotification = [NSNotification notificationWithName:kMTNotificationDownloadQueueUpdated object:nil];
		[[NSNotificationCenter defaultCenter] performSelector:@selector(postNotification:) withObject:downloadQueueNotification afterDelay:4.0];
	} else {
		DDLogDetail(@"No shows to delete?");

	}
}

-(NSInteger)numberOfShowsToDownload
{
	NSInteger n= 0;
	for (MTTiVoShow *show in _downloadQueue) {
		if (!show.isDone) {
			n++;
		}
	}
	return n;
}

#pragma mark Growl/Apple Notifications

-(void) loadGrowl {
	
	if(NSAppKitVersionNumber >= NSAppKitVersionNumber10_6) {
		NSBundle *myBundle = [NSBundle mainBundle];
		NSString *growlPath = [[myBundle privateFrameworksPath] stringByAppendingPathComponent:@"Growl.framework"];
		NSBundle *growlFramework = [NSBundle bundleWithPath:growlPath];
		
		if (growlFramework && [growlFramework load]) {
			// Register ourselves as a Growl delegate
			
			NSDictionary *infoDictionary = [growlFramework infoDictionary];
			DDLogMajor(@"Using Growl.framework %@ (%@)",
				  [infoDictionary objectForKey:@"CFBundleShortVersionString"],
				  [infoDictionary objectForKey:(NSString *)kCFBundleVersionKey]);
			
			Class GAB = NSClassFromString(@"GrowlApplicationBridge");
			if([GAB respondsToSelector:@selector(setGrowlDelegate:)]) {
				[GAB performSelector:@selector(setGrowlDelegate:) withObject:self];
			}
		}
	}
}
//Note that any new notification types need to be added to constants.h, but especially Growl Registration Ticket.growRegDict
- (void)notifyWithTitle:(NSString *) title subTitle: (NSString*) subTitle forNotification: (NSString *) notification {
	DDLogMajor(@"Growl: %@/%@: %@", title, subTitle, notification);
	Class GAB = NSClassFromString(@"GrowlApplicationBridge");
	if([GAB respondsToSelector:@selector(notifyWithTitle:description:notificationName:iconData:priority:isSticky:clickContext:identifier:)])
		[GAB notifyWithTitle: title
				 description: subTitle
			notificationName: notification
					iconData: nil  //use our app logo
					priority: 0
					isSticky: NO
				clickContext: nil
		 ];
	
}

-(MTTiVoShow *) findRealShow:(MTTiVoShow *) showTarget {
	if (showTarget.tiVo) {
		for (MTTiVoShow * show in showTarget.tiVo.shows)  {
			if (show.showID == showTarget.showID) {
				return show;
			}
		}
	}
	return nil;
}


#pragma mark - Download Support for Tivos and Shows

-(int)totalShows
{
    int total = 0;
    for (MTTiVo *tiVo in _tiVoList) {
        total += tiVo.shows.count;
    }
    return total;
}

-(BOOL)foundTiVoNamed:(NSString *)tiVoName
{
	BOOL ret = NO;
	for (MTTiVo *tiVo in _tiVoList) {
		if ([tiVo.tiVo.name compare:tiVoName] == NSOrderedSame) {
			ret = YES;
			break;
		}
	}
	return ret;
}

-(NSArray *)downloadQueueForTiVo:(MTTiVo *)tiVo
{
//    return [_downloadQueue filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"tiVo.tiVo.name == %@",tiVo.tiVo.name]];
    return [_downloadQueue filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"tiVoName == %@",tiVo.tiVo.name]];
}


-(void)encodeFinished
{
	numEncoders--;
	if ([_quitWhenCurrentDownloadsComplete boolValue] && ![self tiVosProcessing]) {
		//Quit here
		[NSApp terminate:nil];
	}
    [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationDownloadQueueUpdated object:nil];
    DDLogMajor(@"num decoders after decrement is %d",numEncoders);
}

-(BOOL)tiVosProcessing
{
	BOOL returnValue = NO;
	for (MTTiVo *tiVo in _tiVoList) {
		if (tiVo.isProcessing) {
			returnValue = YES;
			break;
		}
	}
	return returnValue;
}

-(void)commercialFinished
{
	numCommercials--;
    [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationDownloadQueueUpdated object:nil];
    DDLogMajor(@"num commercials after decrement is %d",numCommercials);
}

-(void)writeDownloadQueueToUserDefaults {
	NSMutableArray * downloadArray = [NSMutableArray arrayWithCapacity:_downloadQueue.count];
	for (MTTiVoShow * show in _downloadQueue) {
		if (show.isInProgress){
			[show cancel];	
		}
		[downloadArray addObject:[show queueRecord]];
								
	}
    DDLogVerbose(@"writing DL queue: %@", downloadArray);
	[[NSUserDefaults standardUserDefaults] setObject:downloadArray forKey:kMTQueue];
}

#pragma mark - Handle directory

-(BOOL) checkDirectory: (NSString *) directory {
	return ([[NSFileManager defaultManager]	createDirectoryAtPath:[directory stringByExpandingTildeInPath]
										  withIntermediateDirectories:YES
														   attributes:nil
																error:nil]);
}

-(void) setDownloadDirectory: (NSString *) newDir {
	if (newDir != _downloadDirectory) {
		[_downloadDirectory release];
		
		if (newDir.length > 0) {
			if (![self checkDirectory:newDir]) {
				DDLogReport(@"Can't open user's download directory %@; trying default", newDir);
				newDir = nil;
			}
		}
		if (!newDir) {
			// nil, or it was bad
			newDir = [self defaultDownloadDirectory];
			
			if (![self checkDirectory:newDir]) {
				DDLogReport(@"Can't open default download directory:  %@ ", newDir); //whoa. very bad things in user directory land
				newDir = nil;
			}
		}
		if (newDir) {
			[[NSUserDefaults standardUserDefaults] setValue:newDir forKey:kMTDownloadDirectory];
			_downloadDirectory = [newDir retain];
		}
	}
}

-(NSString *) defaultDownloadDirectory {
	return [NSString stringWithFormat:@"%@/%@/",NSHomeDirectory(),kMTDefaultDownloadDir];
//note this will fail in sandboxing. Need something like...

//	if ([[NSFileManager defaultManager] respondsToSelector:@selector(URLsForDirectory:inDomains:)]) {
//		//requires 10.6
//		NSArray * movieDirs = [[NSFileManager defaultManager] URLsForDirectory:NSMoviesDirectory inDomains:NSUserDomainMask];
//		if (movieDirs.count >0) {
//			NSURL *movieURL = (NSURL *) movieDirs[0];
//			[movieURL URLByAppendingPathComponent:kMTDefaultDownloadDir].path;
//		}
//	} else { //10.5
//	return [NSString stringWithFormat:@"%@/@",NSHomeDirectory(),kMTDefaultDownloadDir]
//
//	}

}

#pragma mark - Memory Management

-(void)dealloc
{
    // I'm never called!
    [super dealloc];
}


-(NSMutableArray *)tiVoShows
{
	NSMutableArray *totalShows = [NSMutableArray array];
	DDLogVerbose(@"reloading shows");
	for (MTTiVo *tv in _tiVoList) {
		[totalShows addObjectsFromArray:tv.shows];
	}
	return totalShows;
}


#pragma mark - Bonjour browser delegate methods

- (void)netServiceBrowser:(NSNetServiceBrowser *)netServiceBrowser didFindService:(NSNetService *)netService moreComing:(BOOL)moreServicesComing
{
	DDLogMajor(@"Found Service %@",netService);
    for (NSNetService * prevService in _tivoServices) {
        if ([prevService.name compare:netService.name] == NSOrderedSame) {
			DDLogDetail(@"Already had %@",netService);
            return; //already got this one
        }
    }
    [_tivoServices addObject:netService];
    netService.delegate = self;
    [netService resolveWithTimeout:6.0];
}

#pragma mark - NetService delegate methods

- (void)netServiceDidResolveAddress:(NSNetService *)sender
{
	NSString *ipAddress = @"";
	if ([sender addresses] && [sender addresses].count) {
		ipAddress = [self getStringFromAddressData:[sender addresses][0]];
		
	}
//    if (_tiVoList.count == 1) {  //Test code for single tivo testing
//        return;
//    }
	DDLogDetail(@"Checking hostAddresses for %@",ipAddress);

	for (NSString *hostAddress in self.hostAddresses) {
		if ([hostAddress caseInsensitiveCompare:ipAddress] == NSOrderedSame) {
			return;  // This filters out PyTivo instances on the current host
		}
	}

	for (NSString *tiVoAddress in [self tiVoAddresses]) {
		DDLogVerbose(@"Comparing tiVo %@ address %@ to ipaddress %@",sender.name,tiVoAddress,ipAddress);
		if ([tiVoAddress caseInsensitiveCompare:ipAddress] == NSOrderedSame) {
			return;  // This filters out tivos that have already been found from a manual entry
		}
	}
    
    if ([sender.name rangeOfString:@"Py"].location == NSNotFound) {
        MTTiVo *newTiVo = [MTTiVo tiVoWithTiVo:sender withOperationQueue:queue];
      
        self.tiVoList = [self.tiVoList arrayByAddingObject: newTiVo];
		DDLogMajor(@"Got new TiVo: %@ at %@", newTiVo, ipAddress);
        [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationTiVoListUpdated object:nil];
    } else {
		DDLogMajor(@"PyAddress: %@ not in hostAddresses = %@", ipAddress, self.hostAddresses);
    }
}

-(void)netService:(NSNetService *)sender didNotResolve:(NSDictionary *)errorDict
{
    DDLogReport(@"Service %@ failed to resolve",sender.name);
}

- (NSString *)getStringFromAddressData:(NSData *)dataIn {
    struct sockaddr_in  *socketAddress = nil;
    NSString            *ipString = nil;
	
    socketAddress = (struct sockaddr_in *)[dataIn bytes];
    ipString = [NSString stringWithFormat: @"%s",
                inet_ntoa(socketAddress->sin_addr)];  ///problem here
	DDLogVerbose(@"Translated %d to %@", socketAddress->sin_addr.s_addr, ipString);
    return ipString;
}


@end
