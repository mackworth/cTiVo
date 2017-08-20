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
#import "MTRPCData.h"

@protocol MTTableViewProtocol

@optional
-(NSArray *)sortedShows;

@end


@class MTTiVoManager, MTTiVoShow;

@interface MTTiVo : NSObject <NSXMLParserDelegate>

@property (nonatomic, strong) NSDate *lastDownloadEnded;
@property (strong) NSArray *shows;
@property (nonatomic, strong) MTNetService *tiVo;
@property BOOL  manualTiVo, enabled;
@property BOOL mediaKeyIsGood,storeMediaKeyInKeychain;
@property BOOL isReachable;
@property (nonatomic, strong) NSString *mediaKey;
@property int manualTiVoID;
@property (nonatomic) BOOL supportsTransportStream;

+(MTTiVo *)tiVoWithTiVo:(MTNetService *)tiVo withOperationQueue:(NSOperationQueue *)queue;
+(MTTiVo *)tiVoWithTiVo:(MTNetService *)tiVo withOperationQueue:(NSOperationQueue *)queue manual:(BOOL) isManual withID:(int)manualTiVoID;
+(MTTiVo *)manualTiVoWithDescription:(NSDictionary *)description withOperationQueue:(NSOperationQueue *)queue;

-(id) initWithTivo:(id)tiVo withOperationQueue:(NSOperationQueue *)queue manual:(BOOL) isManual withID:(int)manualTiVoID;
-(void)scheduleNextUpdateAfterDelay:(NSInteger) delay;
-(void)updateShows:(id)sender;
-(void)manageDownloads:(id)info;
//-(void) reportNetworkFailure;
-(NSInteger)isProcessing;
-(void)rescheduleAllShows;
-(void)setupNotifications;
-(void)notifyUserWithTitle:(NSString *) title subTitle: (NSString*) subTitle; // notification of Tivo problem

-(void) saveLastLoadTime:(NSDate *) newDate;
-(void)resetAllDetails;
-(void)getMediaKey;
-(NSDictionary *)defaultsDictionary;
-(MTRPCData *) rpcDataForID: (NSString *) idString;

@end
