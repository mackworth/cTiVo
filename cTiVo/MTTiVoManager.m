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

@synthesize subscribedShows = _subscribedShows, numEncoders;

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
- (id)retain {
    return self;
}

// Replace the retain counter so we can never release this object.
- (NSUInteger)retainCount {
    return NSUIntegerMax;
}

// This function is empty, as we don't want to let the user release this object.
- (oneway void)release {
    
}

//Do nothing, other than return the shared instance - as this is expected from autorelease.
- (id)autorelease {
    return self;
}


-(id)init
{
	self = [super init];
	if (self) {
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
        
        //Set user desired hiding of the user pref, if any
        
        NSArray *hiddenFormatNames = [defaults objectForKey:kMTHiddenFormats];
        if (hiddenFormatNames) {
            //Un hide all 
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
		}
        
		//If no selected format make it the first.
		if (!_selectedFormat) {
			self.selectedFormat = [_formatList objectAtIndex:0];
		}
		
		if (![defaults objectForKey:kMTMediaKeys]) {
			[defaults setObject:[NSDictionary dictionary] forKey:kMTMediaKeys];
		}
		
		self.downloadDirectory  = [defaults objectForKey:kMTDownloadDirectory];
		
		self.oldQueue = [[NSUserDefaults standardUserDefaults] objectForKey:kMTQueue];
		
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
		queue.maxConcurrentOperationCount = 1;
		
		_videoListNeedsFilling = YES;
        updatingVideoList = NO;
		
		[self loadGrowl];
//		NSLog(@"Getting Host Addresses");
//		hostAddresses = [[[NSHost currentHost] addresses] retain];
//        NSLog(@"Host Addresses = %@",self.hostAddresses);
//        NSLog(@"Host Names = %@",[[NSHost currentHost] names]);
//        NSLog(@"Host addresses for first name %@",[[NSHost hostWithName:[[NSHost currentHost] names][0]] addresses]);
        
	}
	return self;
}

#pragma mark - TiVo Search Methods

-(void)loadManualTiVos
{
    BOOL didFindTiVo = NO;
	NSMutableArray *manualTiVoList = [NSMutableArray arrayWithArray:[_tiVoList filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"manualTiVo == YES"]]];
	[_tiVoList removeObjectsInArray:manualTiVoList];
    NSMutableArray *manualTiVoDescriptions = [NSMutableArray arrayWithArray:[[NSUserDefaults standardUserDefaults] arrayForKey:kMTManualTiVos]];
	//Validate array
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
		[manualTiVoDescriptions removeObjectsInArray:itemsToRemove];
		[[NSUserDefaults standardUserDefaults] setObject:manualTiVoDescriptions forKey:kMTManualTiVos];
	}
	
    for (NSDictionary *manualTiVoDescription in manualTiVoDescriptions) {
		//Check for exisitng
		MTNetService *newTiVoService = nil;
		MTTiVo *newTiVo = nil;
		for (MTTiVo *tivo in manualTiVoList) {
			if ([tivo.tiVo.iPAddress compare:manualTiVoDescription[@"iPAddress"]] == NSOrderedSame) {
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
		}
		if (newTiVo.enabled) {
			//Remove any matching ip address already in _tiVoList
			NSMutableArray *itemsToRemove = [NSMutableArray array];
			for (MTTiVo *tiVo in _tiVoList) {
				NSString *ipaddr = [self getStringFromAddressData:[tiVo.tiVo addresses][0]];
				if ([ipaddr compare:newTiVo.tiVo.iPAddress] == NSOrderedSame) {
					[itemsToRemove addObject:tiVo];
				}
			}
			[_tiVoList removeObjectsInArray:itemsToRemove];
			[_tiVoList addObject:newTiVo];
			didFindTiVo = YES;
		}
    }
//    if (didFindTiVo) {
        NSNotification *notification = [NSNotification notificationWithName:kMTNotificationTiVoListUpdated object:nil];
        [[NSNotificationCenter defaultCenter] performSelectorOnMainThread:@selector(postNotification:) withObject:notification waitUntilDone:NO];
//    }
	if (tivoBrowser) {
		[tivoBrowser stop];
		[_tivoServices removeAllObjects];
		[tivoBrowser searchForServicesOfType:@"_tivo-videos._tcp" inDomain:@"local"];
	}
}


-(void)searchForBonjourTiVos
{
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
    return addresses;
}

-(NSArray *)tiVoList
{
	NSSortDescriptor *manualSort = [NSSortDescriptor sortDescriptorWithKey:@"manualTiVo" ascending:NO];
	NSSortDescriptor *nameSort = [NSSortDescriptor sortDescriptorWithKey:@"tiVo.name" ascending:YES];
	return [_tiVoList sortedArrayUsingDescriptors:[NSArray arrayWithObjects:manualSort,nameSort, nil]];
}

-(void) setupNotifications {
    //have to wait until tivomanager is setup before calling subsidiary data models
    NSNotificationCenter *defaultCenter = [NSNotificationCenter defaultCenter];
    
    [defaultCenter addObserver:self selector:@selector(encodeFinished) name:kMTNotificationEncodeDidFinish object:nil];
    [defaultCenter addObserver:self selector:@selector(encodeFinished) name:kMTNotificationEncodeWasCanceled object:nil];
    [defaultCenter addObserver:self.subscribedShows selector:@selector(checkSubscription:) name: kMTNotificationDetailsLoaded object:nil];
    [defaultCenter addObserver:self.subscribedShows selector:@selector(updateSubscriptionWithDate:) name:kMTNotificationEncodeDidFinish object:nil];
}


-(NSMutableArray *) subscribedShows {
    
	if (_subscribedShows ==  nil) {

            _subscribedShows = [NSMutableArray new];
        [_subscribedShows loadSubscriptions];
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
                program.showTitle = [[program.showTitle substringWithRange:[result rangeAtIndex:1]] stringByAppendingFormat:@"-%d",n+1];
            } else {
                program.showTitle = [program.showTitle stringByAppendingString:@"-1"];
            }
            [self checkShowTitleUniqueness:program];
        }
    }

}
-(NSIndexSet *) moveShowsInDownloadQueue:(NSArray *) shows
								 toIndex:(NSUInteger)insertIndex
{
	NSMutableIndexSet *fromIndexSet = [NSMutableIndexSet indexSet  ];
	for (MTTiVoShow * show in shows) {
		NSUInteger index = [[tiVoManager downloadQueue] indexOfObject :show];
		//can't move an inprogress/canceled/failed one.
		if (index != NSNotFound && (show.downloadStatus.intValue == kMTStatusNew)) {
			[fromIndexSet addIndex:index];
		}
	}
	if (fromIndexSet.count ==0) return nil;
	
	// If any of the removed objects come before the insertion index,
	// we need to decrement the index appropriately
	NSMutableArray * dlQueue = [self downloadQueue];
	NSUInteger adjustedInsertIndex = insertIndex -
	[fromIndexSet countOfIndexesInRange:(NSRange){0, insertIndex}];
	NSRange destinationRange = NSMakeRange(adjustedInsertIndex, [fromIndexSet count]);
	NSIndexSet *destinationIndexes = [NSIndexSet indexSetWithIndexesInRange:destinationRange];
	
	NSArray *objectsToMove = [dlQueue objectsAtIndexes:fromIndexSet];
	[dlQueue removeObjectsAtIndexes: fromIndexSet];
	[dlQueue insertObjects:objectsToMove atIndexes:destinationIndexes];
	
	return destinationIndexes;
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
                    programFound = YES;
					break;
                }
            }
            
            if (!programFound) {
                //Make sure the title isn't the same and if it is add a -1 modifier
                submittedAny = YES;
                [self checkShowTitleUniqueness:program];
                program.isQueued = YES;
                program.numRetriesRemaining = kMTMaxDownloadRetries;
                program.numStartupRetriesRemaining = kMTMaxDownloadStartupRetries;
				if (!program.downloadDirectory) {
					program.downloadDirectory = tiVoManager.downloadDirectory;
				}
				if (nextShow) {
                    NSUInteger index = [_downloadQueue indexOfObject:nextShow];
                    if (index == NSNotFound) {
                        [_downloadQueue addObject:program];
                        
                    } else {
                        [_downloadQueue insertObject:program atIndex:index];
                    }
                } else {
                    [_downloadQueue addObject:program];
                }
            }
        }
	}
	if (submittedAny){
		[[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationTiVoShowsUpdated object:nil];
        [[NSNotificationCenter defaultCenter ] postNotificationName:  kMTNotificationDownloadQueueUpdated object:nil];
	}
}


-(void) downloadShowsWithCurrentOptions:(NSArray *) shows beforeShow:(MTTiVoShow *) nextShow {
	for (MTTiVoShow * thisShow in shows) {
		thisShow.encodeFormat = [self selectedFormat];
		thisShow.addToiTunesWhenEncoded = thisShow.encodeFormat.canAddToiTunes &&
											[[NSUserDefaults standardUserDefaults] boolForKey:kMTiTunesSubmit];
		thisShow.simultaneousEncode = thisShow.encodeFormat.canSimulEncode &&
											[[NSUserDefaults standardUserDefaults] boolForKey:kMTSimultaneousEncode];
		thisShow.downloadDirectory = tiVoManager.downloadDirectory;
	}
	[self addProgramsToDownloadQueue:shows beforeShow:nextShow ];
}

- (void) noRecordingAlertDidEnd:(NSAlert *)alert returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo
{
    MTTiVoShow * show = (MTTiVoShow *) contextInfo;
	[self deleteProgramsFromDownloadQueue: @[show] ];
    
}

-(void) deleteProgramsFromDownloadQueue:(NSArray *) programs {
    NSMutableIndexSet * itemsToRemove= [NSMutableIndexSet indexSet];
	for (MTTiVoShow * program in programs) {

		NSUInteger index = [_downloadQueue indexOfObject:program];
		if (index == NSNotFound) {
			for (MTTiVoShow *p in _downloadQueue) {  //this is probably unncessary
				if (p.showID == program.showID	) {
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
		[_downloadQueue removeObjectsAtIndexes:itemsToRemove];
		[[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationTiVoShowsUpdated object:nil];
		[[NSNotificationCenter defaultCenter ] postNotificationName:  kMTNotificationDownloadStatusChanged object:nil];
//			NSLog(@"QQQ setting DLQueueUpdated post");
		NSNotification *downloadQueueNotification = [NSNotification notificationWithName:kMTNotificationDownloadQueueUpdated object:nil];
		[[NSNotificationCenter defaultCenter] performSelector:@selector(postNotification:) withObject:downloadQueueNotification afterDelay:4.0];
	}
}

-(NSInteger)numberOfShowsToDownload
{
	NSInteger n= 0;
	for (MTTiVoShow *s in _downloadQueue) {
		if (!([s.downloadStatus intValue] == kMTStatusDone || [s.downloadStatus intValue] == kMTStatusFailed)) {
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
			NSLog(@"Using Growl.framework %@ (%@)",
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
	for (MTTiVo *tiVo in self.tiVoList) {
		if ([tiVo.tiVo.name compare:tiVoName] == NSOrderedSame) {
			ret = YES;
			break;
		}
	}
	return ret;
}

-(NSArray *)downloadQueueForTiVo:(MTTiVo *)tiVo
{
    return [_downloadQueue filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"tiVo.tiVo.name == %@",tiVo.tiVo.name]];
}


-(void)encodeFinished
{
	numEncoders--;
    [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationDownloadQueueUpdated object:nil];
    //NSLog(@"num decoders after decrement is %d",numEncoders);
}

-(void)writeDownloadQueueToUserDefaults {
	NSMutableArray * downloadArray = [NSMutableArray arrayWithCapacity:_downloadQueue.count];
	for (MTTiVoShow * show in _downloadQueue) {
		if (show.isInProgress){
			[show cancel];	
		}
		[downloadArray addObject:[show queueRecord]];
								
	}
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
				newDir = nil;	
			}
		}
		if (!newDir) {
			// nil, or it was bad
			newDir = [self defaultDownloadDirectory];
			
			if (![self checkDirectory:newDir]) {
				//whoa. very bad things in user directory land
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
	for (MTTiVo *tv in _tiVoList) {
		[totalShows addObjectsFromArray:tv.shows];
	}
	return totalShows;
}


#pragma mark - Bonjour browser delegate methods

- (void)netServiceBrowser:(NSNetServiceBrowser *)netServiceBrowser didFindService:(NSNetService *)netService moreComing:(BOOL)moreServicesComing
{
	NSLog(@"Found Service %@",netService);
    for (NSNetService * prevService in _tivoServices) {
        if ([prevService.name compare:netService.name] == NSOrderedSame) {
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

	for (NSString *hostAddress in self.hostAddresses) {
		if ([hostAddress caseInsensitiveCompare:ipAddress] == NSOrderedSame) {
			return;  // This filters out PyTivo instances on the current host
		}
	}

	for (NSString *tiVoAddress in [self tiVoAddresses]) {
//        NSLog(@"Comparing tiVo %@ address %@ to ipaddress %@",sender.name,tiVoAddress,ipAddress);
		if ([tiVoAddress caseInsensitiveCompare:ipAddress] == NSOrderedSame) {
			return;  // This filters out tivos that have already been found from a manual entry
		}
	}
    
    if ([sender.name rangeOfString:@"Py"].location == NSNotFound) {
        MTTiVo *newTiVo = [MTTiVo tiVoWithTiVo:sender withOperationQueue:queue];
      
        [_tiVoList addObject:newTiVo];
        [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationTiVoListUpdated object:nil];
    } else {
        NSLog(@"PyAddress: %@ not in hostAddresses = %@", ipAddress, self.hostAddresses);
    }
}

-(void)netService:(NSNetService *)sender didNotResolve:(NSDictionary *)errorDict
{
    NSLog(@"Service %@ failed to resolve",sender.name);
}

- (NSString *)getStringFromAddressData:(NSData *)dataIn {
    struct sockaddr_in  *socketAddress = nil;
    NSString            *ipString = nil;
	
    socketAddress = (struct sockaddr_in *)[dataIn bytes];
    ipString = [NSString stringWithFormat: @"%s",
                inet_ntoa(socketAddress->sin_addr)];  ///problem here
    return ipString;
}


@end
