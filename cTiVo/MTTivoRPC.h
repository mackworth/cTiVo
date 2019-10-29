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
-(void) purgeShows: (NSArray <NSString *> *) showIDs;
-(void) whatsOnSearchWithCompletion: (void (^)(MTWhatsOnType whatsOn, NSString * recordingID, NSString * channelNumber)) completionHandler;
-(void) getShowInfoForShows: (NSArray <NSString *> *) showIDs;
	//if needed, get showInfo for showIds; notification done to delegate ( RPCId is set for those shoes)
	//not notified if rpdData (including clipmetadata already set
-(void) channelListWithCompletion: (void (^)(NSDictionary <NSString *, NSString *> *)) completionHandler;
-(void) tiVoInfoWithCompletion: (void (^)(NSString *)) completionHandler;

-(void) deleteShowsWithRecordIds: (NSArray <NSString *> *) recordingIds;
-(void) stopRecordingShowsWithRecordIds: (NSArray <NSString *> *) recordingIds;
-(void) undeleteShowsWithRecordIds: (NSArray <NSString *> *) recordingIds;

-(void) sendKeyEvent: (NSString *) keyEvent withCompletion: (void (^) (void)) completionHandler;
-(void) sendURL: (NSString *) URL;
-(void) playOnTiVo: (NSString *) recordingId withCompletionHandler: (void (^)(BOOL success)) completionHandler;
-(void) rebootTiVo;

-(void) findSkipModeEDLForShow:(MTRPCData *) rpcData;
-(NSArray <MTRPCData *> *) showsWaitingForSkipMode;

@property (nonatomic, weak) id <MTRPCDelegate> delegate;

@end

