//
//  MTNetworkTivos.m
//  myTivo
//
//  Created by Scott Buchanan on 12/6/12.
//  Copyright (c) 2012 Scott Buchanan. All rights reserved.
//

#import "MTTiVoManager.h"
#import "MTAppDelegate.h"
#import "MTSubscription.h"
#import "MTSubscriptionList.h"
//#import "NSNotificationCenter+Threads.h"
#if MAC_OS_X_VERSION_MIN_REQUIRED < MAC_OS_X_VERSION_10_9
#import <Growl/Growl.h>
#endif
#import "NSString+Helpers.h"

#include <arpa/inet.h>



@interface MTTiVoManager ()
#if MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_9
    <NSUserNotificationCenterDelegate>  
#endif
        {

    NSNetServiceBrowser *tivoBrowser;

    int numEncoders;// numCommercials, numCaptions;//Want to limit launches to two encoders.
	
    NSMetadataQuery *cTiVoQuery;
	BOOL volatile loadingManualTiVos;

}

@property (atomic, strong)     NSOperationQueue *opsQueue;
@property (nonatomic, strong) NSMutableDictionary <NSString *, NSDictionary  *> * manualEpisodeData;
@property (nonatomic, strong) NSDictionary *showsOnDisk;

@end


@implementation MTTiVoManager

@synthesize subscribedShows = _subscribedShows, numEncoders, tiVoList = _tiVoList;

__DDLOGHERE__

#pragma mark - Singleton Support Routines

+ (MTTiVoManager *)sharedTiVoManager {
     static dispatch_once_t pred;
    static MTTiVoManager *myManager = nil;
    BOOL __block firstTime = NO;
    dispatch_once(&pred, ^{
        myManager = [[self alloc] init];
        //have to wait until tivomanager is assigned and out of protected block
        //before calling subsidiary data models as they will call back in
        firstTime = YES;

    });
    if (firstTime) {
        [myManager restoreOldQueue]; //no reason to fire all notifications on initial queue
        [[NSUserDefaults standardUserDefaults] synchronize];
        [myManager setupNotifications];
    }
    return myManager;
}

-(id)init
{
	self = [super init];
	if (self) {
		DDLogDetail(@"setting up TivoManager");
		NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
		_tivoServices = [NSMutableArray new];
		_tiVoList = [NSMutableArray new];
		self.opsQueue = [NSOperationQueue new];
        _downloadQueue = [NSMutableArray new];

        _lastLoadedTivoTimes = [[defaults dictionaryForKey:kMTTiVoLastLoadTimes] mutableCopy];
		if (!_lastLoadedTivoTimes) {
			_lastLoadedTivoTimes = [NSMutableDictionary new];
		}
        [self initialFormatSetup];
		self.downloadDirectory  = [defaults objectForKey:kMTDownloadDirectory];
		DDLogVerbose(@"downloadDirectory %@", self.downloadDirectory);
        [self restoreManualEpisodeInfo];

		numEncoders = 0;
		_signalError = 0;
		self.opsQueue.maxConcurrentOperationCount = 4;

		_processingPaused = @(NO);
		
		[self loadUserNotifications];
        [self setupMetadataQuery];
 		loadingManualTiVos = NO;
        self.tvdb = [MTTVDB sharedManager];
	}
	return self;
}

-(void) initialFormatSetup {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

    NSString *formatListPath = [[NSBundle mainBundle] pathForResource:@"formats" ofType:@"plist"];
    NSDictionary *formats = [NSDictionary dictionaryWithContentsOfFile:formatListPath];
    _formatList = [NSMutableArray arrayWithArray:[formats objectForKey:@"formats"]];
    NSMutableArray *tmpArray = [NSMutableArray array];
    for (NSDictionary *fl in _formatList) {
        MTFormat *thisFormat = [MTFormat formatWithDictionary:fl];
        thisFormat.isFactoryFormat = [NSNumber numberWithBool:YES];
        [tmpArray addObject:thisFormat];
    }
    _formatList = tmpArray;
    DDLogVerbose(@"factory Formats: %@", tmpArray);

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
            if ([name isEqualToString:f.name]) {  //confirm find didn't return a default format
                f.isHidden = [NSNumber numberWithBool:YES];
            }
        }
    }

    //Load user formats from preferences if any
    NSArray *userFormats = [[NSUserDefaults standardUserDefaults] arrayForKey:kMTFormats];
    if (userFormats) {
        DDLogVerbose(@"User formats: %@", userFormats);
        [self addFormatsToList:userFormats withNotification:NO];
    }

    //Make sure there's a selected format, especially on first launch

    NSString *formatName = [defaults objectForKey:kMTSelectedFormat];
    self.selectedFormat = [self findFormat:formatName];
    DDLogVerbose(@"defaultFormat %@", formatName);
}

-(void) setupMetadataQuery {
    //Set up query for existing downloads using
    cTiVoQuery = [[NSMetadataQuery alloc] init];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(metadataQueryHandler:) name:NSMetadataQueryDidUpdateNotification object:cTiVoQuery];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(metadataQueryHandler:) name:NSMetadataQueryDidFinishGatheringNotification object:cTiVoQuery];
    NSPredicate *mdqueryPredicate = [NSPredicate predicateWithFormat:@"kMDItemFinderComment ==[c] 'cTiVoDownload'"];
    [cTiVoQuery setPredicate:mdqueryPredicate];
    [cTiVoQuery setSearchScopes:@[NSMetadataQueryLocalComputerScope]];
    [cTiVoQuery setNotificationBatchingInterval:2.0];
    [cTiVoQuery startQuery];
}

-(void)metadataQueryHandler:(id)sender
{
	DDLogDetail(@"Got Metadata Result with count %ld",[cTiVoQuery resultCount]);
	NSMutableDictionary *tmpDict = [NSMutableDictionary dictionary];
	for (NSUInteger i =0; i < [cTiVoQuery resultCount]; i++) {
        NSMetadataItem * item = [cTiVoQuery resultAtIndex:i];
        if (![item isKindOfClass:[NSMetadataItem class]]) continue;
        NSString *filePath = [item valueForAttribute:NSMetadataItemPathKey];
        NSString * showID = [filePath getXAttr:kMTXATTRTiVoID ];
        NSString * tiVoName = [filePath getXAttr:kMTXATTRTiVoName ];
        if (showID.length && tiVoName.length) {
            NSString *key = [NSString stringWithFormat:@"%@: %@",tiVoName,showID];
            if ([tmpDict objectForKey:key]) {
                NSArray *paths = [tmpDict objectForKey:key];
                [tmpDict setObject:[paths arrayByAddingObject:filePath] forKey:key];
            } else {
                [tmpDict setObject:@[filePath] forKey:key];
			}
		}
	}
	self.showsOnDisk = [NSDictionary dictionaryWithDictionary:tmpDict];
    [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationTiVoShowsUpdated object:nil];
	DDLogVerbose(@"showsOnDisk = %@",self.showsOnDisk);
}

-(NSString *)keyForShow: (MTTiVoShow *) show {
    return [NSString stringWithFormat:@"%@: %@",show.tiVoName,show.idString];
}

-(NSArray <NSString *> *) copiesOnDiskForShow:(MTTiVoShow *) show {
    return [self.showsOnDisk objectForKey: [self keyForShow:show]];
}

-(void) addShow:(MTTiVoShow *) show onDiskAtPath:(NSString *)path {
    //Add xattrs
    [path setXAttr:kMTXATTRTiVoName toValue:show.tiVoName ];
    [path setXAttr:kMTXATTRTiVoID toValue:show.idString ];
    [path setXAttr:kMTXATTRSpotlight toValue:kMTSpotlightKeyword ];

    NSMutableDictionary *tmpDict = [NSMutableDictionary dictionaryWithDictionary:self.showsOnDisk];
    NSString * key = [self keyForShow:show];
    if ([tmpDict objectForKey:key]) {
        NSArray *paths = [tmpDict objectForKey:key];
        [tmpDict setObject:[paths arrayByAddingObject:path] forKey:key];
    } else {
        [tmpDict setObject:@[path] forKey:key];
    }
    self.showsOnDisk = [NSDictionary dictionaryWithDictionary:tmpDict];
}


#pragma mark - Loading queue from Preferences

-(void) restoreOldQueue {
	NSArray *oldQueue = [[NSUserDefaults standardUserDefaults] objectForKey:kMTQueue];
	DDLogMajor(@"Restoring old Queue(%ld elements)",oldQueue.count);
	
	NSMutableArray * newShows = [NSMutableArray arrayWithCapacity:oldQueue.count];
	for (NSDictionary * queueEntry in oldQueue) {
		DDLogDetail(@"Restoring show %@",queueEntry[kMTQueueTitle]);
		MTDownload * newDownload= [MTDownload downloadFromQueue:queueEntry];
		[newShows addObject:newDownload];
	}
	DDLogVerbose(@"Restored downloadQueue: %@",newShows);
	self.downloadQueue = newShows;

    //update formats
    if ([[NSUserDefaults standardUserDefaults] integerForKey:kMTUserDefaultVersion] < 2) {
        if (self.selectedFormat.isDeprecated) {
            self.selectedFormat =[self findFormat:@""];// switch to Default
        }
        NSString * warnUserDeprecated = nil;
        for (MTSubscription * sub in self.subscribedShows) {
            if (sub.encodeFormat.isDeprecated) {
                warnUserDeprecated = sub.encodeFormat.name;
                break;
            }
        }
        if (!warnUserDeprecated) {
            for (MTDownload * download in self.downloadQueue) {
                if (download.isNew && download.encodeFormat.isDeprecated) {
                    warnUserDeprecated = download.encodeFormat.name;
                    break;
                }
            }
        }
        if (warnUserDeprecated) {
            [self notifyWithTitle: [NSString stringWithFormat: @"Formats like %@ are not recommended!", warnUserDeprecated ]
                         subTitle: @"Switch to Default or another Format" ];
        }
        [[NSUserDefaults standardUserDefaults] setInteger:2 forKey:kMTUserDefaultVersion];
    }

}

-(NSInteger) findProxyShowInDLQueue:(MTTiVoShow *) showTarget {
	NSString * targetTivoName = showTarget.tiVo.tiVo.name;
	return [self.downloadQueue indexOfObjectPassingTest:^BOOL(MTDownload * download, NSUInteger idx, BOOL *stop) {
		MTTiVoShow * possShow = download.show;
		return [targetTivoName isEqualToString:[possShow tempTiVoName]] &&
		showTarget.showID == possShow.showID &&
        possShow.protectedShow.boolValue;
	}];
}

-(void) replaceProxyInQueue: (MTTiVoShow *) newShow {
    NSInteger dlIndex;
    while ((dlIndex =[tiVoManager findProxyShowInDLQueue:newShow]) != NSNotFound) {
		MTDownload * proxyDL = [tiVoManager downloadQueue][dlIndex];
		DDLogVerbose(@"Found proxy %@ at %ld on tiVo %@",newShow, dlIndex, proxyDL.show.tiVoName);
        [proxyDL convertProxyToRealForShow: newShow];
		//this is a back door entry into queue, so need to check for uniqueness again in current environment
//		[self checkShowTitleUniqueness:newShow];
		if (proxyDL.downloadStatus.integerValue == kMTStatusDeleted) {
			DDLogDetail(@"Tivo restored previously deleted show %@",newShow);
			[proxyDL prepareForDownload:YES];
		}
	}
}

-(void)checkDownloadQueueForDeletedEntries: (MTTiVo *) tiVo {
	NSString *targetTivoName = tiVo.tiVo.name;
	for (MTDownload * download in self.downloadQueue) {
		if(download.show.protectedShow.boolValue &&
		   [targetTivoName isEqualToString:download.show.tiVoName]) {
			if (! download.isDone) {
				DDLogDetail(@"Marking %@ as deleted", download.show.showTitle);
				download.downloadStatus =@kMTStatusDeleted;
			}
			download.show.imageString = @"deleted";
			download.show.protectedShow = @NO; //let them delete from queue
		}
	}
}


-(void)saveState {
	NSMutableArray * downloadArray = [NSMutableArray arrayWithCapacity:_downloadQueue.count];
	for (MTDownload * download in _downloadQueue) {
		[downloadArray addObject:[download queueRecord]];
	}
    DDLogVerbose(@"writing DL queue: %@", downloadArray);
	[[NSUserDefaults standardUserDefaults] setObject:downloadArray forKey:kMTQueue];

    [self saveManualEpisodeInfo];
	[self.subscribedShows saveSubscriptions];
	[[NSUserDefaults standardUserDefaults] synchronize];

}


#pragma mark - TiVo Search Methods

-(void) loadManualTiVos
{
//    BOOL didFindTiVo = NO;
	if (loadingManualTiVos) {
		return;
	}
	loadingManualTiVos = YES;
	DDLogDetail(@"LoadingTivos");
	NSMutableArray *bonjourTiVoList = [NSMutableArray arrayWithArray:[_tiVoList filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"manualTiVo == NO"]]];
	NSArray *manualTiVoList = [NSArray arrayWithArray:[_tiVoList filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"manualTiVo == YES"]]];
//	[_tiVoList removeObjectsInArray:manualTiVoList];
	DDLogVerbose(@"Manual TiVos: %@",manualTiVoList);
	
	//Update rebuild manualTiVoList reusing what can be reused.
	NSMutableArray *newManualTiVoList = [NSMutableArray array];
	for (NSDictionary *mTiVo in self.savedTiVos) {
        if ([mTiVo[kMTTiVoManualTiVo] boolValue]) {
			if ([mTiVo[kMTTiVoEnabled] boolValue]) { //Don't do anything if not enabled
				MTTiVo *targetMTTiVo = nil;
				BOOL shouldUpdateTiVo = NO;
				for (MTTiVo *currentMTiVo in manualTiVoList) { // See if there is a current TiVo that matches (by ID as name may change)
					if (currentMTiVo.manualTiVoID == [mTiVo[kMTTiVoID] intValue]) {
						targetMTTiVo = currentMTiVo; //Found a TiVo to edit
						break;
					}
				}
				if (!targetMTTiVo) { //Create a new MTTiVo
					targetMTTiVo = [MTTiVo manualTiVoWithDescription:mTiVo withOperationQueue:self.opsQueue];
					if(targetMTTiVo){
						shouldUpdateTiVo = YES;
						DDLogDetail(@"Adding new manual TiVo %@",targetMTTiVo);
					}
				}
				if (targetMTTiVo) {
					if ([targetMTTiVo.tiVo.iPAddress caseInsensitiveCompare:mTiVo[kMTTiVoIPAddress]] != NSOrderedSame ||  //Update if required, incl. a new MTTiVo
							   [targetMTTiVo.tiVo.userName compare:mTiVo[kMTTiVoUserName]] != NSOrderedSame ||
							   targetMTTiVo.tiVo.userPort != [mTiVo[kMTTiVoUserPort] intValue] ||
							   targetMTTiVo.tiVo.userPortSSL != [mTiVo[kMTTiVoUserPortSSL] intValue] ||
							   ![targetMTTiVo.mediaKey isEqualToString:mTiVo[kMTTiVoMediaKey]]
							   ) { // If there's a change then edit it and update
						targetMTTiVo.tiVo.iPAddress = mTiVo[kMTTiVoIPAddress];
						targetMTTiVo.tiVo.userName = mTiVo[kMTTiVoUserName];
						targetMTTiVo.tiVo.userPort = (short)[mTiVo[kMTTiVoUserPort] intValue];
						targetMTTiVo.tiVo.userPortSSL = (short)[mTiVo[kMTTiVoUserPortSSL] intValue];
						targetMTTiVo.enabled = [mTiVo[kMTTiVoEnabled] boolValue];
						targetMTTiVo.mediaKey = mTiVo[kMTTiVoMediaKey];
						DDLogDetail(@"Updated manual TiVo %@",targetMTTiVo);
						shouldUpdateTiVo = YES;
					}
					if (shouldUpdateTiVo) {
						//Turn off label in UI
						[[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationTiVoUpdated object:targetMTTiVo];
						//RE-update shows
						[targetMTTiVo scheduleNextUpdateAfterDelay:0];
					}
					[newManualTiVoList addObject:targetMTTiVo];
				}
			}
		} else {
			//bonjour tivo, so just check if it needs to be refreshed
			for (MTTiVo *targetTiVo in bonjourTiVoList) {
				if ([targetTiVo.tiVo.name isEqualToString: mTiVo[kMTTiVoUserName]] ) {
					if (!targetTiVo.enabled  ||  ![targetTiVo.mediaKey isEqualToString:mTiVo[kMTTiVoMediaKey]]) {
						//Turn off label in UI
						//RE-update shows
						[[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationTiVoUpdated object:targetTiVo];
						targetTiVo.enabled = YES;
						targetTiVo.mediaKey = mTiVo[kMTTiVoMediaKey];
						[targetTiVo scheduleNextUpdateAfterDelay:0];
						break;
					}
				}
			}
		}
		
	}
	NSArray *bonjourTiVoDescriptions = self.savedBonjourTiVos;
	for (NSDictionary *mTiVo in bonjourTiVoDescriptions) {
        if ([mTiVo[kMTTiVoEnabled] boolValue]) { //Don't do anything if not enabled
		}
	}

//	//Re build _tivoList
	[bonjourTiVoList addObjectsFromArray:newManualTiVoList];
	self.tiVoList = bonjourTiVoList;
	DDLogDetail(@"TiVo List %@",self.tiVoList);
	NSNotification *notification = [NSNotification notificationWithName:kMTNotificationTiVoListUpdated object:nil];
	[[NSNotificationCenter defaultCenter] performSelectorOnMainThread:@selector(postNotification:) withObject:notification waitUntilDone:NO];
	loadingManualTiVos = NO;
}


//Found issues with corrupt, or manually edited entries in the manual array so use this to remove them
-(NSArray *)getManualTiVoDescriptions
{
	NSMutableArray *manualTiVoDescriptions = [NSMutableArray arrayWithArray:[[NSUserDefaults standardUserDefaults] arrayForKey:kMTManualTiVos]];
	NSMutableArray *itemsToRemove = [NSMutableArray array];
    for (NSDictionary *manualTiVoDescription in manualTiVoDescriptions) {
		if (manualTiVoDescription.count != 6 ||
			((NSString *)manualTiVoDescription[kMTTiVoUserName]).length == 0 ||
			((NSString *)manualTiVoDescription[kMTTiVoIPAddress]).length == 0) {
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

-(NSArray *)savedTiVos
{
    return [[NSUserDefaults standardUserDefaults] objectForKey:kMTTiVos];
}

-(void)updateTiVoDefaults:(MTTiVo *)tiVo
{
    DDLogDetail(@"Updating TiVo Defaults with tivo %@",tiVo);
    NSArray *currentSavedTiVos = tiVoManager.savedTiVos;
    NSMutableArray *updatedSavedTiVos = [NSMutableArray new];
	NSDictionary *tiVoDict = [tiVo defaultsDictionary];
	BOOL foundTiVo = NO;
    for (NSDictionary *savedTiVo in currentSavedTiVos) {
		NSDictionary * dictToAdd = savedTiVo;
        if ([savedTiVo[kMTTiVoManualTiVo] boolValue]) {
			if (tiVo.manualTiVo && ([savedTiVo[kMTTiVoID] intValue] == tiVo.manualTiVoID)) {
				dictToAdd = tiVoDict;
				foundTiVo = YES;
			}
		} else if (!(tiVo.manualTiVo) && [savedTiVo[kMTTiVoUserName] isEqualToString:tiVo.tiVo.name]) {
            dictToAdd = tiVoDict;
			foundTiVo = YES;
        }
		[updatedSavedTiVos addObject:dictToAdd];
    }
	if (!foundTiVo) {
		DDLogReport(@"Warning: didn't find tivo %@",tiVo);
        [updatedSavedTiVos addObject:tiVoDict];
	}
    DDLogVerbose(@"Saving new tivos %@",[updatedSavedTiVos maskMediaKeys]);
    [[NSUserDefaults standardUserDefaults] setValue:updatedSavedTiVos forKeyPath:kMTTiVos];
}

-(int) nextManualTiVoID
{
    NSArray *manualTiVos = self.savedTiVos;
    int retValue = 1;
    for (NSDictionary *manualTiVo in manualTiVos) {
        if ([manualTiVo[kMTTiVoID] intValue] > retValue) {
            retValue = [manualTiVo[kMTTiVoID] intValue];
        }
    }
    return retValue+1;
}


-(void)searchForBonjourTiVos
{
	DDLogDetail(@"searching for Bonjour");
    tivoBrowser = [NSNetServiceBrowser new];
    tivoBrowser.delegate = self;
    [tivoBrowser scheduleInRunLoop:[NSRunLoop mainRunLoop] forMode:NSDefaultRunLoopMode];
    [tivoBrowser searchForServicesOfType:@"_tivo-videos._tcp" inDomain:@"local"];
}

//-(NSArray *)hostAddresses
//{
//    NSArray *ret = _hostAddresses;
//    if (!_hostAddresses) {
//        self.hostAddresses = [[NSHost currentHost] addresses];
//		DDLogDetail(@"Host Addresses:  %@",self.hostAddresses);
//        ret = _hostAddresses;
//    }
//    return ret;
//}

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

-(NSArray *)allTiVos
{
    return _tiVoList;
}

-(NSArray *)tiVoList {
    NSPredicate *enabledTiVos = [NSPredicate predicateWithFormat:@"enabled == YES"];
//    NSArray *enabledTiVoList = [_tiVoList filteredArrayUsingPredicate:enabledTiVos];
//    NSLog(@"return %lu enabled tivos",enabledTiVoList.count);
	return [_tiVoList filteredArrayUsingPredicate:enabledTiVos];
}

-(void) setTiVoList: (NSArray *) tiVoList {
	if (_tiVoList != tiVoList) {
		NSSortDescriptor *manualSort = [NSSortDescriptor sortDescriptorWithKey:@"manualTiVo" ascending:NO];
		NSSortDescriptor *nameSort = [NSSortDescriptor sortDescriptorWithKey:@"tiVo.name" ascending:YES];
		_tiVoList = [tiVoList sortedArrayUsingDescriptors:[NSArray arrayWithObjects:manualSort,nameSort, nil]];
		DDLogVerbose(@"resorting TiVoList %@", _tiVoList);
	}
}

-(void) setupNotifications {

    DDLogVerbose(@"setting tivoManager notifications");
    NSNotificationCenter *defaultCenter = [NSNotificationCenter defaultCenter];
    
    [defaultCenter addObserver:self selector:@selector(encodeFinished:) name:kMTNotificationShowDownloadDidFinish object:nil];
    [defaultCenter addObserver:self selector:@selector(encodeFinished:) name:kMTNotificationShowDownloadWasCanceled object:nil];
//    [defaultCenter addObserver:self selector:@selector(encodeFinished) name:kMTNotificationEncodeWasCanceled object:nil];
//    [defaultCenter addObserver:self selector:@selector(commercialFinished) name:kMTNotificationCommercialDidFinish object:nil];
//    [defaultCenter addObserver:self selector:@selector(commercialFinished) name:kMTNotificationCommercialWasCanceled object:nil];
//    [defaultCenter addObserver:self selector:@selector(captionFinished) name:kMTNotificationCaptionDidFinish object:nil];
//    [defaultCenter addObserver:self selector:@selector(captionFinished) name:kMTNotificationCaptionWasCanceled object:nil];
    [defaultCenter addObserver:self.subscribedShows selector:@selector(checkSubscription:) name: kMTNotificationDetailsLoaded object:nil];
    [defaultCenter addObserver:self.subscribedShows selector:@selector(initialLastLoadedTimes) name:kMTNotificationTiVoListUpdated object:nil];

    [[NSUserDefaults standardUserDefaults] addObserver:self forKeyPath:kMTUpdateIntervalMinutes options:NSKeyValueObservingOptionNew context:nil];
	[[NSUserDefaults standardUserDefaults] addObserver:self forKeyPath:kMTScheduledOperations options:NSKeyValueObservingOptionNew context:nil];
	[[NSUserDefaults standardUserDefaults] addObserver:self forKeyPath:kMTScheduledEndTime options:NSKeyValueObservingOptionNew context:nil];
	[[NSUserDefaults standardUserDefaults] addObserver:self forKeyPath:kMTScheduledStartTime options:NSKeyValueObservingOptionNew context:nil];
    [[NSUserDefaults standardUserDefaults] addObserver:self forKeyPath:kMTTiVos options:NSKeyValueObservingOptionNew context:nil];

}

#pragma mark - Scheduling routine

-(void)determineCurrentProcessingState
{ //merge with configureSchedule?
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
    BOOL manuallyPaused = [[NSUserDefaults standardUserDefaults] boolForKey:kMTQueuePaused];
	if (manuallyPaused ||
         (schedulingActive &&
            (startTimeSeconds > currentSeconds || currentSeconds > endTimeSeconds))) { //We're NOT active
             [self pauseQueue:@(NO)];
	} else {
        [self unPauseQueue];
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


-(BOOL) anyShowsWaiting {
	for (MTDownload * show in tiVoManager.downloadQueue) {
		if (!show.isDone) {
			return YES; //no real need to count them all
		}
	}
	return NO;
}

-(BOOL) anyShowsCompleted {
	for (MTDownload * show in tiVoManager.downloadQueue) {
		if (show.isDone) {
			return YES; //no real need to count them all
		}
	}
	return NO;
}

-(void) clearDownloadHistory {
	NSMutableIndexSet * itemsToRemove= [NSMutableIndexSet indexSet];
	for (unsigned int index = 0;index< tiVoManager.downloadQueue.count; index++) {
		MTDownload * download = tiVoManager.downloadQueue[index];
		if (download.isDone) {
			[itemsToRemove addIndex:index];
			download.show.isQueued = NO;
		}
	}

	if (itemsToRemove.count > 0) {
		DDLogVerbose(@"Deleted history: %@", itemsToRemove);
		[_downloadQueue removeObjectsAtIndexes:itemsToRemove];
		[[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationDownloadQueueUpdated object:nil];
		[[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationTiVoShowsUpdated object:nil];
	} else {
		DDLogDetail(@"No history to delete?");
		
	}

}

-(void)pauseQueue:(NSNumber *)askUser
{
    if ([askUser boolValue] && [self anyTivoActive] ) {
		NSAlert *scheduleAlert = [NSAlert alertWithMessageText:@"There are shows in process, and you are pausing the queue.  Should the current shows in process be rescheduled?" defaultButton:@"Reschedule" alternateButton: @"Cancel" otherButton: @"Complete current show(s)" informativeTextWithFormat:@""];
		NSInteger returnValue = [scheduleAlert runModal];
		DDLogDetail(@"User said %ld to cancel alert",returnValue);
		if (returnValue == NSAlertDefaultReturn) {
			//We're rescheduling shows
            for (MTTiVo *tiVo in _tiVoList) {
                [tiVo rescheduleAllShows];
            }
            NSNotification *notification = [NSNotification notificationWithName:kMTNotificationDownloadQueueUpdated object:nil];
            [[NSNotificationCenter defaultCenter] performSelector:@selector(postNotification:) withObject:notification afterDelay:4.0];
#if 0  //maybe in a future release
            dispatch_queue_t queue2 = dispatch_get_global_queue(0,0);
            dispatch_group_t group = dispatch_group_create();

            for (MTTiVo *tiVo in _tiVoList) {
               dispatch_group_async(group,queue2,^{
                   [tiVo rescheduleAllShows];
                });
            }

            dispatch_group_notify(group,queue2,^{
                DDLogReport(@"finished all reschedules");
             [NSNotificationCenter postNotificationNameOnMainThread:kMTNotificationDownloadQueueUpdated object:nil afterDelay:4.0 ];           });
#endif
            self.processingPaused = @(YES);
        } else if (returnValue == NSAlertAlternateReturn) {
            //no action:  self.processingPaused = @(NO);
        } else { //NSAlertOtherReturn
            self.processingPaused = @(YES);
        }
    } else {
        self.processingPaused = @(YES);
        for (MTTiVo *tiVo in _tiVoList) {
            [tiVo rescheduleAllShows];
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
	NSCalendar *myCalendar = [NSCalendar currentCalendar];
	NSDateComponents *currentComponents = [myCalendar components:(NSHourCalendarUnit | NSMinuteCalendarUnit | NSSecondCalendarUnit) fromDate:[NSDate date]];
	NSDateComponents *targetComponents = [myCalendar components:(NSHourCalendarUnit | NSMinuteCalendarUnit | NSSecondCalendarUnit) fromDate:date];
	double currentSeconds = (double)currentComponents.hour * 3600.0 +(double) currentComponents.minute * 60.0 + (double) currentComponents.second;
	double targetSeconds = (double)targetComponents.hour * 3600.0 + (double)targetComponents.minute * 60.0 + (double) targetComponents.second;
	if (targetSeconds <= currentSeconds) {
		targetSeconds += 3600 * 24;
	}
	return targetSeconds - currentSeconds;
}

-(NSDate *) tomorrowAtTime: (NSInteger) hour {
    //may be called at launch, so don't assume anything is setup
    NSUInteger units = NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay | NSCalendarUnitHour | NSCalendarUnitMinute | NSCalendarUnitSecond  ;
    NSDateComponents *comps = [[NSCalendar currentCalendar] components:units fromDate:[NSDate date]];
    comps.day = comps.day + 1;    // Add one day
    comps.hour = hour;
    comps.minute = 0;
    comps.second = 0;
    NSDate *tomorrowTime = [[NSCalendar currentCalendar] dateFromComponents:comps];
    return tomorrowTime;
}

-(NSDate *) defaultQueueStartTime {
return [self tomorrowAtTime:1];  //start at 1AM tomorrow]
}

-(NSDate *) defaultQueueEndTime {
    return [self tomorrowAtTime:6];  //end at 6AM tomorrow]
}

-(void)setQueueStartTime
{
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(unPauseQueue) object:nil];
	if (![[NSUserDefaults standardUserDefaults] boolForKey:kMTScheduledOperations]){
		DDLogDetail(@"No scheduled operations auto-resume");
		return;
	}
	NSDate* startDate = [[NSUserDefaults standardUserDefaults] objectForKey:kMTScheduledStartTime];
    if (!startDate) {
        [[NSUserDefaults standardUserDefaults] setObject:[self defaultQueueStartTime] forKey:kMTScheduledStartTime]; //recursive
        return;
    }
    double targetSeconds = [self secondsUntilNextTimeOfDay:startDate];
	DDLogDetail(@"Will start queue in %f seconds (%f hours), due to beginDate of %@",targetSeconds, (targetSeconds/3600.0), startDate);
	[self performSelector:@selector(unPauseQueue) withObject:nil afterDelay:targetSeconds];
}

-(void)setQueueEndTime
{
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(pauseQueue:) object:@(NO)];
	if (![[NSUserDefaults standardUserDefaults] boolForKey:kMTScheduledOperations]) {
		DDLogDetail(@"No scheduled operations auto-pause ");
		return;
	}
	NSDate * endDate = [[NSUserDefaults standardUserDefaults] objectForKey:kMTScheduledEndTime];
    if (!endDate) {
         [[NSUserDefaults standardUserDefaults] setObject:[self defaultQueueEndTime] forKey:kMTScheduledEndTime];//recursive
        return;
    }
    double targetSeconds = [self secondsUntilNextTimeOfDay:endDate];
	DDLogDetail(@"Will pause queue in %f seconds (%f hours), due to endDate of %@",targetSeconds, (targetSeconds/3600.0), endDate);
	[self performSelector:@selector(pauseQueue:) withObject:@(NO) afterDelay:targetSeconds];
}

-(void)startAllTiVoQueues
{
    for (MTTiVo *tiVo in _tiVoList) {
        DDLogDetail(@"Starting download on tiVo %@",tiVo.tiVo.name);
		[tiVo manageDownloads:tiVo];
    }
}

-(void) cancelAllDownloads {
	for (MTDownload *download in tiVoManager.downloadQueue) {
		if (download.isInProgress){
			[download rescheduleShowWithDecrementRetries:@NO];
		}
	}
}

-(double) aggregateSpeed {
    double speed = 0.0;
    for (MTDownload *download in tiVoManager.downloadQueue) {
        if (download.downloadStatus.intValue == kMTStatusDownloading || download.downloadStatus.intValue == kMTStatusEncoding) {
            speed += download.speed;
        }
    }
    return speed;
}

-(NSTimeInterval) aggregateTimeLeft {
    double speed = self.aggregateSpeed;
    if (speed == 0.0) return 0.0;
    
    double work = 0.0;
    for (MTDownload *download in tiVoManager.downloadQueue) {
        if (download.downloadStatus.intValue == kMTStatusDownloading || download.downloadStatus.intValue == kMTStatusEncoding){
            work += download.show.fileSize * (1.0-download.processProgress);
        } else if (!download.isDone) {
            work += download.show.fileSize;
        }
    }
    return work/speed;
}

#pragma mark - Key Value Observing

-(void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    NSUserDefaults * defs = [NSUserDefaults standardUserDefaults];
    if ([keyPath compare:kMTScheduledOperations] == NSOrderedSame) {
        DDLogMajor(@"Turned %@ scheduled Operations",[defs boolForKey:kMTScheduledOperations]? @"on" : @"off" );
		[self configureSchedule];
        [self determineCurrentProcessingState];
	} else if ([keyPath compare:kMTScheduledEndTime] == NSOrderedSame) {
        DDLogMajor(@"Set operations end time to %@",[defs objectForKey: kMTScheduledEndTime]);
		[self setQueueEndTime];
	} else if ([keyPath compare:kMTScheduledStartTime] == NSOrderedSame) {
       DDLogMajor(@"Set operations start time to %@",[defs objectForKey: kMTScheduledStartTime]);
        [self setQueueStartTime];
	} else if ([keyPath isEqualToString:kMTTiVos]){
        DDLogMajor(@"Changed TiVo list to %@",[[defs objectForKey:  kMTTiVos] maskMediaKeys]);
        [self updateTiVos];
    } else if ([keyPath isEqualToString:kMTUpdateIntervalMinutes]){
        DDLogMajor(@"Changed Update Time to %ld",(long)[defs integerForKey:kMTUpdateIntervalMinutes]);
        for (MTTiVo *tiVo in _tiVoList) {
            [tiVo scheduleNextUpdateAfterDelay:-1];
        }
    } else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }

}

-(void)updateTiVos
{
    //Make sure enabled state and media key are correct for network tivos and
    //mediakey, enabled, ports and hostname for manual tivos
    for (MTTiVo *tiVo in _tiVoList) {
		if (tiVo.manualTiVo) {
			for (NSDictionary *savedTiVo in self.savedTiVos) {
				if ([savedTiVo[kMTTiVoID] intValue] == tiVo.manualTiVoID) {
					tiVo.tiVo.userName = savedTiVo[kMTTiVoUserName];
					tiVo.tiVo.userPort = (short)[savedTiVo[kMTTiVoUserPort] intValue];
					tiVo.tiVo.userPortSSL = (short)[savedTiVo[kMTTiVoUserPortSSL] intValue];
					tiVo.mediaKey = savedTiVo[kMTTiVoMediaKey];
					tiVo.tiVo.iPAddress = savedTiVo[kMTTiVoIPAddress];
					tiVo.enabled = [savedTiVo[kMTTiVoEnabled] boolValue];
				}
			}
        } else {
			for (NSDictionary *savedTiVo in self.savedTiVos) {
				if ([savedTiVo[kMTTiVoUserName] isEqualToString:tiVo.tiVo.name]) {
					tiVo.mediaKey = savedTiVo[kMTTiVoMediaKey];
					tiVo.enabled = [savedTiVo[kMTTiVoEnabled] boolValue];
				}
			}
		}
    }
	DDLogDetail(@"Notifying %@",kMTNotificationTiVoListUpdated);[[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationTiVoListUpdated object:nil];
}

-(void)refreshAllTiVos
{
	DDLogMajor(@"Refreshing all Tivos");
	for (MTTiVo *tiVo in _tiVoList) {
		if (tiVo.isReachable && tiVo.enabled) {
			[tiVo updateShows:nil];
		}
	}
}

-(void)resetAllDetails {
	DDLogMajor(@"Resetting the caches!");
    [self.tvdb resetAll];

    //Remove TiVo Detail Cache
/* FIX; temp for tvdb debug
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *files = [fm contentsOfDirectoryAtPath:kMTTmpDetailsDir error:nil];
    for (NSString *file in files) {
        NSString *filePath = [NSString stringWithFormat:@"%@/%@",kMTTmpDetailsDir,file];
        [fm removeItemAtPath:filePath error:nil];
    }
 */
	for (MTTiVo *tiVo in _tiVoList) {
        [tiVo resetAllDetails];
	}
	[self refreshAllTiVos];

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

-(void)setSelectedFormat:(MTFormat *)selectedFormat
{
    if (![selectedFormat isKindOfClass:[MTFormat class]]) {
        return;
    }
    if (selectedFormat == nil) {
        selectedFormat = [self findFormat:@"Default"];
    }
    if (selectedFormat == _selectedFormat) {
        return;
    }
    _selectedFormat = selectedFormat;
    [[NSUserDefaults standardUserDefaults] setObject:_selectedFormat.name forKey:kMTSelectedFormat];
}

-(MTFormat *) findFormat:(NSString *) formatName {
    MTFormat * defaultFormat = nil;
    if (!formatName) formatName = @""; //avoid nil compare issues
    for (MTFormat *fd in _formatList) {
        if ([fd.name compare:formatName] == NSOrderedSame) {
            return fd;
        }
        if ([fd.name isEqualToString:@"Default"]) {
            defaultFormat = fd;
        }
    }
	//nobody found; let's see if one got renamed
    for (MTFormat *fd in _formatList) {
        if ([formatName compare:fd.formerName] == NSOrderedSame) {
            return fd;
        }
    }
	//Now do lookup on hardwired ones that got renamed by us!!
	NSDictionary *  oldFormats =
		@{@"Quicktime (H.264   10Mbps)" : @"H.264 High Quality ",
		  @"Quicktime (H.264   5Mbps)" : @"H.264 Medium Quality",
		  @"Quicktime (H.264   3Mbps)" : @"H.264 Low Quality",
		  @"Quicktime (H.264   1Mbps)" : @"H.264 Small 1Mbps",
		  @"Quicktime (H.264   256kbps)" : @"H.264 Very Small 256kbps",
          @"ffmpeg ComSkip/5.1"         :@"Default",
          @"MP4 FFMpeg"                     : @"Decrypt MP4",
          @"ffmpeg ComSkip/5.1"             : @"Default",
          @"Handbrake AppleTV"              : @"HB Old AppleTV ",
          @"Handbrake iPhone"               : @"HB Old iPhone",
          @"Handbrake AppleTV for SD TiVos" : @"HB Std Def",
          @"Handbrake iPhone for SD TiVos"  : @"HB Std Def",
          @"Handbrake TV"                   : @"HB Std Def",
          @"Audio only (ffmpeg MP3)"        : @"Audio only (MP3)"
          };
	
	if (oldFormats[formatName]) {
		return [self findFormat:oldFormats[formatName]]; //recursion will stop assuming no circularity in oldFormats
	}
    if (!defaultFormat) defaultFormat = _formatList[0];
    return defaultFormat;
}

-(MTFormat *) testPSFormat {
    for (MTFormat *fd in _formatList) {
        if (fd.isTestPS) {
            return fd;
        }
    }
    return nil;
}

-(void)addEncFormatToList: (NSString *) filename {
	MTFormat * newFormat = [MTFormat formatWithEncFile:filename];
	[newFormat checkAndUpdateFormatName:tiVoManager.formatList];
	if (newFormat) [_formatList addObject:newFormat];
	[[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationFormatListUpdated object:nil];
	[[NSUserDefaults standardUserDefaults] setObject:tiVoManager.userFormatDictionaries forKey:kMTFormats];	
}

-(void)addFormatsToList:(NSArray *)formats withNotification:(BOOL) notify
{
	for (NSDictionary *f in formats) {
		MTFormat *newFormat = [MTFormat formatWithDictionary:f];
		//Lots of error checking here
        //Check that name is unique
        [newFormat checkAndUpdateFormatName:self.formatList];
		[self.formatList addObject:newFormat];
	}
    if (notify) {
        [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationFormatListUpdated object:nil];
        [[NSUserDefaults standardUserDefaults] setValue:tiVoManager.userFormatDictionaries forKey:kMTFormats];
    }
}

#pragma mark - Channel management

-(void) updateChannel: (NSDictionary *) newChannel {
    if (!newChannel) return;
    NSMutableArray *channels = [[[NSUserDefaults standardUserDefaults] objectForKey:kMTChannelInfo] mutableCopy];
    if (!channels) channels = [NSMutableArray array];

    NSIndexSet * removeIndexes = [channels indexesOfObjectsPassingTest:^BOOL(NSDictionary *  _Nonnull channel, NSUInteger idx, BOOL * _Nonnull stop) {
        return [channel[kMTChannelInfoName] caseInsensitiveCompare:newChannel[kMTChannelInfoName]] == NSOrderedSame;
    }];
    if (removeIndexes.count >0) {
        [channels removeObjectsAtIndexes:removeIndexes];
    }
    [channels addObject:newChannel];
    [[NSUserDefaults standardUserDefaults] setValue:channels forKeyPath:kMTChannelInfo];
}

-(void) createChannel: (NSDictionary *) newChannel  {
    if (!newChannel) return;
    NSString * channelBase = newChannel[kMTChannelInfoName];
    if ([self channelNamed:channelBase]) {
        int i = 0;
        NSString * newName = nil;

        do {
            i++;
            newName = [NSString stringWithFormat:@"%@%d",channelBase, i];
        } while ( [self channelNamed:newName]);
        NSMutableDictionary * channel = [newChannel mutableCopy];
        [channel setObject:newName forKey:kMTChannelInfoName];
        [self updateChannel:channel];
    } else {
        [self updateChannel:newChannel];
    }
}

-(void) setFailedPS:(BOOL) psFailed forChannelNamed: (NSString *) channelName {
    if (channelName.length == 0) return;
    NSDictionary * newChannel = [self channelNamed:channelName];
    if (newChannel) {
        NSMutableDictionary * mutChannel = [newChannel mutableCopy];
        [mutChannel setValue:@(psFailed) forKey:kMTChannelInfoPSFailed];
        newChannel = [NSDictionary dictionaryWithDictionary: mutChannel ];
    } else {
        newChannel = @{kMTChannelInfoName: channelName,
                      kMTChannelInfoCommercials: @(NSOnState),
                      kMTChannelInfoPSFailed: @(psFailed),
                       kMTChannelInfoUseTS: @(psFailed ? NSOnState : NSMixedState)};
    }
    [self updateChannel:newChannel];
}

-(NSDictionary *)channelNamed:(NSString *) channelName {
    NSArray <NSDictionary *> * channels = [[NSUserDefaults standardUserDefaults] objectForKey:kMTChannelInfo];
    NSUInteger index = [channels  indexOfObjectPassingTest:^BOOL(NSDictionary *  _Nonnull channel, NSUInteger idx, BOOL * _Nonnull stop) {
        return [channel[kMTChannelInfoName ] caseInsensitiveCompare:channelName] == NSOrderedSame;
    }];
    if (index == NSNotFound) {
        return nil;
    } else {
        return channels[index];
    }
}

-(void) removeAllChannelsStartingWith: (NSString*) prefix {
    NSArray * channels = [[NSUserDefaults standardUserDefaults] objectForKey:kMTChannelInfo];
    NSIndexSet * realChannels = [channels indexesOfObjectsPassingTest:^BOOL(NSDictionary *  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        return ! [obj[kMTChannelInfoName] hasPrefix:prefix];
    }];
    if (realChannels.count < channels.count) {
        [[NSUserDefaults standardUserDefaults] setValue: [channels objectsAtIndexes:realChannels]  forKey:kMTChannelInfo];
    }
}

-(void) sortChannelsAndMakeUnique {
    NSArray * channels = [[NSUserDefaults standardUserDefaults] objectForKey:kMTChannelInfo];
    NSMutableDictionary *uniqueObjects = [NSMutableDictionary dictionaryWithCapacity:channels.count];
    for (NSDictionary *object in channels) {
        if (![object isKindOfClass:[NSDictionary class]] || !object[kMTChannelInfoName]) {
            DDLogReport(@"Removing invalid entry in channels: %@", object);
            continue;
        }
        [uniqueObjects setObject:object forKey:object[kMTChannelInfoName]];
    }
    NSArray * newChannels = [[uniqueObjects allValues] sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *  _Nonnull obj1, NSDictionary *   _Nonnull obj2) {
        return [obj1[kMTChannelInfoName] caseInsensitiveCompare:obj2[kMTChannelInfoName] ];
    }];
    [[NSUserDefaults standardUserDefaults] setValue:newChannels  forKey:kMTChannelInfo];
}

-(NSCellStateValue) useTSForChannel:(NSString *)channelName {
    NSDictionary * channelInfo = [tiVoManager channelNamed:channelName];
    if (channelInfo) {
        return ((NSNumber*) channelInfo[kMTChannelInfoUseTS ]).intValue;
    } else {
        return NSMixedState;
    }
}

-(NSCellStateValue) failedPSForChannel:(NSString *) channelName {
    NSDictionary * channelInfo = [tiVoManager channelNamed:channelName];
    if (channelInfo) {
        return ((NSNumber*) channelInfo[kMTChannelInfoPSFailed ]).intValue;
    } else {
        return NSMixedState;
    }
}

-(NSCellStateValue) commercialsForChannel:(NSString *) channelName {
    NSDictionary * channelInfo = [tiVoManager channelNamed:channelName];
    if (channelInfo) {
        return ((NSNumber*) channelInfo[kMTChannelInfoCommercials ]).intValue;
    } else {
        return NSOnState;
    }
}

-(BOOL) allShowsSelected {
    return ((MTAppDelegate *) [NSApp delegate]).allShowsSelected;
}

-(void) testAllChannelsForPS {
    NSMutableSet * channelsTested = [NSMutableSet new];
    NSMutableArray * testsToRun = [NSMutableArray new];
    NSArray * programs = ((MTAppDelegate *) [NSApp delegate]).currentSelectedShows;
    for (MTDownload * existingDL in [self downloadQueue]) {
        //Avoids accidentally testing all shows twice
        if (existingDL.encodeFormat.isTestPS && existingDL.isNew) {
            [channelsTested addObject:existingDL.show.stationCallsign];
        }
    }
    for (MTTiVoShow * show in programs) {
        if (!(show.protectedShow.boolValue) && ! show.isQueued ) {
            NSString * channel = show.stationCallsign;
            if (channel) {
                if ( ! [channelsTested containsObject:channel]) {
                    if  ( [self useTSForChannel:channel ] != NSOnState ) {
                        MTDownload * newDownload = [MTDownload downloadTestPSForShow:show];
                        [testsToRun addObject:newDownload];
                    }
                    [channelsTested addObject:channel];
                }
            }
        }
    }
    if (testsToRun.count > 0) {
        [self addToDownloadQueue:testsToRun beforeDownload:nil];
    }
}

-(void) removeAllPSTests {
    MTFormat * testFormat = [self testPSFormat];
    NSMutableArray * testDownloads = [NSMutableArray new];
    for (MTDownload * download in self.downloadQueue) {
        if (!download.isInProgress && download.encodeFormat == testFormat) {
            [testDownloads addObject:download];
        }
    }
    [self deleteFromDownloadQueue:testDownloads ];

}

#pragma mark - Media Key Support


-(NSString *)getAMediaKey
{
	NSString *key = nil;
	NSArray *currentTiVoList = [NSArray arrayWithArray:[self allTiVos]];
	for (MTTiVo *tiVo in currentTiVoList) {
		if (tiVo.mediaKey && tiVo.mediaKey.length) {
			key = tiVo.mediaKey;
			break;
		}
	}
	return key;
}

#pragma mark - Download Management

-(NSIndexSet *) moveShowsInDownloadQueue:(NSArray *) shows
								 toIndex:(NSUInteger)insertIndex
{
	DDLogDetail(@"moving shows %@ to %ld", shows,insertIndex);
	NSIndexSet * fromIndexSet = [[tiVoManager downloadQueue] indexesOfObjectsPassingTest:
								 ^BOOL(id obj, NSUInteger idx, BOOL *stop) {
									return [shows indexOfObject:obj] != NSNotFound;
								 }];

	// If any of the removed objects come before the insertion index,
    // we need to decrement the index appropriately
    NSMutableArray * dlQueue = [self downloadQueue];
    NSUInteger adjustedInsertIndex = insertIndex -
    [fromIndexSet countOfIndexesInRange:(NSRange){0, insertIndex}];
    NSRange destinationRange = NSMakeRange(adjustedInsertIndex, shows.count);
    NSIndexSet *destinationIndexes = [NSIndexSet indexSetWithIndexesInRange:destinationRange];
    DDLogVerbose(@"moving shows %@ from %@ to %@", shows,fromIndexSet, destinationIndexes);
    if (fromIndexSet.count > 0) {
        //objects may be copies, so not in queue already
        [dlQueue removeObjectsAtIndexes: fromIndexSet];
    }
    [dlQueue insertObjects:shows atIndexes:destinationIndexes];

	DDLogDetail(@"Posting DLUpdated notifications");
	[[NSNotificationCenter defaultCenter ] postNotificationName:  kMTNotificationDownloadQueueUpdated object:nil];
	return destinationIndexes;
}

-(void) sortDownloadQueue {

	[self.downloadQueue sortUsingComparator:^NSComparisonResult(MTDownload * download1, MTDownload* download2) {
		NSInteger status1 = download1.downloadStatusSorter;
        NSInteger status2 = download2.downloadStatusSorter;
		return status1 > status2 ? NSOrderedAscending : status1 < status2 ? NSOrderedDescending : NSOrderedSame;
		
	}];
}

-(MTDownload *) findInDownloadQueue: (MTTiVoShow *) show {
	for (MTDownload * download in _downloadQueue) {
		if (download.show == show) {
			return download;
		}
	}
	return nil;
}

-(MTDownload *) findRealDownload: (MTDownload *) proxyDownload  {
	for (MTDownload * download in self.downloadQueue) {
		if ([download isSimilarTo:proxyDownload]) {
			return download;
		}
	}
	return nil;
}

-(NSArray *) currentDownloadQueueSortedBy: (NSArray *) sortDescripters {
	return [self.downloadQueue sortedArrayUsingDescriptors:sortDescripters];
}

-(void)addToDownloadQueue:(NSArray *)newDownloads beforeDownload:(MTDownload *) nextDownload {
	BOOL submittedAny = NO;
	for (MTDownload *newDownload in newDownloads){
		MTTiVoShow * newShow = newDownload.show;
		if (![newShow.protectedShow boolValue]) {
            BOOL showFound = NO;
            if(![[NSUserDefaults standardUserDefaults] boolForKey:kMTAllowDups]) {
                for (MTDownload *oldDownload in _downloadQueue) {
                    if (oldDownload.show.showID == newShow.showID	) {
                        if (oldDownload.show==newShow) {
                            DDLogDetail(@" %@ already in queue",oldDownload);
                        } else {
                            DDLogReport(@"show %@ already in queue as %@ with same ID %d!",oldDownload, newShow, newShow.showID);
                        }
                        showFound = YES;
                        break;
                    }
                }
            }
            if (!showFound) {
                //Make sure the title isn't the same and if it is add a -1 modifier
                submittedAny = YES;
//                [self checkShowTitleUniqueness:newShow];
				[newDownload prepareForDownload:NO];
				if (nextDownload) {
                    NSUInteger index = [_downloadQueue indexOfObject:nextDownload];
                    if (index == NSNotFound) {
						DDLogDetail(@"Prev show not found, adding %@ at end",newDownload);
						[_downloadQueue addObject:newDownload];
                        
                    } else {
						DDLogVerbose(@"inserting before %@ at %ld",nextDownload, index);
                        [_downloadQueue insertObject:newDownload atIndex:index];
                    }
                } else {
					DDLogVerbose(@"adding %@ at end",newDownload);
                   [_downloadQueue addObject:newDownload];
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


-(void) downloadShowsWithCurrentOptions:(NSArray *) shows beforeDownload:(MTDownload *) nextDownload {
	NSMutableArray * downloads = [NSMutableArray arrayWithCapacity:shows.count];
	for (MTTiVoShow * thisShow in shows) {
		NSUserDefaults * defaults = [NSUserDefaults standardUserDefaults];
		DDLogDetail(@"Adding show: %@", thisShow);
        MTDownload * newDownload = [MTDownload downloadForShow:thisShow withFormat: self.selectedFormat withQueueStatus: kMTStatusNew];
		newDownload.exportSubtitles = [defaults objectForKey:kMTExportSubtitles];
		newDownload.addToiTunesWhenEncoded = newDownload.encodeFormat.canAddToiTunes &&
											[defaults boolForKey:kMTiTunesSubmit];
//		newDownload.simultaneousEncode = newDownload.encodeFormat.canSimulEncode &&
//											[defaults boolForKey:kMTSimultaneousEncode];
		newDownload.skipCommercials = [newDownload.encodeFormat.comSkip boolValue] &&
											[defaults boolForKey:@"RunComSkip"];
		newDownload.markCommercials = newDownload.encodeFormat.canMarkCommercials &&
											[defaults boolForKey:@"MarkCommercials"];
		newDownload.genTextMetaData = [defaults objectForKey:kMTExportTextMetaData];
#ifndef deleteXML
		newDownload.genXMLMetaData = [defaults objectForKey:kMTExportTivoMetaData];
		newDownload.includeAPMMetaData =[NSNumber numberWithBool:(newDownload.encodeFormat.canAcceptMetaData && [defaults boolForKey:kMTExportMetaData])];
#endif
		[downloads addObject: newDownload];
	}
	[self addToDownloadQueue:downloads beforeDownload:nextDownload ];
}

-(void) deleteFromDownloadQueue:(NSArray *) downloads {
    NSMutableIndexSet * itemsToRemove= [NSMutableIndexSet indexSet];
	DDLogDetail(@"Delete shows: %@", downloads);
	for (MTDownload * download in downloads) {

		NSUInteger index = [_downloadQueue indexOfObject:download];
		if (index == NSNotFound) {
			for (MTDownload *oldDownload in _downloadQueue) {  //this is probably unncessary
				if (oldDownload.show.showID == download.show.showID	) {
					DDLogMajor(@"Odd: two shows with same ID: %@ in queue v %@", download, oldDownload);
					index = [_downloadQueue indexOfObject:oldDownload];
					break;
				}
			}
		}
		if (index != NSNotFound) {
			MTDownload *oldDownload = _downloadQueue[index];
            [oldDownload cancel];
			oldDownload.show.isQueued = NO;
			[itemsToRemove addIndex:index];
		}
	}
	
	if (itemsToRemove.count > 0) {
		DDLogVerbose(@"Deleted downloads: %@", itemsToRemove);
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
	for (MTDownload *download in _downloadQueue) {
		if (!download.isDone) {
			n++;
		}
	}
	return n;
}

-(BOOL) checkForExit {
    return [(MTAppDelegate *) [NSApp delegate] checkForExit];
}

#pragma mark - Growl/Apple Notifications

-(void) loadUserNotifications {

#if MAC_OS_X_VERSION_MIN_REQUIRED < MAC_OS_X_VERSION_10_9
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
#else
    [[NSUserNotificationCenter defaultUserNotificationCenter] setDelegate:self];
#endif
}
//Note that any new notification types need to be added to constants.h, but especially Growl Registration Ticket.growRegDict

- (BOOL)userNotificationCenter:(NSUserNotificationCenter *)center
     shouldPresentNotification:(NSUserNotification *)notification {
    return YES;
}
-(void) notifyWithTitle:(NSString *) title subTitle: (NSString*) subTitle {
    [self notifyForName: nil withTitle:title subTitle:subTitle isSticky:YES forNotification:kMTGrowlPossibleProblem];
}

- (void)notifyForName: (NSString *) objName withTitle:(NSString *) title subTitle: (NSString*) subTitle isSticky:(BOOL)sticky forNotification: (NSString *) notification {
    DDLogReport(@"Notify: %@/n%@", title, subTitle ?: @"");

#if MAC_OS_X_VERSION_MIN_REQUIRED < MAC_OS_X_VERSION_10_9
    //Note: when removing in future, remove all kMTGrowlxxx strings as well
    NSString * subTitleCombo = subTitle.length ? (objName.length ? [NSString stringWithFormat:@"%@: %@", subTitle, objName]
                                                                 : subTitle)
                                                : objName;
	Class GAB = NSClassFromString(@"GrowlApplicationBridge");
	if([GAB respondsToSelector:@selector(notifyWithTitle:description:notificationName:iconData:priority:isSticky:clickContext:identifier:)])
		[GAB notifyWithTitle: title
				 description: subTitleCombo
			notificationName: notification
					iconData: nil  //use our app logo
					priority: 0
					isSticky: sticky
				clickContext: nil
		 ];
#else
    NSUserNotification *userNot = [[NSUserNotification alloc] init ];
    userNot.title = title;
    userNot.subtitle = objName;
    userNot.informativeText = subTitle;
    userNot.soundName = NSUserNotificationDefaultSoundName;
    [[NSUserNotificationCenter defaultUserNotificationCenter] deliverNotification:userNot];
#endif
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
       if (tiVo.enabled) total += tiVo.shows.count;
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
    return [_downloadQueue filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"show.tiVoName == %@",tiVo.tiVo.name]];
}


-(void)encodeFinished:(NSNotification *)notification
{
    if (numEncoders == 0) {
        [self notifyWithTitle: @"Internal Logic Error! " subTitle: @"numEncoders under 0" ];

    } else {
        numEncoders--;
    }
    DDLogMajor(@"Num encoders after decrement from notification %@ is %d ",notification.name,numEncoders);

    NSNotification *restartNotification = [NSNotification notificationWithName:kMTNotificationDownloadQueueUpdated object:nil];
    [[NSNotificationCenter defaultCenter] performSelector:@selector(postNotification:) withObject:restartNotification afterDelay:2];
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
        if ([newDir isEquivalentToPath:kMTTmpDir] ||
            [newDir isEquivalentToPath:[[NSUserDefaults standardUserDefaults] stringForKey:kMTTmpFilesDirectory]]) {
            DDLogReport(@"Can't set download directory to temp directory%@; trying default", newDir);
            newDir = nil;
        }
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
			_downloadDirectory = newDir;
		}
	}
}

-(NSString *) defaultDownloadDirectory {
	return [NSString stringWithFormat:@"%@/%@/",NSHomeDirectory(),kMTDefaultDownloadDir];
//note this will fail in sandboxing. Need something like...

//		NSArray * movieDirs = [[NSFileManager defaultManager] URLsForDirectory:NSMoviesDirectory inDomains:NSUserDomainMask];
//		if (movieDirs.count >0) {
//			NSURL *movieURL = (NSURL *) movieDirs[0];
//			return [movieURL URLByAppendingPathComponent:@"TiVoShows"].path;
//      }

}

-(NSString *)tmpFilesDirectory {

    NSString * tmpPath = [[NSUserDefaults standardUserDefaults] stringForKey:kMTTmpFilesDirectory];
    if (![[NSFileManager defaultManager] fileExistsAtPath:tmpPath]) {
            [[NSUserDefaults standardUserDefaults] setObject:tmpPath forKey: kMTTmpFilesDirectory]; //trigger validation process
            tmpPath = [[NSUserDefaults standardUserDefaults] stringForKey:kMTTmpFilesDirectory];
        }
//    }
    return tmpPath;
 
}


-(NSMutableArray *)tiVoShows
{
	NSMutableArray *totalShows = [NSMutableArray array];
	DDLogVerbose(@"reloading shows");
	for (MTTiVo *tv in _tiVoList) {
		if (tv.enabled) {
			[totalShows addObjectsFromArray:tv.shows];

		}
	}
	return totalShows;
}
#pragma mark - Manual Show information

-(void) saveManualEpisodeInfo {
    @synchronized (self.manualEpisodeData) {
        for (NSString *key in self.manualEpisodeData.allKeys) {
            NSDictionary * info = self.manualEpisodeData[key];
            if (-[(NSDate *)info[@"date"] timeIntervalSinceNow ] > 60*60*24*90) {
                [self.manualEpisodeData removeObjectForKey:key];
            }
        }
        [[NSUserDefaults standardUserDefaults] setObject:
                                             (self.manualEpisodeData.count > 0) ?
                                              self.manualEpisodeData :
                                              nil
                                              forKey:kMTManualEpisodeData];
    }
}

-(void) restoreManualEpisodeInfo {
    self.manualEpisodeData = [[[NSUserDefaults standardUserDefaults] objectForKey:kMTManualEpisodeData] mutableCopy]
    ?: [NSMutableDictionary dictionary];
}

-(void) updateManualInfo:(NSDictionary *)info forShow:(MTTiVoShow *)show {
    @synchronized(self.manualEpisodeData) {
        NSMutableDictionary * newDatedInfo = [info mutableCopy];
        [newDatedInfo setValue:[NSDate date] forKey:@"date"];
        [self.manualEpisodeData setValue:[newDatedInfo copy] forKey: show.uniqueID];
    }
}

-(NSDictionary *) getManualInfo: (MTTiVoShow *) show {
    NSDictionary <NSString *, NSString *> *info;
    @synchronized (self.manualEpisodeData) {
        info = self.manualEpisodeData[show.uniqueID];
    }
    //we mark current date every time we access
    if (info) [self updateManualInfo: info forShow:show];
    return info;
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

- (void)netServiceBrowser:(NSNetServiceBrowser *)browser
             didNotSearch:(NSDictionary *)errorDict
{
    DDLogReport(@"Bonjour service not found: %@",errorDict);
}

- (void)netServiceBrowser:(NSNetServiceBrowser *)aNetServiceBrowser didRemoveService:(NSNetService *)aNetService moreComing:(BOOL)moreComing {
    DDLogReport(@"Removing Service: %@",aNetService.name);

}

#pragma mark - NetService delegate methods



- (NSString *)dataToString:(NSData *) data {
    // Helper for getting information from the TXT data
    NSString *resultString = nil;
    if (data) {
        resultString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    }
    return resultString;
}

- (void)netServiceDidResolveAddress:(NSNetService *)sender
{
    [sender stop];
	NSArray * addresses = [sender addresses];
	if (addresses.count == 0) return;
	if (addresses.count > 1) {
		DDLogDetail(@"more than one IP address: %@",addresses);
	}
	NSString *ipAddress = [self getStringFromAddressData:addresses[0]];
		
//    if (_tiVoList.count == 1) {  //Test code for single tivo testing
//        return;
//    }
	NSDictionary * TXTRecord = [NSNetService dictionaryFromTXTRecordData:sender.TXTRecordData ];
	for (NSString * key in [TXTRecord allKeys]) {
		DDLogDetail(@"TXTKey: %@ = %@", key, [self dataToString:TXTRecord[key]]);
	}

	NSString * platform = [self dataToString:TXTRecord[@"platform"]];
	NSString * TSN = [self dataToString:TXTRecord[@"tsn"]];
	NSString * identity = [self dataToString:TXTRecord[@"identity"]];
    NSString * version= [self dataToString:TXTRecord[@"swversion"]];
    
	if ([TSN hasPrefix:@"A94"] || [identity hasPrefix:@"A94"]) {
		DDLogDetail(@"Found Stream %@ - %@(%@); rejecting",TSN, sender.name, ipAddress);
		return;
	}
	if ([platform hasSuffix:@"pyTivo"]) {
		//filter out pyTivo
		DDLogDetail(@"Found pyTivo %@(%@); rejecting ",sender.name,ipAddress);
		return;
	}
    
	if ([version hasSuffix:@"1.95a"]) {
		//filter out tivo desktop
		DDLogDetail(@"Found old TiVo Desktop %@(%@) ",sender.name,ipAddress);
		return;
	}
	
	if (!TSN || TSN.length == 0) {
		DDLogDetail(@"No TSN; rejecting TiVo %@(%@)",sender.name,ipAddress);
		return;
	}

	if (platform && ![platform hasPrefix:@"tcd"]) {
		//filter out other non-tivos
		DDLogDetail(@"Invalid TiVo platform %@; rejecting %@(%@) ",platform, sender.name,ipAddress);
		return;
	}
    
	for (NSString *tiVoAddress in [self tiVoAddresses]) {
		DDLogVerbose(@"Comparing new TiVo %@ address %@ to existing %@",sender.name, ipAddress, tiVoAddress);
		if ([tiVoAddress caseInsensitiveCompare:ipAddress] == NSOrderedSame) {
			DDLogDetail(@"Rejecting duplicate TiVo at %@",ipAddress);
			return;  // This filters out tivos that have already been found from a manual entry
		}
	}
    
	MTTiVo *newTiVo = [MTTiVo tiVoWithTiVo:sender withOperationQueue:self.opsQueue];
    newTiVo.supportsTransportStream = [TSN characterAtIndex:0] > '6' || [TSN hasPrefix:@"663"];

	self.tiVoList = [_tiVoList arrayByAddingObject: newTiVo];
	if (self.tiVoList.count > 1 && ![[NSUserDefaults standardUserDefaults] boolForKey:kMTHasMultipleTivos]) {  //This is the first time we've found more than 1 tivo
		[[NSUserDefaults standardUserDefaults] setBool:YES forKey:kMTHasMultipleTivos];
		[[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationFoundMultipleTiVos object:nil];
	}
	DDLogReport(@"Got new TiVo: %@ at %@", newTiVo, ipAddress);
	[[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationTiVoListUpdated object:nil];
    [newTiVo scheduleNextUpdateAfterDelay:0];

}


-(void)netService:(NSNetService *)sender didNotResolve:(NSDictionary *)errorDict
{
    DDLogReport(@"Service %@ failed to resolve",sender.name);
    [sender stop];
}

- (NSString *)getStringFromAddressData:(NSData *)dataIn {
    struct sockaddr_in  *socketAddress = nil;
    NSString            *ipString = nil;
	
    socketAddress = (struct sockaddr_in *)[dataIn bytes];
    ipString = [NSString stringWithFormat: @"%s",
                inet_ntoa(socketAddress->sin_addr)];  ///problem here
	DDLogVerbose(@"Translated %u to %@", socketAddress->sin_addr.s_addr, ipString);
    return ipString;
}

-(void) dealloc {
    [[NSNotificationCenter defaultCenter]removeObserver:self];
}

@end

@implementation NSObject (maskMediaKeys)

-(NSString *) maskMediaKeys {
    NSString * outString =[self description];
    for (MTTiVo * tiVo in tiVoManager.tiVoList) {
        NSString * mediaKey = tiVo.mediaKey;
        if (mediaKey.length > 0) {
            NSString * maskedKey = [NSString stringWithFormat:@"<<%@ MediaKey>>",tiVo.tiVo.name];
            outString = [outString stringByReplacingOccurrencesOfString:mediaKey withString:maskedKey];
        }
    }
    return outString;
}
    

@end
