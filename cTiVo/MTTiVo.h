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

@class MTTiVoManager, MTTiVoShow;

@interface MTTiVo : NSObject <NSXMLParserDelegate> {
	BOOL volatile isConnecting, managingDownloads, firstUpdate, canPing;
	NSURLConnection *showURLConnection;
	NSMutableData *urlData;
    SCNetworkReachabilityContext reachabilityContext;
    int totalItemsOnTivo;
    int lastChangeDate;
    int itemStart;
    int itemCount;
    BOOL parsingShow, gettingContent, gettingDetails;
    NSMutableString *element;
    MTTiVoShow *currentShow;
    NSDictionary *elementToPropertyMap;
	NSMutableDictionary *previousShowList;
    
}

@property (nonatomic, retain) MTNetService *tiVo;
@property (nonatomic, retain) NSMutableArray *shows;
@property (nonatomic, retain) NSDate *networkAvailability;
@property (nonatomic, retain) NSString *mediaKey;
@property (nonatomic, assign) NSOperationQueue *queue;
@property (nonatomic, retain) MTTiVoManager *tiVoManager;
@property BOOL mediaKeyIsGood;
@property BOOL isReachable, isResponding, manualTiVo, enabled;

+(MTTiVo *)tiVoWithTiVo:(id)tiVo withOperationQueue:(NSOperationQueue *)queue;

-(id) initWithTivo:(id)tiVo withOperationQueue:(NSOperationQueue *)queue;
-(void)updateShows:(id)sender;
-(void)manageDownloads:(id)info;
//-(void) reportNetworkFailure;
-(NSInteger)numberOfShowsInProcess;
-(void)rescheduleAllShows;

@end
