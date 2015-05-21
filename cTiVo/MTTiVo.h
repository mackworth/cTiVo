//
//  MTTiVo.h
//  cTiVo
//
//  Created by Scott Buchanan on 1/5/13.
//  Copyright (c) 2013 Scott Buchanan. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <SystemConfiguration/SystemConfiguration.h>
#import "MTNetService.h"

@protocol MTTableViewProtocol

@optional
-(NSArray *)sortedShows;

@end


@class MTTiVoManager, MTTiVoShow;

@interface MTTiVo : NSObject <NSXMLParserDelegate> {
	BOOL volatile isConnecting, managingDownloads, firstUpdate, canPing;
	NSURLConnection *showURLConnection;
	NSMutableData *urlData;
	NSMutableArray *newShows;
    SCNetworkReachabilityContext reachabilityContext;
    int totalItemsOnTivo;
    int lastChangeDate;
    int itemStart;
    int itemCount;
    int authenticationTries;
    BOOL parsingShow, gettingContent, gettingDetails, gettingIcon;
    NSMutableString *element;
    MTTiVoShow *currentShow;
    NSDictionary *elementToPropertyMap;
	NSMutableDictionary *previousShowList;
    
}

@property (nonatomic, strong) MTNetService *tiVo;
@property (strong) NSArray *shows;
@property (nonatomic, strong) NSDate *networkAvailability;
@property (nonatomic, strong) NSString *mediaKey;
@property (nonatomic, strong) NSOperationQueue *opsQueue;
@property (nonatomic, strong) MTTiVoManager *tiVoManager;
@property (nonatomic, strong) NSURLConnection *showURLConnection;
@property BOOL mediaKeyIsGood,storeMediaKeyInKeychain;
@property BOOL isReachable, isResponding, manualTiVo, enabled;
@property (nonatomic, strong) NSDate *lastDownloadEnded;
@property (nonatomic, strong) 	NSDate *currentNPLStarted;
@property int manualTiVoID;

+(MTTiVo *)tiVoWithTiVo:(id)tiVo withOperationQueue:(NSOperationQueue *)queue;
+(MTTiVo *)tiVoWithTiVo:(id)tiVo withOperationQueue:(NSOperationQueue *)queue manual:(BOOL) isManual withID:(int)manualTiVoID;
+(MTTiVo *)manualTiVoWithDescription:(NSDictionary *)description withOperationQueue:(NSOperationQueue *)queue;

-(id) initWithTivo:(id)tiVo withOperationQueue:(NSOperationQueue *)queue manual:(BOOL) isManual withID:(int)manualTiVoID;
-(void)scheduleNextUpdateAfterDelay:(NSInteger) delay;
-(void)updateShows:(id)sender;
-(void)manageDownloads:(id)info;
//-(void) reportNetworkFailure;
-(NSInteger)isProcessing;
-(void)rescheduleAllShows;
-(void)setupNotifications;

-(void) saveLastLoadTime:(NSDate *) newDate;
-(void)resetAllDetails;
-(void)getMediaKey;
-(NSDictionary *)defaultsDictionary;

@end
