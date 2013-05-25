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
@class MTDownload;

@interface MTSubscription : NSObject {
    
}


@property (nonatomic, strong) NSString * displayTitle;
@property (nonatomic, strong) NSRegularExpression *subscriptionRegex;
@property (nonatomic, strong) NSDate *createdTime;
@property (readonly) NSDate *displayDate;
@property (nonatomic, strong) NSString *preferredTiVo;
@property (nonatomic, strong) NSNumber *HDOnly;
@property (nonatomic, strong) NSNumber *SDOnly;
@property (nonatomic, strong) NSMutableArray *prevRecorded;
//Dictionary with keys; showTitle, episodeID, startTime, TivoName

@property (nonatomic, strong) NSNumber *addToiTunes;
@property (nonatomic, strong) NSNumber *skipCommercials, *includeSuggestions, *markCommercials;
@property (nonatomic, strong) MTFormat *encodeFormat;
@property (nonatomic, strong) NSNumber *genTextMetaData,
									   *genXMLMetaData,
									   *includeAPMMetaData,
									   *exportSubtitles;

@property (readonly) BOOL canSimulEncode;
@property (readonly) BOOL shouldSimulEncode;
@property (readonly) BOOL canAddToiTunes;
@property (readonly) BOOL shouldAddToiTunes;
@property (readonly) BOOL canSkipCommercials;
@property (readonly) BOOL canMarkCommercials;
@property (readonly) BOOL shouldSkipCommercials;

-(BOOL) isSubscribed:(MTTiVoShow *) tivoShow;
-(MTDownload *) downloadForShow: (MTTiVoShow *) thisShow;

@end

@interface NSMutableArray (MTSubscriptionList)

-(void) checkSubscription: (NSNotification *) notification;
-(NSArray *) addSubscriptions:(NSArray *) shows; //returns new subs
-(NSArray *) addSubscriptionsDL: (NSArray *) downloads;
-(MTSubscription *) addSubscriptionsString: (NSString *) pattern;
-(void) deleteSubscriptions:(NSArray *) subscriptions;

-(void) saveSubscriptions;
-(void) loadSubscriptions;

@end
