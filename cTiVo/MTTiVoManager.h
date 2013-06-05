//
//  MTNetworkTivos.h
//  myTivo
//
//  Created by Scott Buchanan on 12/6/12.
//  Copyright (c) 2012 Scott Buchanan. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "NSString+HTML.h"
#import "MTDownloadTableCellView.h"
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
@property (nonatomic, strong) NSMutableArray *tiVoShows, *formatList;
@property (nonatomic, strong) NSMutableDictionary *lastLoadedTivoTimes;
@property (atomic, strong) NSMutableArray *downloadQueue;
@property (nonatomic, strong) NSMutableArray *subscribedShows;
@property (nonatomic, strong) NSMutableDictionary *tvdbSeriesIdMapping;
@property (nonatomic, strong) NSMutableDictionary *tvdbCache;

@property (nonatomic, strong) NSString *downloadDirectory;
@property (nonatomic, weak, readonly) NSString *tmpFilesDirectory;
@property (weak, readonly) NSString *defaultDownloadDirectory;

@property int volatile signalError;

//Other Properties
@property (nonatomic,readonly) NSMutableArray *tivoServices;
@property (nonatomic, strong) MTFormat *selectedFormat;
@property (nonatomic) int numEncoders, totalShows; // numCommercials, numCaptions;//Want to limit launches to two encoders.
@property (nonatomic, strong) NSWindow *mainWindow;
@property (nonatomic, strong) NSNumber *processingPaused, *quitWhenCurrentDownloadsComplete;
@property (nonatomic, strong) NSDictionary *showsOnDisk;
@property (nonatomic, readonly) BOOL anyShowsCompleted;


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
-(NSDictionary *)currentMediaKeys;
-(BOOL)foundTiVoNamed:(NSString *)tiVoName;
-(void)loadManualTiVos;
-(void)refreshAllTiVos;
-(void)resetAllDetails;

-(BOOL)anyTivoActive;


//---------------Other methods ----------
- (void)notifyWithTitle:(NSString *) title subTitle: (NSString*) subTitle forNotification: (NSString *) notification;   //Growl notification
-(void)updateShowOnDisk:(NSString *)key withPath:(NSString *)path;

@end
