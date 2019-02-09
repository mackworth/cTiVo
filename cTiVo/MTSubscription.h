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

@interface MTSubscription : NSObject < NSPasteboardWriting, NSPasteboardReading> {
    
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

@property (nonatomic, strong) NSString *stationCallSign;
@property (nonatomic, strong) NSNumber *addToiTunes;
@property (nonatomic, strong) NSNumber *skipCommercials, *includeSuggestions, *markCommercials, *useSkipMode, *deleteAfterDownload;
@property (nonatomic, strong) MTFormat *encodeFormat;
@property (nonatomic, strong) NSNumber *genTextMetaData,
									   *exportSubtitles;

@property (readonly) BOOL canAddToiTunes;
@property (readonly) BOOL shouldAddToiTunes;
@property (readonly) BOOL canSkipCommercials;
@property (readonly) BOOL canMarkCommercials;
@property (readonly) BOOL shouldSkipCommercials;

+(MTSubscription *) subscriptionFromString:(NSString *) str;
+(MTSubscription *) subscriptionFromDictionary: (NSDictionary *) sub;
+(MTSubscription *) subscriptionFromShow: (MTTiVoShow *) tivoShow;


-(BOOL) isSubscribed:(MTTiVoShow *) tivoShow ignoreDate:(BOOL) ignoreDate;
-(MTDownload *) downloadForSubscribedShow: (MTTiVoShow *) thisShow;

@end

