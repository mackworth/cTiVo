//
//  MTNetService.h
//  cTiVo
//
//  Created by Scott Buchanan on 1/24/13.
//  Copyright (c) 2013 Scott Buchanan. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface MTNetService : NSNetService

-(MTNetService *) initWithName:(NSString *)name;

@property (nonatomic, strong) NSString *userName, *iPAddress;

@property (nonatomic) short userPort, userPortSSL, userPortRPC;

@end
