//
//  MTNetService.h
//  cTiVo
//
//  Created by Scott Buchanan on 1/24/13.
//  Copyright (c) 2013 Scott Buchanan. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface MTNetService : NSNetService

@property (nonatomic, retain) NSString *userName, *iPAddress;

@property (nonatomic) short userPort;

@end
