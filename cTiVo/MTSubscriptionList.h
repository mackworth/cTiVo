//
//  MTSubscriptionList.h
//  cTiVo
//
//  Created by Hugh Mackworth on 12/9/14.
//  Copyright (c) 2014 cTiVo. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "MTSubscription.h"

@interface NSMutableArray (SubscriptionList)

-(void) checkSubscription: (NSNotification *) notification;  //Notification.object should be show to check
-(void) checkSubscriptionsNew:(NSArray *) newSubs;

-(NSArray *) addSubscriptionsShows:(NSArray *) shows; //returns new subs
-(NSArray *) addSubscriptionsDL: (NSArray *) downloads;
-(NSArray *) addSubscriptionsFormattedStrings: (NSArray *) strings;
-(NSArray *) addSubscriptionsPatterns: (NSArray *) patterns;

-(void) deleteSubscriptions:(NSArray *) subscriptions;
-(void) clearHistory:(NSArray *) subscriptions;

-(void) saveSubscriptions;
-(void) loadSubscriptions;

@end
