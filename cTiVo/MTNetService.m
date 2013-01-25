//
//  MTNetService.m
//  cTiVo
//
//  Created by Scott Buchanan on 1/24/13.
//  Copyright (c) 2013 Scott Buchanan. All rights reserved.
//

#import "MTNetService.h"
#include <arpa/inet.h>

@implementation MTNetService

-(id)init{
    self = [super init];
    if (self) {
        self.userPort = 0;
        self.userName = nil;
        self.iPAddress = nil;
    }
    return self;
}

-(NSInteger)port
{
    NSInteger p = super.port;
    if (_userPort) {
        p = _userPort;
    }
    return p;
}

-(NSString *)hostName
{
    NSString *returnString = super.hostName;
    if (self.iPAddress) {
        returnString = self.iPAddress;
    }
    return returnString;
}

-(NSString *)name
{
    NSString *returnString = super.name;
    if (self.userName) {
        returnString = self.userName;
    }
    return returnString;
}

-(NSArray *)addresses
{
    NSArray *returnArray = [super addresses];
    if (_iPAddress) {
        struct sockaddr_in socketAddress;
        socketAddress.sin_family = AF_INET;
        socketAddress.sin_port = htons(_userPort);
        socketAddress.sin_addr.s_addr = inet_addr([_iPAddress cStringUsingEncoding:NSASCIIStringEncoding]);
        returnArray = [NSArray arrayWithObject:[NSData dataWithBytes:&socketAddress length:sizeof(struct sockaddr_in)]];
    }
    return returnArray;
}


@end
