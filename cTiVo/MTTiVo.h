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

@class MTTiVoManager, MTTiVoShow;

@interface MTTiVo : NSObject <NSXMLParserDelegate, MTRPCDelegate>

@property (nonatomic, strong) NSDate *lastDownloadEnded;
@property (strong) NSArray < MTTiVoShow *> *shows;
@property (nonatomic, strong) MTNetService *tiVo;
@property (nonatomic, strong) NSString * tiVoSerialNumber;
@property (readonly)  BOOL  manualTiVo;
@property (atomic, assign) BOOL enabled;
@property (nonatomic, assign)BOOL storeMediaKeyInKeychain;
@property (atomic, assign) BOOL isReachable;
@property (nonatomic, strong) NSString *mediaKey;
@property int manualTiVoID;
@property (nonatomic, readonly) BOOL supportsTransportStream, supportsRPC;

+(MTTiVo *)tiVoWithTiVo:(MTNetService *)tiVo
     withOperationQueue:(NSOperationQueue *)queue
       withSerialNumber:(NSString *) TSN;
+(MTTiVo *)manualTiVoWithDescription:(NSDictionary *)description
                  withOperationQueue:(NSOperationQueue *)queue;

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

-(NSDictionary *)descriptionDictionary;
-(void) updateWithDescription:(NSDictionary *) newTiVo;

-(MTRPCData *) rpcDataForID: (NSString *) idString;
-(void) reloadShowInfoForID: (NSString *) showID;
-(MTRPCData *)registerRPCforShow: (MTTiVoShow *) show;
-(BOOL) rpcActive;
-(void) deleteTiVoShows: (NSArray <MTTiVoShow *> *) shows;
-(void) stopRecordingTiVoShows: (NSArray <MTTiVoShow *> *) shows;

@end
