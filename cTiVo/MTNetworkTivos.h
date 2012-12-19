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


@interface MTNetworkTivos : NSObject <NSNetServiceBrowserDelegate, NSNetServiceDelegate, NSURLConnectionDataDelegate, NSURLConnectionDelegate, NSTextFieldDelegate, NSAlertDelegate>  {
    
    NSNetService *tivoService ;
    NSNetServiceBrowser *tivoBrowser;
    NSMutableData *listingData;
	
	NSURLConnection *programListURLConnection, *downloadURLConnection;
	NSTask *decryptingTask, *encodingTask;
    NSMutableDictionary *programDownloading, *programDecrypting, *programEncoding;
	NSFileHandle *downloadFile, *stdOutFileHandle;
	double dataDownloaded, referenceFileSize;
	NSNetService *tivoConnectingTo;
	NSOpenPanel *myOpenPanel;
    double percentComplete;
    MTDownloadListCellView *downloadTableCell, *decryptTableCell, *encodeTableCell;

}

//Shared Data

@property (nonatomic, readonly) NSMutableArray *tiVoList, *tiVoShows, *downloadQueue, *formatList;
@property (nonatomic, strong) NSString *downloadDirectory, *programLoadingString;

//Other Properties
@property (nonatomic,readonly) NSMutableArray *tivoServices;
@property (nonatomic) BOOL videoListNeedsFilling;
@property (nonatomic, strong) NSDictionary *selectedFormat;
@property (nonatomic, strong) NSNetService *selectedTiVo;
@property (unsafe_unretained, nonatomic, readonly) NSMutableArray *tiVoNames;



-(void)fetchVideoListFromHost;
-(void)addProgramToDownloadQueue:(MTTiVoShow *)program;


@end
