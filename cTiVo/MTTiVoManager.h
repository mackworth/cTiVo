//
//  MTNetworkTivos.h
//  myTivo
//
//  Created by Scott Buchanan on 12/6/12.
//  Copyright (c) 2012 Scott Buchanan. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "NSString+HTML.h"
#import "MTDownloadListCellView.h"
#import "MTTiVoShow.h"
#import "MTProgramList.h"
#import "MTTiVo.h"
#import "MTSubscription.h"


@interface MTTiVoManager : NSObject <NSNetServiceBrowserDelegate, NSNetServiceDelegate, NSURLConnectionDataDelegate, NSURLConnectionDelegate, NSTextFieldDelegate>  {
    
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
    MTDownloadListCellView *downloadTableCell, *decryptTableCell, *encodeTableCell;
	int numEncoders;//Want to limit launches to two encoders.
    
    BOOL volatile updatingVideoList;
	
	NSOperationQueue *queue;
	
	NSArray *hostAddresses;

}

//Shared Data

@property (nonatomic, readonly) NSMutableArray *tiVoList, *tiVoShows, *downloadQueue, *formatList;
@property (nonatomic, readonly) NSMutableArray *subscribedShows;
@property (nonatomic, retain) NSString *downloadDirectory, *programLoadingString;

//Other Properties
@property (nonatomic,readonly) NSMutableArray *tivoServices;
@property (nonatomic) BOOL videoListNeedsFilling, addToItunes, simultaneousEncode;
@property (nonatomic, retain) NSDictionary *selectedFormat;
//@property (nonatomic, retain) NSNetService *selectedTiVo;
@property (nonatomic, readonly) NSMutableArray *tiVoNames;
@property (nonatomic,assign) MTProgramList *tiVoShowTableView;

+ (MTTiVoManager *)sharedTiVoManager;

#define tiVoManager [MTTiVoManager sharedTiVoManager]

-(void)addProgramToDownloadQueue:(MTTiVoShow *)program;
-(void) downloadthisShowWithCurrentOptions:(MTTiVoShow*) thisShow;  
-(void) deleteProgramFromDownloadQueue:(MTTiVoShow *) program;

-(BOOL) canAddToiTunes:(NSDictionary *) format;
-(BOOL) canSimulEncode:(NSDictionary *) format;
-(NSDictionary *) findFormat:(NSString *) formatName;
-(NSDictionary *)currentMediaKeys;

@end
