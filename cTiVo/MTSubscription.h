//
//  MTSubscription.h
//  cTiVo
//
//  Created by Hugh Mackworth on 1/4/13.
//  Copyright (c) 2013 Scott Buchanan. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "MTTiVoShow.h"
#import "MTFormat.h"

@interface MTSubscription : NSObject {
    
}


@property (nonatomic, retain) NSString *seriesTitle;
@property (nonatomic, retain) NSDate *lastRecordedTime;

@property (nonatomic, retain) NSNumber *addToiTunes;
@property (nonatomic, retain) NSNumber *simultaneousEncode, *skipCommercials;
@property (nonatomic, retain) MTFormat *encodeFormat;

@property (readonly) BOOL canSimulEncode;
@property (readonly) BOOL shouldSimulEncode;
@property (readonly) BOOL canAddToiTunes;
@property (readonly) BOOL shouldAddToiTunes;
@property (readonly) BOOL canSkipCommercials;
@property (readonly) BOOL shouldSkipCommercials;

@end

@interface NSMutableArray (MTSubscriptionList)

-(void) checkSubscriptionsAll;
-(NSArray *) addSubscriptions:(NSArray *) shows; //returns new subs
-(void) deleteSubscriptions:(NSArray *) subscriptions;
-(void) updateSubscriptionWithDate: (NSNotification *) notification;
-(BOOL) isSubscribed:(MTTiVoShow *) tivoShow;
-(void) saveSubscriptions;
-(void) loadSubscriptions;

@end
