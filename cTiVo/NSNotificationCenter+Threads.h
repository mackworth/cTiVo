//
//  NSNotificationCenter+Threads.h
//  cTiVo
//
//  Created by Hugh Mackworth on 12/26/14.
//  Copyright (c) 2014 cTiVo. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NSNotificationCenter (Threads)

+(void)postNotificationOnMainThread:(NSNotification *)notification;
+(void)postNotificationOnMainThread:(NSNotification *)notification afterDelay:(NSTimeInterval) delay;

+(void)postNotificationNameOnMainThread:(NSString *)name object:(id)object;
+(void)postNotificationNameOnMainThread:(NSString *)name object:(id)object afterDelay:(NSTimeInterval)delay;

+(void)postNotificationNameOnMainThread:(NSString *)name object:(id)object userInfo:(NSDictionary *)userInfo;
+(void)postNotificationNameOnMainThread:(NSString *)name object:(id)object userInfo:(NSDictionary *)userInfo afterDelay:(NSTimeInterval)delay;

@end
