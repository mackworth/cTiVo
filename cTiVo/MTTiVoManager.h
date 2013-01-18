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
#import "MTProgramTableView.h"
#import "MTTiVo.h"
#import "MTSubscription.h"
#import <SystemConfiguration/SystemConfiguration.h>
#import "MTFormat.h"


@interface MTTiVoManager : NSObject <NSNetServiceBrowserDelegate, NSNetServiceDelegate, NSURLConnectionDataDelegate, NSURLConnectionDelegate, NSTextFieldDelegate, NSAlertDelegate>  {
    
    NSNetService *tivoService ;
    NSNetServiceBrowser *tivoBrowser;
    NSMutableData *listingData;
//	NSMutableDictionary *tiVoShowsDictionary;
	NSMutableArray *updatingTiVoShows;
	
	NSURLConnection *programListURLConnection, *downloadURLConnection;
	NSTask *decryptingTask, *encodingTask;
    NSMutableDictionary *programDownloading, *programDecrypting, *programEncoding;
	NSFileHandle *downloadFile, *stdOutFileHandle;
	double dataDownloaded, referenceFileSize;
	NSNetService *tivoConnectingTo;
	NSOpenPanel *myOpenPanel;
    double percentComplete;
    MTDownloadTableCellView *downloadTableCell, *decryptTableCell, *encodeTableCell;
	NSArray *factoryFormatList;
    int numEncoders;//Want to limit launches to two encoders.

    BOOL volatile updatingVideoList;
	
	NSOperationQueue *queue;
    
}

//Shared Data

@property (nonatomic, retain) NSMutableArray *tiVoList, *tiVoShows, *downloadQueue, *formatList;
@property (nonatomic, retain) NSMutableArray *subscribedShows;
@property (nonatomic, retain) NSMutableArray *oldQueue; //queue from last run of program
@property (nonatomic, retain) NSString *downloadDirectory;
@property (readonly) NSString *defaultDownloadDirectory;

//Other Properties
@property (nonatomic,readonly) NSMutableArray *tivoServices;
@property (nonatomic) BOOL videoListNeedsFilling, addToItunes, simultaneousEncode;
@property (nonatomic, retain) MTFormat *selectedFormat;
@property int numEncoders;//Want to limit launches to two encoders.
@property (nonatomic, assign) NSWindow *mainWindow;


+ (MTTiVoManager *)sharedTiVoManager;

#define tiVoManager [MTTiVoManager sharedTiVoManager]

-(void) addProgramToDownloadQueue:(MTTiVoShow *)program;
-(void) addProgramsToDownloadQueue:(NSArray *)programs beforeShow:(MTTiVoShow *) nextShow;
-(void) downloadShowsWithCurrentOptions:(NSArray *) shows;
-(void) deleteProgramFromDownloadQueue:(MTTiVoShow *) program;

-(NSArray *)userFormats;
-(NSArray *)userFormatDictionaries;
-(NSArray *)hiddenBuiltinFormatNames;
-(MTFormat *) findFormat:(NSString *) formatName;
-(NSDictionary *)currentMediaKeys;
//-(void)manageDownloads;
-(void)addFormatsToList:(NSArray *)formats;

-(void)writeDownloadQueueToUserDefaults;
-(NSArray *)downloadQueueForTiVo:(MTTiVo *)tiVo;
- (void) noRecordingAlertDidEnd:(NSAlert *)alert returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo;

@end
