//
//  MTNetworkTivos.h
//  myTivo
//
//  Created by Scott Buchanan on 12/6/12.
//  Copyright (c) 2012 Scott Buchanan. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "NSString+HTML.h"


@interface MTNetworkTivos : NSObject <NSNetServiceBrowserDelegate, NSNetServiceDelegate, NSURLConnectionDataDelegate, NSURLConnectionDelegate, NSTextFieldDelegate, NSAlertDelegate>  {
    
    NSNetService *tivoService ;
    NSNetServiceBrowser *tivoBrowser;
    NSMutableData *listingData;
	IBOutlet NSProgressIndicator *downloadingProgress, *decryptingProgress, *encodingProgress;
	IBOutlet NSPopUpButton *tivoList, *formatList;
	IBOutlet NSTextField *downloadingLabel, *decryptingLabel, *encodingLabel, *mediaKeyLabel, *loadingProgramListLabel, *downloadDirectory;
	IBOutlet NSProgressIndicator *loadingProgramListIndicator;
	IBOutlet NSTableView *programListTable, *downloadQueueTable;
	IBOutlet NSButton *cancelDownloadingButton, *cancelDecryptingButton, *cancelEncodingButton;
	NSURLConnection *programListURLConnection, *downloadURLConnection;
	NSTask *decryptingTask, *encodingTask;
	NSArray *encodingFormats;
	NSMutableDictionary *mediaKeys;
	NSDictionary *programDownloading, *programDecrypting, *programEncoding;
	NSFileHandle *downloadFile, *stdOutFileHandle;
	double dataDownloaded, referenceFileSize;
	NSNetService *tivoConnectingTo;
	NSOpenPanel *myOpenPanel;
    double percentComplete;
}

@property (nonatomic, readonly) NSMutableArray *tivoNames, *recordings, *downloadQueue, *decryptQueue, *encodeQueue;
@property (nonatomic,readonly) NSMutableArray *tivoServices;
@property (nonatomic) BOOL videoListNeedsFilling;

-(void)fetchVideoListFromHost;

@end
