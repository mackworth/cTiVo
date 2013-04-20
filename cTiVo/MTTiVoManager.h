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
@property (atomic, strong) NSMutableArray *downloadQueue;
@property (nonatomic, strong) NSMutableArray *subscribedShows;

@property (nonatomic, strong) NSString *downloadDirectory;
@property (weak, readonly) NSString *defaultDownloadDirectory;

@property int volatile signalError;

//Other Properties
@property (nonatomic,readonly) NSMutableArray *tivoServices;
@property (nonatomic, strong) MTFormat *selectedFormat;
@property (nonatomic) int numEncoders, totalShows, numCommercials, numCaptions;//Want to limit launches to two encoders.
@property (nonatomic, strong) NSWindow *mainWindow;
@property (nonatomic, strong) NSNumber *processingPaused, *quitWhenCurrentDownloadsComplete;
@property (nonatomic, strong) NSDictionary *showsOnDisk;


+ (MTTiVoManager *)sharedTiVoManager;

#define tiVoManager [MTTiVoManager sharedTiVoManager]

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

-(MTDownload *) findRealDownload: (MTDownload *) proxyDownload;
-(MTTiVoShow *) findRealShow:(MTTiVoShow *) showTarget;
-(void) replaceProxyInQueue: (MTTiVoShow *) newShow;
-(void) checkDownloadQueueForDeletedEntries: (MTTiVo *) tiVo;

-(NSArray *)userFormats;
-(NSArray *)userFormatDictionaries;
-(NSArray *)hiddenBuiltinFormatNames;
-(MTFormat *) findFormat:(NSString *) formatName;
-(NSDictionary *)currentMediaKeys;
//-(void)manageDownloads;
-(void)addFormatsToList:(NSArray *)formats;

-(void)writeDownloadQueueToUserDefaults;
-(NSArray *)downloadQueueForTiVo:(MTTiVo *)tiVo;

-(BOOL)foundTiVoNamed:(NSString *)tiVoName;
-(NSInteger)numberOfShowsToDownload;
-(void)loadManualTiVos;
- (void)notifyWithTitle:(NSString *) title subTitle: (NSString*) subTitle forNotification: (NSString *) notification;
-(void)refreshAllTiVos;
-(BOOL)anyTivoActive;

//-(BOOL)playVideoForDownloads:(NSArray *) downloads;
//-(BOOL)revealInFinderForDownloads:(NSArray *) downloads;
-(void)pauseQueue:(NSNumber *)askUser;
-(void)unPauseQueue;
-(void)determineCurrentProcessingState;
-(void)updateShowOnDisk:(NSString *)key withPath:(NSString *)path;

@end
