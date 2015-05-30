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
#import "MTProgramTableView.h"
#import "MTTiVo.h"
#import "MTSubscription.h"
#import <SystemConfiguration/SystemConfiguration.h>
#import "MTFormat.h"


@interface MTTiVoManager : NSObject <NSNetServiceBrowserDelegate, NSNetServiceDelegate, NSURLConnectionDataDelegate, NSURLConnectionDelegate, NSTextFieldDelegate, NSAlertDelegate>  {
}

//Shared Data

@property (nonatomic, strong) NSArray *tiVoList;
@property (nonatomic, readonly) NSArray *tiVoShows;
@property (nonatomic, strong) NSMutableArray  *formatList;
@property (nonatomic, strong) NSMutableDictionary *lastLoadedTivoTimes;
@property (atomic, strong) NSMutableArray *downloadQueue;
@property (nonatomic, strong) NSMutableArray *subscribedShows;
@property (atomic, strong) NSMutableDictionary *tvdbSeriesIdMapping;
@property (atomic, strong) NSMutableDictionary *tvdbCache;
@property (atomic, strong) NSMutableDictionary * theTVDBStatistics;

@property (nonatomic, strong) NSString *downloadDirectory;
@property (nonatomic, weak, readonly) NSString *tmpFilesDirectory;
@property (weak, readonly) NSString *defaultDownloadDirectory;
@property (weak, readonly) NSArray *savedTiVos;
@property (weak, readonly) NSArray *savedManualTiVos;
@property (weak, readonly) NSArray *savedBonjourTiVos;

@property int volatile signalError;

//Other Properties
@property (nonatomic,readonly) NSMutableArray *tivoServices;
@property (nonatomic, strong) NSOperationQueue * tvdbQueue;
@property (nonatomic, strong) MTFormat *selectedFormat;
@property (nonatomic) int numEncoders;
@property (nonatomic,readonly) int totalShows; // numCommercials, numCaptions;//Want to limit launches to two encoders.
@property (nonatomic, strong) NSNumber *processingPaused, *quitWhenCurrentDownloadsComplete;
@property (nonatomic, strong) NSDictionary *showsOnDisk;
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
-(void) clearDownloadHistory;

//---------------Download Queue userDefaults writing/reading  ----------
-(void)writeDownloadQueueToUserDefaults;
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
-(NSArray *)hiddenBuiltinFormatNames;
-(MTFormat *) findFormat:(NSString *) formatName;
-(void)addFormatsToList:(NSArray *)formats;
-(void)addEncFormatToList: (NSString *) filename ;

//---------------TiVo Management methods ----------
-(BOOL)foundTiVoNamed:(NSString *)tiVoName;
-(void)loadManualTiVos;
-(void)searchForBonjourTiVos;
-(void)refreshAllTiVos;
-(void)resetAllDetails;
-(NSArray *)allTiVos;
-(BOOL)anyTivoActive;
-(int) nextManualTiVoID;
-(void)updateTiVoDefaults:(MTTiVo *)tiVo;


//---------------Other methods ----------
- (void)notifyWithTitle:(NSString *) title subTitle: (NSString*) subTitle isSticky: (BOOL) sticky forNotification: (NSString *) notification; //Gowl notification with Sticky
- (void)notifyWithTitle:(NSString *) title subTitle: (NSString*) subTitle forNotification: (NSString *) notification;   //Growl notification
-(void)updateShowOnDisk:(NSString *)key withPath:(NSString *)path;
-(NSString *)getAMediaKey;


@end

@interface NSObject (maskMediaKeys)
//strip out all mediakeys in debug log
-(NSString *) maskMediaKeys;

@end
