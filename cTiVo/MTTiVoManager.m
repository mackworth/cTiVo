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

#include <arpa/inet.h>

@interface MTTiVoManager ()

@property (retain) NSNetService *updatingTiVo;
@property (nonatomic, retain) NSArray *hostAddresses;

@end


@implementation MTTiVoManager

@synthesize subscribedShows = _subscribedShows;

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
		
		tivoBrowser = [NSNetServiceBrowser new];
		tivoBrowser.delegate = self;
		[tivoBrowser scheduleInRunLoop:[NSRunLoop mainRunLoop] forMode:NSDefaultRunLoopMode];
		[tivoBrowser searchForServicesOfType:@"_tivo-videos._tcp" inDomain:@"local"];
		_tivoServices = [NSMutableArray new];
		listingData = [NSMutableData new];
		_tiVoList = [NSMutableArray new];
		queue = [NSOperationQueue new];
		_downloadQueue = [NSMutableArray new];

		NSString *formatListPath = [[NSBundle mainBundle] pathForResource:@"formats" ofType:@"plist"];
		NSDictionary *formats = [NSDictionary dictionaryWithContentsOfFile:formatListPath];
		_formatList = [[NSMutableArray arrayWithArray:[formats objectForKey:@"formats"] ] retain];
		
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
		if (![defaults objectForKey:kMTDownloadDirectory]) {
			NSString *ddir = [NSString stringWithFormat:@"%@/Downloads/",NSHomeDirectory()];
			[defaults setValue:ddir forKey:kMTDownloadDirectory];
		}
		_downloadDirectory = [defaults objectForKey:kMTDownloadDirectory];
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
		
		_addToItunes = NO;
		_simultaneousEncode = YES;
		_videoListNeedsFilling = YES;
        updatingVideoList = NO;
//		NSLog(@"Getting Host Addresses");
//		hostAddresses = [[[NSHost currentHost] addresses] retain];
//        NSLog(@"Host Addresses = %@",self.hostAddresses);
//        NSLog(@"Host Names = %@",[[NSHost currentHost] names]);
//        NSLog(@"Host addresses for first name %@",[[NSHost hostWithName:[[NSHost currentHost] names][0]] addresses]);
        
	}
	return self;
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

-(void) setupNotifications {
    //have to wait until tivomanager is setup before calling subsidiary data models
    NSNotificationCenter *defaultCenter = [NSNotificationCenter defaultCenter];
    
    [defaultCenter addObserver:self selector:@selector(manageDownloads) name:kMTNotificationDownloadQueueUpdated object:nil];
    [defaultCenter addObserver:self selector:@selector(manageDownloads) name:kMTNotificationDownloadDidFinish object:nil];
    [defaultCenter addObserver:self selector:@selector(manageDownloads) name:kMTNotificationDecryptDidFinish object:nil];
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


-(void)setSelectedFormat:(NSDictionary *)selectedFormat
{
    if (selectedFormat == _selectedFormat) {
        return;
    }
    [_selectedFormat release];
    _selectedFormat = [selectedFormat retain];
    [[NSUserDefaults standardUserDefaults] setObject:[_selectedFormat objectForKey:@"name"] forKey:kMTSelectedFormat];
}

-(NSDictionary *) findFormat:(NSString *) formatName {
    for (NSDictionary *fd in _formatList) {
        if ([formatName compare:fd[@"name"]] == NSOrderedSame) {
            return fd;
        }
    }
    return nil;
}

-(NSDictionary *)currentMediaKeys
{
	NSMutableDictionary *tmpDict = [NSMutableDictionary dictionary];
	for (MTTiVo *thisTiVo in _tiVoList) {
		[tmpDict setObject:thisTiVo.mediaKey forKey:thisTiVo.tiVo.name];
	}
	return [NSDictionary dictionaryWithDictionary:tmpDict];
}

-(BOOL) canAddToiTunes:(NSDictionary *) format {
    return [format[@"iTunes"] boolValue];
}

-(BOOL) canSimulEncode:(NSDictionary *) format {
	return [format[@"iTunes"] boolValue];
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

-(void)addProgramToDownloadQueue:(MTTiVoShow *)program
{
	BOOL programFound = NO;
	for (MTTiVoShow *p in _downloadQueue) {
		if (p.showID == program.showID	) {
			programFound = YES;
		}
	}
	
	if (!programFound) {
        //Make sure the title isn't the same and if it is add a -1 modifier
        [self checkShowTitleUniqueness:program];
        program.isQueued = YES;
		NSString *tryDirectory = _downloadDirectory;
		//Check that download directory exists.  If create it.  If unsuccessful use default ~/Movies
		if (![[NSFileManager defaultManager] fileExistsAtPath:tryDirectory]) { // try to create it
			if (![[NSFileManager defaultManager] createDirectoryAtPath:tryDirectory withIntermediateDirectories:YES attributes:nil error:nil]) { //Go to default if not successful
				tryDirectory = [NSString stringWithFormat:@"%@/Movies",NSHomeDirectory()];
			}
		}
		program.downloadDirectory = tryDirectory;
		program.numRetriesRemaining = kMTMaxDownloadRetries;
		[_downloadQueue addObject:program];
        [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationTiVoShowsUpdated object:nil];
        [[NSNotificationCenter defaultCenter ] postNotificationName:  kMTNotificationDownloadQueueUpdated object:self];
	}
}

-(void) downloadthisShowWithCurrentOptions:(MTTiVoShow*) thisShow {
	thisShow.encodeFormat = [self selectedFormat];
	thisShow.addToiTunesWhenEncoded = [self canAddToiTunes:thisShow.encodeFormat] &&
                                        self.addToItunes;
	thisShow.simultaneousEncode = [self canSimulEncode:thisShow.encodeFormat] &&
                                        self.simultaneousEncode;
    [self addProgramToDownloadQueue:thisShow];
}

-(void) deleteProgramFromDownloadQueue:(MTTiVoShow *) program {
    BOOL programFound = NO;
	for (MTTiVoShow *p in _downloadQueue) {
		if (p.showID == program.showID	) {
			programFound = YES;
            break;
		}
	}
	
	if (programFound) {
        [program cancel];
        program.isQueued = NO;
        [_downloadQueue removeObject:program];
        [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationTiVoShowsUpdated object:nil];
        [[NSNotificationCenter defaultCenter ] postNotificationName:  kMTNotificationDownloadStatusChanged object:nil];
		NSNotification *downloadQueueNotification = [NSNotification notificationWithName:kMTNotificationDownloadQueueUpdated object:self];
		[[NSNotificationCenter defaultCenter] performSelector:@selector(postNotification:) withObject:downloadQueueNotification afterDelay:4.0];
	}
}


-(void)manageDownloads
{
    //We are only going to have one each of Downloading, Encoding, and Decrypting.  So scan to see what currently happening
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(manageDownloads) object:nil];
    BOOL isDownloading = NO, isDecrypting = NO;
    for (MTTiVoShow *s in _downloadQueue) {
        if ([s.downloadStatus intValue] == kMTStatusDownloading) {
            isDownloading = YES;
        }
        if ([s.downloadStatus intValue] == kMTStatusDecrypting) {
            isDecrypting = YES;
        }
    }
    if (!isDownloading) {
        for (MTTiVoShow *s in _downloadQueue) {
            if ([s.downloadStatus intValue] == kMTStatusNew && (numEncoders < kMTMaxNumDownloaders || !s.simultaneousEncode)) {
                if(s.tiVo.isReachable) {
                    if (s.simultaneousEncode) {
                        numEncoders++;
                    }
                    [s download];
                } else {    //We'll try again in kMTRetryNetworkInterval seconds at a minimum;
                    [s.tiVo reportNetworkFailure];
                    NSLog(@"Could not reach %@ tivo will try later",s.tiVo.tiVo.name);
                    [self performSelector:@selector(manageDownloads) withObject:nil afterDelay:kMTRetryNetworkInterval];
                }
                break;
            }
        }
    }
    if (!isDecrypting) {
        for (MTTiVoShow *s in _downloadQueue) {
            if ([s.downloadStatus intValue] == kMTStatusDownloaded && !s.simultaneousEncode) {
                [s decrypt];
                break;
            }
        }
    }
    if (numEncoders < kMTMaxNumDownloaders) {
        for (MTTiVoShow *s in _downloadQueue) {
            if ([s.downloadStatus intValue] == kMTStatusDecrypted && numEncoders < kMTMaxNumDownloaders) {
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
    //NSLog(@"num decoders after decrement is %d",numEncoders);
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
    [netService resolveWithTimeout:4.0];
}

#pragma mark - NetService delegate methods

- (void)netServiceDidResolveAddress:(NSNetService *)sender
{
	NSString *ipAddress = @"";
	if ([sender addresses] && [sender addresses].count) {
		ipAddress = [self getStringFromAddressData:[sender addresses][0]];
		
	}

	for (NSString *hostAddress in self.hostAddresses) {
		if ([hostAddress caseInsensitiveCompare:ipAddress] == NSOrderedSame) {
			return;  // This filters out PyTivo instances on the current host
		}
	}

	MTTiVo *newTiVo = [MTTiVo tiVoWithTiVo:sender withOperationQueue:queue];
    [_tiVoList addObject:newTiVo];
    [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationTiVoListUpdated object:nil];
    
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
