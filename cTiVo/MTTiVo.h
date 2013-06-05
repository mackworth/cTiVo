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
    BOOL parsingShow, gettingContent, gettingDetails, gettingIcon;
    NSMutableString *element;
    MTTiVoShow *currentShow;
    NSDictionary *elementToPropertyMap;
	NSMutableDictionary *previousShowList;
    
}

@property (nonatomic, strong) MTNetService *tiVo;
@property (nonatomic, strong) NSMutableArray *shows;
@property (nonatomic, strong) NSDate *networkAvailability;
@property (nonatomic, strong) NSString *mediaKey;
@property (nonatomic, weak) NSOperationQueue *queue;
@property (nonatomic, strong) MTTiVoManager *tiVoManager;
@property (nonatomic, strong) NSURLConnection *showURLConnection;
@property BOOL mediaKeyIsGood;
@property BOOL isReachable, isResponding, manualTiVo, enabled;
@property (nonatomic, strong) NSDate *lastDownloadEnded;
@property (nonatomic, strong) 	NSDate *currentNPLStarted;

+(MTTiVo *)tiVoWithTiVo:(id)tiVo withOperationQueue:(NSOperationQueue *)queue;

-(id) initWithTivo:(id)tiVo withOperationQueue:(NSOperationQueue *)queue;
-(void)updateShows:(id)sender;
-(void)manageDownloads:(id)info;
//-(void) reportNetworkFailure;
-(NSInteger)isProcessing;
-(void)rescheduleAllShows;
-(void)setupNotifications;

-(void) saveLastLoadTime:(NSDate *) newDate;
-(void)resetAllDetails;


@end
