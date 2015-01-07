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
#import "MTSubscriptionList.h"

#import <Growl/Growl.h>

#include <arpa/inet.h>
#include <sys/xattr.h>



@interface MTTiVoManager () {
	
    NSNetServiceBrowser *tivoBrowser;
    NSMutableData *listingData;
	//	NSMutableDictionary *tiVoShowsDictionary;
	NSMutableArray *updatingTiVoShows;
	
	NSURLConnection *programListURLConnection, *downloadURLConnection;
	NSTask *decryptingTask, *encodingTask;
    NSMutableDictionary *programDownloading, *programDecrypting, *programEncoding;
	NSFileHandle *downloadFile, *stdOutFileHandle;
	double dataDownloaded, referenceFileSize;
	MTNetService *tivoConnectingTo;
	NSOpenPanel *myOpenPanel;
    double percentComplete;
 	NSArray *factoryFormatList;
    int numEncoders;// numCommercials, numCaptions;//Want to limit launches to two encoders.
	
    NSOperationQueue *queue;
    NSMetadataQuery *cTiVoQuery;
	BOOL volatile loadingManualTiVos;

}

@property (strong) MTNetService *updatingTiVo;
//@property (nonatomic, strong) NSArray *hostAddresses;

@end


@implementation MTTiVoManager

@synthesize subscribedShows = _subscribedShows, numEncoders, tiVoList = _tiVoList;

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
    return [self sharedTiVoManager];
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
		
        _lastLoadedTivoTimes = [[defaults dictionaryForKey:kMTTiVoLastLoadTimes] mutableCopy];
		if (!_lastLoadedTivoTimes) {
			_lastLoadedTivoTimes = [NSMutableDictionary new];
		}
		
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
		_formatList = tmpArray;
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
                if ([name isEqualToString:f.name]) {  //confirm find didn't return a default format
					f.isHidden = [NSNumber numberWithBool:YES];
				}
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
//        if (![defaults objectForKey:kMTSelectedFormat]) {
//            //What? No previous format,must be our first run. Let's see if there's any iTivo prefs.
//            [MTiTiVoImport checkForiTiVoPrefs];
//        }
		if (([defaults boolForKey:kMTRunComSkip] && [defaults boolForKey:kMTSimultaneousEncode])) [defaults setBool:NO forKey:kMTRunComSkip];  //patch for iTivo imports

		if ([defaults objectForKey:kMTSelectedFormat]) {
			NSString *formatName = [defaults objectForKey:kMTSelectedFormat];
			self.selectedFormat = [self findFormat:formatName];
			DDLogVerbose(@"defaultFormat %@", formatName);
		}
        
		//If no selected format make it the first.
		if (!_selectedFormat) {
			self.selectedFormat = [_formatList objectAtIndex:0];
		}
				
		self.downloadDirectory  = [defaults objectForKey:kMTDownloadDirectory];
		DDLogVerbose(@"downloadDirectory %@", self.downloadDirectory);
		

 		programEncoding = nil;
		programDecrypting = nil;
		programDownloading = nil;
		downloadURLConnection = nil;
		programListURLConnection = nil;
//        _hostAddresses = nil;
		downloadFile = nil;
		decryptingTask = nil;
		encodingTask = nil;
		stdOutFileHandle = nil;
		tivoConnectingTo = nil;
		
		numEncoders = 0;
//		numCommercials = 0;
//		numCaptions = 0;
		_signalError = 0;
		queue.maxConcurrentOperationCount = 1;
		
		_processingPaused = @(NO);
		self.quitWhenCurrentDownloadsComplete = @(NO);
		
		[self loadGrowl];
//		NSLog(@"Getting Host Addresses");
//		hostAddresses = [[[NSHost currentHost] addresses] retain];
//        NSLog(@"Host Addresses = %@",self.hostAddresses);
//        NSLog(@"Host Names = %@",[[NSHost currentHost] names]);
//        NSLog(@"Host addresses for first name %@",[[NSHost hostWithName:[[NSHost currentHost] names][0]] addresses]);
		
		//Set up query for exisiting downloads using
        cTiVoQuery = [[NSMetadataQuery alloc] init];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(metadataQueryHandler:) name:NSMetadataQueryDidUpdateNotification object:cTiVoQuery];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(metadataQueryHandler:) name:NSMetadataQueryDidFinishGatheringNotification object:cTiVoQuery];
		NSPredicate *mdqueryPredicate = [NSPredicate predicateWithFormat:@"kMDItemFinderComment ==[c] 'cTiVoDownload'"];
		[cTiVoQuery setPredicate:mdqueryPredicate];
		[cTiVoQuery setSearchScopes:@[NSMetadataQueryLocalComputerScope]];
		[cTiVoQuery setNotificationBatchingInterval:2.0];
		[cTiVoQuery startQuery];
		loadingManualTiVos = NO;
        _tvdbSeriesIdMapping = [NSMutableDictionary dictionary];
		_tvdbCache = [NSMutableDictionary dictionaryWithDictionary:[[NSUserDefaults standardUserDefaults] objectForKey:kMTTheTVDBCache]];
        //Clean up old entries
        NSMutableArray *keysToDelete = [NSMutableArray array];
        for (NSString *key in _tvdbCache) {
            NSDate *d = [[_tvdbCache objectForKey:key] objectForKey:@"date"];
            if ([[NSDate date] timeIntervalSinceDate:d] > 60.0 * 60.0 * 24.0 * 30.0) { //Too old so throw out
                [keysToDelete addObject:key];
            }
        }
        for (NSString *key in keysToDelete) {
            [_tvdbCache removeObjectForKey:key];
        }
	}
	return self;
}

-(void)metadataQueryHandler:(id)sender
{
	DDLogDetail(@"Got Metatdata Result with count %ld",[cTiVoQuery resultCount]);
	NSMutableDictionary *tmpDict = [NSMutableDictionary dictionary];
    NSData *buffer = [NSData dataWithData:[[NSMutableData alloc] initWithLength:256]];
	for (NSUInteger i =0; i < [cTiVoQuery resultCount]; i++) {
		NSString *filePath = [[cTiVoQuery resultAtIndex:i] valueForAttribute:NSMetadataItemPathKey];
		ssize_t len = getxattr([filePath cStringUsingEncoding:NSASCIIStringEncoding], [kMTXATTRTiVoID UTF8String], (void *)[buffer bytes], 256, 0, 0);
		if (len > 0) {
			NSData *idData = [NSData dataWithBytes:[buffer bytes] length:(NSUInteger)len];
			NSString  *showID = [[NSString alloc] initWithData:idData encoding:NSUTF8StringEncoding];
			len = getxattr([filePath cStringUsingEncoding:NSASCIIStringEncoding], [kMTXATTRTiVoName UTF8String], (void *)[buffer bytes], 256, 0, 0);
			if (len > 0) {
				NSData *nameData = [NSData dataWithBytes:[buffer bytes] length:len];
				NSString *tiVoName = [[NSString alloc] initWithData:nameData encoding:NSUTF8StringEncoding];
				NSString *key = [NSString stringWithFormat:@"%@: %@",tiVoName,showID];
				if ([tmpDict objectForKey:key]) {
					NSArray *paths = [tmpDict objectForKey:key];
					[tmpDict setObject:[paths arrayByAddingObject:filePath] forKey:key];
				} else {
					[tmpDict setObject:@[filePath] forKey:key];
				}
			}
		}

	}
	self.showsOnDisk = [NSDictionary dictionaryWithDictionary:tmpDict];
    [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationTiVoShowsUpdated object:nil];
	DDLogVerbose(@"showsOnDisk = %@",self.showsOnDisk);
    
}
#pragma mark - Loading queue from Preferences

-(void)updateShowOnDisk:(NSString *)key withPath:(NSString *)path
{
	NSMutableDictionary *tmpDict = [NSMutableDictionary dictionaryWithDictionary:self.showsOnDisk];
	if ([tmpDict objectForKey:key]) {
		NSArray *paths = [tmpDict objectForKey:key];
		[tmpDict setObject:[paths arrayByAddingObject:path] forKey:key];
	} else {
		[tmpDict setObject:@[path] forKey:key];
	}
	self.showsOnDisk = [NSDictionary dictionaryWithDictionary:tmpDict];
}

-(void) restoreOldQueue {
	
	NSArray *oldQueue = [[NSUserDefaults standardUserDefaults] objectForKey:kMTQueue];
	DDLogMajor(@"Restoring old Queue(%ld elements)",oldQueue.count);
	
	NSMutableArray * newShows = [NSMutableArray arrayWithCapacity:oldQueue.count];
	for (NSDictionary * queueEntry in oldQueue) {
		DDLogDetail(@"Restoring show %@",queueEntry[kMTQueueTitle]);
		MTDownload * newShow = [[MTDownload alloc] init];
		[newShow restoreDownloadData:queueEntry];
		[newShows addObject:newShow];
	}
	DDLogVerbose(@"Restored downloadQueue: %@",newShows);
	self.downloadQueue = newShows;

}

-(NSInteger) findProxyShowInDLQueue:(MTTiVoShow *) showTarget {
	NSString * targetTivoName = showTarget.tiVo.tiVo.name;
	return [self.downloadQueue indexOfObjectPassingTest:^BOOL(id obj, NSUInteger idx, BOOL *stop) {
		MTTiVoShow * possShow = ((MTDownload *) obj).show;
		return [targetTivoName isEqualToString:[possShow tempTiVoName]] &&
		showTarget.showID == possShow.showID;
		
	}];
}

-(void) replaceProxyInQueue: (MTTiVoShow *) newShow {
	NSInteger DLIndex =[tiVoManager findProxyShowInDLQueue:newShow];
	if (DLIndex != NSNotFound) {
		MTDownload * proxyDL = [tiVoManager downloadQueue][DLIndex];
		DDLogVerbose(@"Found proxy %@ at %ld on tiVo %@",newShow, DLIndex, proxyDL.show.tiVoName);
		proxyDL.show = newShow;
		//this is a back door entry into queue, so need to check for uniqueness again in current environment
//		[self checkShowTitleUniqueness:newShow];
		proxyDL.show.isQueued = YES;
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


#pragma mark - TiVo Search Methods

//-(void)loadManualTiVos
//{
//    
//    NSArray *startingTiVos = self.savedTiVos;
//	NSMutableArray *manualTiVoList = [NSMutableArray array];
//    
//    for (NSDictionary *tiVo in startingTiVos) {
//        if ([tiVo[kMTTiVoManualTiVo] boolValue] && [tiVo[kMTTiVoEnabled] boolValue]) {
//            MTNetService *newTiVoService = [[MTNetService alloc] init];
//			newTiVoService.userName = tiVo[kMTTiVoUserName];
//			newTiVoService.iPAddress = tiVo[kMTTiVoIPAddress];
//			newTiVoService.userPort = [tiVo[kMTTiVoUserPort] intValue];
//			newTiVoService.userPortSSL = [tiVo[kMTTiVoUserPortSSL] intValue];
//			MTTiVo *newTiVo = [MTTiVo tiVoWithTiVo:newTiVoService withOperationQueue:queue];
//			newTiVo.manualTiVoID = [tiVo[kMTTiVoID] intValue];
//			newTiVo.manualTiVo = YES;
//			newTiVo.enabled = YES;
//			DDLogDetail(@"Adding new manual TiVo %@",newTiVo);
//			[newTiVo updateShows:nil];
//            [manualTiVoList addObject:newTiVo];
//
//        }
//    }
//    self.tiVoList = [NSArray arrayWithArray:manualTiVoList];
//}

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
					targetMTTiVo = [MTTiVo manualTiVoWithDescription:mTiVo withOperationQueue:queue];
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
						[[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationShowListUpdated object:targetMTTiVo];
						//RE-update shows
						[targetMTTiVo updateShows:nil];
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
						[[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationShowListUpdated object:targetTiVo];
						targetTiVo.enabled = YES;
						targetTiVo.mediaKey = mTiVo[kMTTiVoMediaKey];
						[targetTiVo updateShows:nil];
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
    //have to wait until tivomanager is setup before calling subsidiary data models
	[self restoreOldQueue];
	
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

	[[NSUserDefaults standardUserDefaults] addObserver:self forKeyPath:kMTQueuePaused options:NSKeyValueObservingOptionNew context:nil];
	[[NSUserDefaults standardUserDefaults] addObserver:self forKeyPath:kMTScheduledOperations options:NSKeyValueObservingOptionNew context:nil];
	[[NSUserDefaults standardUserDefaults] addObserver:self forKeyPath:kMTScheduledEndTime options:NSKeyValueObservingOptionNew context:nil];
	[[NSUserDefaults standardUserDefaults] addObserver:self forKeyPath:kMTScheduledStartTime options:NSKeyValueObservingOptionNew context:nil];
	[[NSUserDefaults standardUserDefaults] addObserver:self forKeyPath:kMTTiVos options:NSKeyValueObservingOptionNew context:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(printTVDBStats)
                                                 name:kMTNotificationShowListUpdated
                                               object:nil];
    
}

-(void)printTVDBStats {
    DDLogMajor(@"Statistics for TVDB since start or reset: %@",self.theTVDBStatistics);
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
	if ([self anyTivoActive] && [askUser boolValue]) {
		NSAlert *scheduleAlert = [NSAlert alertWithMessageText:@"There are shows in process, and you are setting a scheduled time to start.  Should the current shows in process be rescheduled?" defaultButton:@"Reschedule" alternateButton: @"Cancel" otherButton: @"Complete stage of current shows" informativeTextWithFormat:@""];
		NSInteger returnValue = [scheduleAlert runModal];
		DDLogDetail(@"User said %ld to cancel alert",returnValue);
		if (returnValue == NSAlertDefaultReturn) {
			//We're rescheduling shows
            for (MTTiVo *tiVo in _tiVoList) {
				[tiVo rescheduleAllShows];
			}
			NSNotification *notification = [NSNotification notificationWithName:kMTNotificationDownloadQueueUpdated object:nil];
			[[NSNotificationCenter defaultCenter] performSelector:@selector(postNotification:) withObject:notification afterDelay:4.0];
            self.processingPaused = @(YES);
        } else if (returnValue == NSAlertAlternateReturn) {
            //no action:  self.processingPaused = @(NO);
        } else { //NSAlertOtherReturn
            self.processingPaused = @(YES);
        }
    } else {
        self.processingPaused = @(YES);
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
	if (targetSeconds < currentSeconds) {
		targetSeconds += 3600 * 24;
	}
	return targetSeconds - currentSeconds;
}

-(void)setQueueStartTime
{
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(unPauseQueue) object:nil];
	if (![[NSUserDefaults standardUserDefaults] boolForKey:kMTScheduledOperations]){
		DDLogDetail(@"Will not be restarting queue");
		return;
	}
	NSDate* startDate = [[NSUserDefaults standardUserDefaults] objectForKey:kMTScheduledStartTime];
    if (!startDate) startDate = [NSDate date];
	double targetSeconds = [self secondsUntilNextTimeOfDay:startDate];
	DDLogDetail(@"Will start queue in %f seconds (%f hours), due to beginDate of %@",targetSeconds, (targetSeconds/3600.0), startDate);
	[self performSelector:@selector(unPauseQueue) withObject:nil afterDelay:targetSeconds];
}

-(void)setQueueEndTime
{
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(pauseQueue:) object:@(NO)];
	if (![[NSUserDefaults standardUserDefaults] boolForKey:kMTScheduledOperations]) {
		DDLogDetail(@"Will not be pausing queue");
		return;
	}
	NSDate * endDate = [[NSUserDefaults standardUserDefaults] objectForKey:kMTScheduledEndTime];
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
    if ([keyPath isEqualToString:kMTTiVos]){
        [self updateTiVos];
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

-(void)resetAllDetails
{
	DDLogMajor(@"Resetting the caches!");
	//Remove TVDB Cache
    [[NSUserDefaults standardUserDefaults] setObject:@{} forKey:kMTTheTVDBCache];
	self.tvdbCache =  [NSMutableDictionary dictionary];
	self.tvdbSeriesIdMapping = [NSMutableDictionary dictionary];
	self.theTVDBStatistics = nil;
	
    //Remove TiVo Detail Cache
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *files = [fm contentsOfDirectoryAtPath:kMTTmpDetailsDir error:nil];
    for (NSString *file in files) {
        NSString *filePath = [NSString stringWithFormat:@"%@/%@",kMTTmpDetailsDir,file];
        [fm removeItemAtPath:filePath error:nil];
    }
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
    _selectedFormat = selectedFormat;
    [[NSUserDefaults standardUserDefaults] setObject:_selectedFormat.name forKey:kMTSelectedFormat];
}

-(MTFormat *) findFormat:(NSString *) formatName {
    for (MTFormat *fd in _formatList) {
        if ([formatName compare:fd.name] == NSOrderedSame) {
            return fd;
        }
    }
	//nobody found; let's see if one got renamed
    for (MTFormat *fd in _formatList) {
        if ([formatName compare:fd.formerName] == NSOrderedSame) {
            return fd;
        }
    }
	//Now do lookup on hardwired ones that got renamed!!
	NSDictionary *  oldFormats =
		@{@"Quicktime (H.264   10Mbps)" : @"H.264 High Quality ",
		  @"Quicktime (H.264   5Mbps)" : @"H.264 Medium Quality",
		  @"Quicktime (H.264   3Mbps)" : @"H.264 Low Quality",
		  @"Quicktime (H.264   1Mbps)" : @"H.264 Small 1Mbps",
		  @"Quicktime (H.264   256kbps)" : @"H.264 Very Small 256kbps"
		  };
	
	if (oldFormats[formatName]) {
		return [self findFormat:oldFormats[formatName]]; //recursion will stop assuming no circularity in oldFormats
	}
	return _formatList[0];
}
-(void)addEncFormatToList: (NSString *) filename {
	MTFormat * newFormat = [MTFormat formatWithEncFile:filename];
	[newFormat checkAndUpdateFormatName:tiVoManager.formatList];
	if (newFormat) [_formatList addObject:newFormat];
	[[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationFormatListUpdated object:nil];
	[[NSUserDefaults standardUserDefaults] setObject:tiVoManager.userFormatDictionaries forKey:kMTFormats];	
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
	[[NSUserDefaults standardUserDefaults] setObject:tiVoManager.userFormatDictionaries forKey:kMTFormats];
}


#pragma mark - Media Key Support

//-(NSDictionary *)currentMediaKeys
//{
//	NSMutableDictionary *tmpDict = [NSMutableDictionary dictionary];
//	for (MTTiVo *thisTiVo in [self allTiVos]) {
//		[tmpDict setObject:thisTiVo.mediaKey forKey:thisTiVo.tiVo.name];
//	}
//	return [NSDictionary dictionaryWithDictionary:tmpDict];
//}

//-(void)updateMediaKeysDefaults
//{
//	NSMutableDictionary *tmpDict = [NSMutableDictionary dictionary];
//	for (MTTiVo *tiVo in [self allTiVos]) {
//		[tmpDict setValue:tiVo.mediaKey forKey:tiVo.tiVo.name];
//	}
//	[[NSUserDefaults standardUserDefaults] setValue:tmpDict forKey:kMTMediaKeys];
//}
//
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



//-(void)checkShowTitleUniqueness:(MTTiVoShow *)program
//{
//    //Make sure the title isn't the same and if it is add a -1 modifier
//    for (MTDownload *download in _downloadQueue) {
//		if (download.show == program) continue;  //no need to check oneself
//        if ([download.show.showTitle compare:program.showTitle] == NSOrderedSame) {
//			NSRegularExpression *ending = [NSRegularExpression regularExpressionWithPattern:@"(.*)-([0-9]+)$" options:NSRegularExpressionCaseInsensitive error:nil];
//            NSTextCheckingResult *result = [ending firstMatchInString:program.showTitle options:NSMatchingWithoutAnchoringBounds range:NSMakeRange(0, program.showTitle.length)];
//            if (result) {
//                int n = [[program.showTitle substringWithRange:[result rangeAtIndex:2]] intValue];
//				DDLogVerbose(@"found show title %@, incrementing version number %d", program.showTitle, n);
//				program.showTitle = [[program.showTitle substringWithRange:[result rangeAtIndex:1]] stringByAppendingFormat:@"-%d",n+1];
//           } else {
//                program.showTitle = [program.showTitle stringByAppendingString:@"-1"];
//			   DDLogDetail(@"found show title %@, adding version number", program.showTitle);
//            }
//            [self checkShowTitleUniqueness:program];
//        }
//    }
//
//}

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

	[self.downloadQueue sortUsingComparator:^NSComparisonResult(MTDownload * download1, MTDownload* download2) {
		int status1 = download1.downloadStatus.intValue; if (status1 > kMTStatusDone) status1= kMTStatusDone; //sort failed/done together
		int status2 = download2.downloadStatus.intValue;if (status2 > kMTStatusDone) status2= kMTStatusDone;
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
		if ([download isEqual:proxyDownload]) {
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
            //if(![[NSUserDefaults standardUserDefaults] boolForKey:kMTAllowDups]) {
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
		MTDownload * newDownload = [[MTDownload alloc] init];
		newDownload.show = thisShow;
		newDownload.encodeFormat = [self selectedFormat];
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

//-(BOOL)playVideoForDownloads:(NSArray *) downloads {
//	for (MTDownload *download in downloads) {
//		if (download.isDone) {
//			if ([download playVideo])  {
//				return YES;		}
//		}
//	}
//	return NO;
//}
//
//-(BOOL)revealInFinderForDownloads:(NSArray *) downloads {
//	NSMutableArray * showURLs = [NSMutableArray arrayWithCapacity:downloads.count];
//	for (MTDownload *show in downloads) {
//		NSURL * showURL = [show videoFileURLWithEncrypted:YES];
//		if (showURL) {
//			[showURLs addObject:showURL];
//		}
//	}
//	if (showURLs.count > 0) {
//		[[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:showURLs];
//		return YES;
//	} else{
//		return NO;
//	}
//	
//}
#pragma mark - Growl/Apple Notifications

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
	[self notifyWithTitle:title subTitle:subTitle isSticky:NO forNotification:notification];
}

- (void)notifyWithTitle:(NSString *) title subTitle: (NSString*) subTitle isSticky:(BOOL)sticky forNotification: (NSString *) notification {
	DDLogReport(@"Notify: %@/%@: %@", title, subTitle, notification);
	Class GAB = NSClassFromString(@"GrowlApplicationBridge");
	if([GAB respondsToSelector:@selector(notifyWithTitle:description:notificationName:iconData:priority:isSticky:clickContext:identifier:)])
		[GAB notifyWithTitle: title
				 description: subTitle
			notificationName: notification
					iconData: nil  //use our app logo
					priority: 0
					isSticky: sticky
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
	numEncoders--;
    DDLogMajor(@"Num encoders after decrement from notification %@ is %d ",notification.name,numEncoders);
	if ([_quitWhenCurrentDownloadsComplete boolValue] && ![self tiVosProcessing]) {
		//Quit here
		[NSApp terminate:nil];
	}
//    [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationDownloadQueueUpdated object:nil];
    NSNotification *restartNotification = [NSNotification notificationWithName:kMTNotificationDownloadQueueUpdated object:nil];
    [[NSNotificationCenter defaultCenter] performSelector:@selector(postNotification:) withObject:restartNotification afterDelay:2];
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

//-(void)commercialFinished
//{
//	numCommercials--;
//    [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationDownloadQueueUpdated object:nil];
//    DDLogMajor(@"num commercials after decrement is %d",numCommercials);
//}
//
//-(void)captionFinished
//{
//	numCaptions--;
//    [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationDownloadQueueUpdated object:nil];
//    DDLogMajor(@"num captions after decrement is %d",numCaptions);
//}

-(void)writeDownloadQueueToUserDefaults {
	NSMutableArray * downloadArray = [NSMutableArray arrayWithCapacity:_downloadQueue.count];
	for (MTDownload * download in _downloadQueue) {
		[downloadArray addObject:[download queueRecord]];
	}
    DDLogVerbose(@"writing DL queue: %@", downloadArray);
	[[NSUserDefaults standardUserDefaults] setObject:downloadArray forKey:kMTQueue];
		
	[self.subscribedShows saveSubscriptions];
	[[NSUserDefaults standardUserDefaults] synchronize];

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

-(NSString *)tmpFilesDirectory {

    return [[NSUserDefaults standardUserDefaults] stringForKey:kMTTmpFilesDirectory];
 
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


//#include <ifaddrs.h>
//- (BOOL)isIPSelf:(NSData *)dataIn {
//	struct sockaddr *realSocketAddress = (struct sockaddr *)[dataIn bytes];
//	struct ifaddrs *ifap, *ifp;
//
//	if(getifaddrs(&ifap) < 0) {
//		DDLogMajor (@"getifaddr error: %d",getifaddrs(&ifap));
//		return NO;
//	}
//	
//	for(ifp = ifap; ifp; ifp = ifp->ifa_next) {
//		sa_family_t targetFamily = ifp->ifa_addr->sa_family;
//		if (realSocketAddress->sa_family == targetFamily) {
//			switch (targetFamily) {
//				case AF_INET: {
//					struct sockaddr_in  *socketAddress = (struct sockaddr_in *)realSocketAddress;
//					struct in_addr targetAddress = socketAddress->sin_addr;
//					struct in_addr myAddress = ((struct sockaddr_in*)ifp->ifa_addr)->sin_addr;
//					DDLogVerbose(@"Checking iPv4: %s-%s (%u) vs  %u",inet_ntoa(myAddress), ifp->ifa_name, myAddress.s_addr, targetAddress.s_addr);
//					if (myAddress.s_addr ==targetAddress.s_addr) {
//						freeifaddrs(ifap);
//						return YES;
//					}
//					break;
//				}
//				case AF_INET6: {
//					struct sockaddr_in6  *socketAddress6= (struct sockaddr_in6 *)realSocketAddress;
//					struct in6_addr targetAddress = socketAddress6->sin6_addr;
//					struct in6_addr myAddress = ((struct sockaddr_in6*)ifp->ifa_addr)->sin6_addr;
//					char myDest[INET6_ADDRSTRLEN];
//					inet_ntop(AF_INET6, &targetAddress, myDest, sizeof myDest);
//					
//					char targetDest[INET6_ADDRSTRLEN];
//					inet_ntop(AF_INET6, &targetAddress, targetDest, sizeof targetDest);
//					
//					DDLogVerbose(@"Checking: %s-%s",myDest, targetDest);
//
//					if (memcmp(&myAddress, &targetAddress, sizeof(myAddress))==0) {
//						freeifaddrs(ifap);
//						return YES;
//					}
//						break;
//				}
//				default: {
//					DDLogVerbose(@"Unrecognized IP family: %d",targetFamily);
//				}
//			}
//		}
//	}
//	// Free memory
//	freeifaddrs(ifap);
//	
//	return NO;
//}

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
//		DDLogDetail(@"Checking hostAddresses for %@",ipAddress);
//	for (NSString *hostAddress in self.hostAddresses) { //older, slower routine
//		if ([hostAddress caseInsensitiveCompare:ipAddress] == NSOrderedSame) {
//			return;  
//		}
//	}
//	for (NSData * addr in addresses) {
//		// This filters out PyTivo instances on the current host
//		if ([self isIPSelf:addr]) {
//			DDLogDetail(@"Found self at %@",ipAddress);
//			//return;
//		}
//	}
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
		DDLogVerbose(@"Comparing TiVo %@ address %@ to ipaddress %@",sender.name,tiVoAddress,ipAddress);
		if ([tiVoAddress caseInsensitiveCompare:ipAddress] == NSOrderedSame) {
			DDLogDetail(@"Found duplicate TiVo at %@",ipAddress);
			return;  // This filters out tivos that have already been found from a manual entry
		}
	}
    
	MTTiVo *newTiVo = [MTTiVo tiVoWithTiVo:sender withOperationQueue:queue];
    
    [newTiVo updateShows:nil];
  
	self.tiVoList = [_tiVoList arrayByAddingObject: newTiVo];
	if (self.tiVoList.count > 1 && ![[NSUserDefaults standardUserDefaults] boolForKey:kMTHasMultipleTivos]) {  //This is the first time we've found more than 1 tivo
		[[NSUserDefaults standardUserDefaults] setBool:YES forKey:kMTHasMultipleTivos];
		[[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationFoundMultipleTiVos object:nil];
	}
	DDLogMajor(@"Got new TiVo: %@ at %@", newTiVo, ipAddress);
	[[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationTiVoListUpdated object:nil];

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


@end

@implementation NSObject (maskMediaKeys)

-(NSString *) maskMediaKeys {
    NSString * outString =[self description];
    for (MTTiVo * tiVo in tiVoManager.tiVoList) {
        NSString * mediaKey = tiVo.mediaKey;
        NSString * maskedKey = [NSString stringWithFormat:@"<<%@MediaKey>>",tiVo.tiVo.name];
        outString = [outString stringByReplacingOccurrencesOfString:mediaKey                                        withString:maskedKey];
    }
    return outString;
}
    

@end
