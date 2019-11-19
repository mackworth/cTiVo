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

-(MTNetService *) initWithName:(NSString *)name {
    self = [[MTNetService alloc] initWithDomain: @"" type: @"_http._tcp" name: name];
    if (self) {
        self.userPort = 80;
        self.userPortSSL = 443;
        self.userPortRPC = 1413;
        self.userName = name;
        self.iPAddress = nil;
    }
	return self;
}

-(NSInteger)port{
    return _userPort ?: super.port;
}

-(NSString *)hostName {
    return self.iPAddress ?: super.hostName;
}

-(NSString *)name {
    return self.userName ?: super.name;
}

-(NSArray *)addresses {
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

-(NSString*) description {
	return [NSString stringWithFormat:@"%@, host:%@:%ld/%d/%d",self.name,self.hostName,self.port, self.userPortSSL , self.userPortRPC];
}

@end
