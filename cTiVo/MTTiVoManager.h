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

@property (nonatomic, strong) NSArray *tiVoList;
@property (nonatomic, readonly) NSArray *tiVoShows;
@property (nonatomic, strong) NSMutableArray  *formatList;
@property (nonatomic, strong) NSMutableDictionary *lastLoadedTivoTimes;
@property (atomic, strong) NSMutableArray *downloadQueue;
@property (nonatomic, strong) NSMutableArray *subscribedShows;

@property (nonatomic, strong) NSString *downloadDirectory;
@property (nonatomic, weak, readonly) NSString *tmpFilesDirectory;
@property (nonatomic,readonly) NSString *defaultDownloadDirectory;
@property (nonatomic,readonly) NSURL *tivoTempDirectory;
@property (nonatomic,readonly) NSURL *tvdbTempDirectory;
@property (nonatomic,readonly) NSURL *detailsTempDirectory;
@property (readonly) NSArray *savedTiVos;
@property (readonly) NSArray *savedManualTiVos;
@property (readonly) NSArray *savedBonjourTiVos;
@property int volatile signalError;

//Other Properties
@property (nonatomic,readonly) NSMutableArray *tivoServices;
@property (nonatomic, strong) MTTVDB *tvdb;

@property (nonatomic, strong) MTFormat *selectedFormat;
@property (atomic) int numEncoders;
@property (nonatomic,readonly) int totalShows; // numCommercials, numCaptions;//Want to limit launches to two encoders.
@property (nonatomic, strong) NSNumber *processingPaused;
@property (nonatomic, readonly) BOOL anyShowsCompleted;
@property (nonatomic, strong) NSArray *currentMediaKeys;
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

-(MTDownload *) findInDownloadQueue: (MTTiVoShow *) show;
-(BOOL) anyShowsWaiting;
-(NSInteger)numberOfShowsToDownload;
-(long long)sizeOfShowsToDownload;
-(long long)biggestShowToDownload;
-(void) clearDownloadHistory;

//---------------Download Queue userDefaults writing/reading  ----------
-(void)saveState;
-(MTDownload *) findRealDownload: (MTDownload *) proxyDownload;
-(MTTiVoShow *) findRealShow:(MTTiVoShow *) showTarget;
-(void) replaceProxyInQueue: (MTTiVoShow *) newShow;
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
-(void)updateTiVoDefaults:(MTTiVo *)tiVo;
-(void) deleteTivoShows: (NSArray <MTTiVoShow *> *) shows;
-(void) stopRecordingShows: (NSArray <MTTiVoShow *> *) shows;

//----------------Channel Management Methods --------
-(void) updateChannel: (NSDictionary *) newChannel;
-(void) createChannel: (NSDictionary *) newChannel;
-(NSDictionary *)channelNamed:(NSString *) channel;
-(void) sortChannelsAndMakeUnique;
-(void) removeAllChannelsStartingWith: (NSString*) prefix;
-(NSCellStateValue) useTSForChannel:(NSString *) channelName;
-(void) setFailedPS:(BOOL) psFailed forChannelNamed: (NSString *) channelName;
-(NSCellStateValue) failedPSForChannel:(NSString *) channelName;
-(NSCellStateValue) commercialsForChannel:(NSString *) channelName;
-(BOOL) allShowsSelected;
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
