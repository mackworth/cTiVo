//
//  MTNetworkTivos.h
//  myTivo
//
//  Created by Scott Buchanan on 12/6/12.
//  Copyright (c) 2012 Scott Buchanan. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "NSString+HTML.h"
#import "MTTiVoShow.h"
#import "MTDownload.h"
#import "MTTiVo.h"
#import "MTSubscription.h"
#import <SystemConfiguration/SystemConfiguration.h>
#import "MTFormat.h"
#import "MTTVDB.h"

@interface MTTiVoManager : NSObject <NSNetServiceBrowserDelegate, NSNetServiceDelegate, NSURLConnectionDataDelegate, NSURLConnectionDelegate, NSTextFieldDelegate, NSAlertDelegate>  {
}

//Shared Data

@property (nonatomic, readonly) NSArray <MTTiVo *> *tiVoList;
@property (nonatomic, readonly) NSArray <MTTiVo *> *tiVoMinis;
@property (nonatomic, readonly) NSArray <MTTiVoShow *> *tiVoShows;
@property (nonatomic, strong) NSMutableArray <MTFormat *> *formatList;
@property (nonatomic, strong) NSMutableDictionary <NSString *, NSDate *> *lastLoadedTivoTimes;
@property (nonatomic, readonly) NSDictionary <NSString *, NSDictionary <NSString *, NSString *> *> *channelList; //union of all TiVos' channelLists

@property (atomic, strong) NSMutableArray <MTDownload *> *downloadQueue;    //should move to private property

@property (nonatomic, strong) NSMutableArray <MTSubscription *> *subscribedShows;

@property (nonatomic, strong)  NSString *downloadDirectory;
@property (nonatomic,readonly) NSString *tmpFilesDirectory;
@property (nonatomic,readonly) NSURL *tivoTempDirectory;
@property (nonatomic,readonly) NSURL *tvdbTempDirectory;
@property (nonatomic,readonly) NSURL *detailsTempDirectory;
@property (readonly) NSArray <NSDictionary <NSString * , NSString *> *> *savedTiVos;
@property int volatile signalError;

//Other Properties
@property (nonatomic, strong) MTTVDB *tvdb;

@property (nonatomic, strong) MTFormat *selectedFormat;
@property (atomic) int numEncoders;
@property (nonatomic,readonly) int totalShows; // numCommercials, numCaptions;//Want to limit launches to two encoders.
@property (nonatomic, strong) NSNumber *processingPaused;
@property (nonatomic, readonly) BOOL anyShowsCompleted;
@property (nonatomic, readonly) double aggregateSpeed; //sum of the speed of all downloads .
@property (nonatomic, readonly)  NSTimeInterval aggregateTimeLeft; 

+ (MTTiVoManager *)sharedTiVoManager;

#define tiVoManager [MTTiVoManager sharedTiVoManager]

//---------------Download Queue Manager methods ----------
-(void) cancelAllDownloads;
-(NSArray <MTDownload *> *) addToDownloadQueue:(NSArray <MTDownload *> *)downloads beforeDownload:(MTDownload *) nextShow;
-(NSArray <MTDownload *> *) downloadShowsWithCurrentOptions:(NSArray<MTTiVoShow *> *) shows beforeDownload:(MTDownload *) nextShow;
-(void) deleteFromDownloadQueue:(NSArray <MTDownload *>*)downloads;
-(void) rescheduleDownloads: (NSArray <MTDownload *> *) downloads;
-(NSIndexSet *) moveShowsInDownloadQueue:(NSArray <MTDownload *> *) downloads
								 toIndex:(NSUInteger)insertIndex;
-(void) sortDownloadQueue;
-(NSArray <MTDownload *> *) currentDownloadQueueSortedBy: (NSArray <NSSortDescriptor *> *) sortDescripters;
-(BOOL) sharedShowWith:(MTDownload *) download; //true if another download shares this download's show

-(NSArray <MTDownload *> *) downloadsForShow: (MTTiVoShow *) show;
-(BOOL) anyShowsWaiting;
-(void) checkSleep: (NSNotification *) notification;
-(void) preventSleep;

-(NSInteger)numberOfShowsToDownload;
-(long long)sizeOfShowsToDownload;
-(long long)biggestShowToDownload;
-(void) clearDownloadHistory;

//---------------Download Queue userDefaults writing/reading  ----------
-(void)saveState;
-(MTDownload *) findRealDownload: (MTDownload *) proxyDownload;
-(MTTiVoShow *) findRealShow:(MTTiVoShow *) showTarget;
-(MTTiVoShow *) replaceProxyInQueue: (MTTiVoShow *) newShow;
-(void) checkDownloadQueueForDeletedEntries: (MTTiVo *) tiVo;

-(NSArray <MTDownload *> *)downloadQueueForTiVo:(MTTiVo *)tiVo;

//---------------Download Queue starting/stopping ----------
-(void)pauseQueue:(NSNumber *)askUser;
-(void)unPauseQueue;
-(void)determineCurrentProcessingState;

//---------------Format Management methods ----------
-(NSArray <MTFormat *> *)userFormats;
-(NSArray <NSDictionary *> *)userFormatDictionaries;
-(MTFormat *) findFormat:(NSString *) formatName;
-(MTFormat *) testPSFormat;
-(void)addFormatsToList:(NSArray <MTFormat *> *)formats withNotification:(BOOL) notify;
-(void)addEncFormatToList: (NSString *) filename ;

//---------------TiVo Management methods ----------
-(BOOL)foundTiVoNamed:(NSString *)tiVoName;
-(void)refreshAllTiVos;
-(void)resetAllDetails;
-(BOOL)anyTivoActive;
-(int) nextManualTiVoID;
-(BOOL) duplicateTiVoFor: (MTTiVo *)tiVo;
-(void) updateTiVoDefaults:(MTTiVo *)tiVo;

//---------------TiVo Management methods ----------
-(void) startTiVos;
-(void) deleteTivoShows: (NSArray <MTTiVoShow *> *) shows;
-(void) stopRecordingShows: (NSArray <MTTiVoShow *> *) shows;
-(void) getSkipModeEDLWhenPossible: (MTDownload *) download;
-(void) skipModeRetrieval: (NSArray <MTTiVoShow *> *) shows interrupting: (BOOL) interrupt;
-(BOOL) autoSkipModeScanAllowedNow;

//----------------Channel Management Methods --------
-(void) createChannel;
-(void) sortChannelsAndMakeUnique;
-(void) removeAllChannelsStartingWith: (NSString*) prefix;
-(NSCellStateValue) useTSForChannel:(NSString *) channelName;
-(void) setFailedPS:(BOOL) psFailed forChannelNamed: (NSString *) channelName;
-(NSCellStateValue) failedPSForChannel:(NSString *) channelName;
-(NSCellStateValue) commercialsForChannel:(NSString *) channelName;
-(NSCellStateValue) skipModeForChannel:(NSString *) channelName;
-(void) testAllChannelsForPS;
-(void) removeAllPSTests;
-(void) channelsChanged:(MTTiVo *) tiVo; //notify TM to update channellist


//---------------Other methods ----------
-(void) notifyWithTitle:(NSString *) title subTitle: (NSString*) subTitle;
- (void)notifyForName: (NSString *) objName withTitle:(NSString *) title subTitle: (NSString*) subTitle isSticky:(BOOL)sticky ;

-(NSArray <NSString *> *) copiesOnDiskForShow:(MTTiVoShow *) show;
-(void) addShow:(MTTiVoShow *) show onDiskAtPath:(NSString *)path;
-(void) launchMetadataQuery;

-(void) updateManualInfo:(NSDictionary *) info forShow: (MTTiVoShow *) show;
-(NSDictionary *) getManualInfo: (MTTiVoShow *) show;

-(NSString *)getAMediaKey;
-(BOOL) checkForExit;

-(void)revealInFinderDownloads:(NSArray <MTDownload *> *) downloads;
-(void)revealInFinderShows:(NSArray <MTTiVoShow *> *) shows;
-(NSArray <MTTiVoShow *> *) showsForDownloads:(NSArray <MTDownload *> *) downloads includingDone: (BOOL) includeDone;

@end

@interface NSObject (maskMediaKeys)
//strip out all mediakeys in debug log
-(NSString *) maskMediaKeys;

@end
