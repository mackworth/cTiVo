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

@property (nonatomic, strong) NSArray <MTTiVo *> *tiVoList;
@property (nonatomic, readonly) NSArray <MTTiVoShow *> *tiVoShows;
@property (nonatomic, strong) NSMutableArray <MTFormat *> *formatList;
@property (nonatomic, strong) NSMutableDictionary <NSString *, NSDate *> *lastLoadedTivoTimes;
@property (atomic, strong) NSMutableArray <MTDownload *> *downloadQueue;
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
-(void) addToDownloadQueue:(NSArray *)downloads beforeDownload:(MTDownload *) nextShow;
-(void) downloadShowsWithCurrentOptions:(NSArray *) shows beforeDownload:(MTDownload *) nextShow;
-(void) deleteFromDownloadQueue:(NSArray *)downloads;
-(NSIndexSet *) moveShowsInDownloadQueue:(NSArray *) downloads
								 toIndex:(NSUInteger)insertIndex;
-(void) sortDownloadQueue;
-(NSArray *) currentDownloadQueueSortedBy: (NSArray*) sortDescripters;
-(BOOL) sharedShowWith:(MTDownload *) download; //true if another download shares this download's show

-(NSArray <MTDownload *> *) downloadsForShow: (MTTiVoShow *) show;
-(BOOL) anyShowsWaiting;
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

-(NSArray *)downloadQueueForTiVo:(MTTiVo *)tiVo;

//---------------Download Queue starting/stopping ----------
-(void)pauseQueue:(NSNumber *)askUser;
-(void)unPauseQueue;
-(void)determineCurrentProcessingState;

//---------------Format Management methods ----------
-(NSArray *)userFormats;
-(NSArray *)userFormatDictionaries;
-(MTFormat *) findFormat:(NSString *) formatName;
-(MTFormat *) testPSFormat;
-(void)addFormatsToList:(NSArray *)formats withNotification:(BOOL) notify;
-(void)addEncFormatToList: (NSString *) filename ;

//---------------TiVo Management methods ----------
-(BOOL)foundTiVoNamed:(NSString *)tiVoName;
-(void)refreshAllTiVos;
-(void)resetAllDetails;
-(NSArray *)allTiVos;
-(BOOL)anyTivoActive;
-(int) nextManualTiVoID;
-(BOOL) duplicateTiVoFor: (MTTiVo *)tiVo;
-(void) updateTiVoDefaults:(MTTiVo *)tiVo;

//---------------TiVo Management methods ----------
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

//---------------Other methods ----------
-(void) notifyWithTitle:(NSString *) title subTitle: (NSString*) subTitle;
- (void)notifyForName: (NSString *) objName withTitle:(NSString *) title subTitle: (NSString*) subTitle isSticky:(BOOL)sticky ;

-(NSArray <NSString *> *) copiesOnDiskForShow:(MTTiVoShow *) show;
-(void) addShow:(MTTiVoShow *) show onDiskAtPath:(NSString *)path;

-(void) updateManualInfo:(NSDictionary *) info forShow: (MTTiVoShow *) show;
-(NSDictionary *) getManualInfo: (MTTiVoShow *) show;

-(NSString *)getAMediaKey;
-(BOOL) checkForExit;

@end

@interface NSObject (maskMediaKeys)
//strip out all mediakeys in debug log
-(NSString *) maskMediaKeys;

@end
