//
//  MTTivoRPC.h
//  TestTivo
//
//  Created by Hugh Mackworth on 11/27/16.
//  Copyright © 2016 Hugh Mackworth. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "MTRPCData.h"

@interface MTTivoRPC : NSObject

-(instancetype) initServer: (NSString *)serverAddress tsn: (NSString *) tsn onPort: (int32_t) port andMAK: (NSString *) mediaAccessKey forDelegate: (id <MTRPCDelegate>) delegate;
-(instancetype) initServer: (NSString *)serverAddress forUser:(NSString *) user withPassword: (NSString *) password;

-(void) launchServer;
-(void) stopServer;

-(BOOL) isActive;

-(MTRPCData *) rpcDataForID: (NSString *) idString;
-(void) emptyCaches;
-(void) reloadShowInfoForID: (NSString *) showID;

-(void) deleteShowsWithRecordIds: (NSArray <NSString *> *) recordingIds;
-(void) stopRecordingShowsWithRecordIds: (NSArray <NSString *> *) recordingIds;
-(void) undeleteShowsWithRecordIds: (NSArray <NSString *> *) recordingIds;

-(void) sendKeyEvent: (NSString *) keyEvent;
-(void) sendURL: (NSString *) URL;
-(void) retrieveClipData: (NSString *) contentId withCompletionHandler: (void (^)(NSArray *)) completionHandler; 
-(void) playOnTiVo: (NSString *) recordingId withCompletionHandler: (void (^)(BOOL)) completionHandler;

@property (nonatomic, weak) id <MTRPCDelegate> delegate;

@end

