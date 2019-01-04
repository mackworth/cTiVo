//
//  NSNotificationCenter+Threads.m
//  cTiVo
//
//  Created by Hugh Mackworth on 12/26/14.
//  Copyright (c) 2014 cTiVo. All rights reserved.
//

#import "NSNotificationCenter+Threads.h"

@implementation NSNotificationCenter (Threads)

+(void)postNotificationOnMainThread:(NSNotification *)notification {
    [self postNotificationOnMainThread:notification afterDelay:0.0];
}

+(void)postNotificationOnMainThread:(NSNotification *)notification afterDelay:(NSTimeInterval) delay {
    if (delay == 0.0) {
        if ([NSThread isMainThread]) {
            [[NSNotificationCenter defaultCenter] postNotification:notification];
        } else {
            [[NSNotificationCenter defaultCenter] performSelectorOnMainThread:@selector(postNotification:) withObject:notification waitUntilDone:NO];
        }
    } else {
        if ([NSThread isMainThread]) {
            [[NSNotificationCenter defaultCenter] performSelector:@selector(postNotification:) withObject:notification afterDelay:delay];
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{
                [[NSNotificationCenter defaultCenter] performSelector:@selector(postNotification:) withObject:notification afterDelay:delay];
            });
        }
    }
}

+(void)postNotificationNameOnMainThread:(NSString *)name object:(id)object {
    [self postNotificationNameOnMainThread:name object:object userInfo:nil afterDelay:0.0];
}

+(void)postNotificationNameOnMainThread:(NSString *)name object:(id)object afterDelay:(NSTimeInterval)delay {
    [self postNotificationNameOnMainThread:name object:object userInfo:nil afterDelay:delay];
}

+(void)postNotificationNameOnMainThread:(NSString *)name object:(id)object userInfo:(NSDictionary *)userInfo
{
    [self postNotificationNameOnMainThread:name object:object userInfo:userInfo afterDelay:0.0];
 }

+(void)postNotificationNameOnMainThread:(NSString *)name object:(id)object userInfo:(NSDictionary *)userInfo afterDelay:(NSTimeInterval)delay {

    NSNotification * notification = [NSNotification notificationWithName:name object:object userInfo:userInfo];
    [self postNotificationOnMainThread:notification afterDelay: delay];
}



@end
