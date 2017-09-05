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

-(instancetype) initServer: (NSString *)serverAddress onPort: (int32_t) port andMAK: (NSString *) mediaAccessKey;
-(instancetype) initServer: (NSString *)serverAddress forUser:(NSString *) user withPassword: (NSString *) password;

-(BOOL) isActive;

-(MTRPCData *) rpcDataForID: (NSString *) idString;
-(void) emptyCaches;
-(void) reloadShowInfoForID: (NSString *) showID;

@property (nonatomic, weak) id <MTRPCDelegate> delegate;

@end

