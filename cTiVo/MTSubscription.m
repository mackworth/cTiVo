//
//  MTSubscription.m
//  cTiVo
//
//  Created by Hugh Mackworth on 1/4/13.
//  Copyright (c) 2013 Scott Buchanan. All rights reserved.
//

#import "MTSubscription.h"
#import "MTTiVoManager.h"

@implementation MTSubscription
@synthesize     seriesTitle= _seriesTitle,
                lastRecordedTime = _lastRecordedTime,
                addToiTunes = _addToiTunes,
//                simultaneousEncode = _simultaneousEncode,
                encodeFormat = _encodeFormat;
__DDLOGHERE__

-(id) init {
	if ((self = [super init])) {
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(formatMayHaveChanged) name:kMTNotificationFormatListUpdated object:nil];
	}
	return self;
}

-(BOOL) canSimulEncode {
    return self.encodeFormat.canSimulEncode;
}

-(BOOL) canSkipCommercials {
    return self.encodeFormat.comSkip.boolValue;
}

-(BOOL) canMarkCommercials {
	NSArray * allowedExtensions = @[@".mp4", @".m4v"];
	NSString * extension = [self.encodeFormat.filenameExtension lowercaseString];
	return [allowedExtensions containsObject: extension];
}

//-(BOOL) shouldSimulEncode {
//    return [_simultaneousEncode boolValue];
//}
//
-(BOOL) shouldSkipCommercials {
    return [_skipCommercials boolValue];
}

-(BOOL) shouldMarkCommercials {
    return [_markCommercials boolValue];
}

-(BOOL) canAddToiTunes {
    return self.encodeFormat.canAddToiTunes;
 }

-(BOOL) shouldAddToiTunes {
    return [self.addToiTunes boolValue];
}

-(void) setEncodeFormat:(MTFormat *) encodeFormat {
    if (_encodeFormat != encodeFormat ) {
        BOOL iTunesWasDisabled = ![self canAddToiTunes];
        BOOL skipWasDisabled = ![self canSkipCommercials];
        _encodeFormat = encodeFormat;
//        if (!self.canSimulEncode && self.shouldSimulEncode) {
//            //no longer possible
//            self.simultaneousEncode = [NSNumber numberWithBool:NO];
//        } else if (simulWasDisabled && [self canSimulEncode]) {
//            //newly possible, so take user default
//            self.simultaneousEncode = [NSNumber numberWithBool:([[NSUserDefaults standardUserDefaults] boolForKey:kMTSimultaneousEncode] && self.encodeFormat.canSimulEncode)];
//        }
        if (!self.canAddToiTunes && self.shouldAddToiTunes) {
            //no longer possible
            self.addToiTunes = [NSNumber numberWithBool:NO];
        } else if (iTunesWasDisabled && [self canAddToiTunes]) {
            //newly possible, so take user default
            self.addToiTunes = [NSNumber numberWithBool:([[NSUserDefaults standardUserDefaults] boolForKey:kMTiTunesSubmit] && self.encodeFormat.canAddToiTunes)];
        }
        if (!self.canSkipCommercials && self.shouldSkipCommercials) {
            //no longer possible
            self.skipCommercials = [NSNumber numberWithBool:NO];
        } else if (skipWasDisabled && [self canSkipCommercials]) {
            //newly possible, so take user default
            self.skipCommercials = [NSNumber numberWithBool:([[NSUserDefaults standardUserDefaults] boolForKey:@"RunComSkip"] && self.encodeFormat.comSkip)];
        }
    }
}
- (void) formatMayHaveChanged{
	//if format list is updated, we need to ensure our format still exists
	//known bug: if name of current format changed, we will not find correct one
	self.encodeFormat = [tiVoManager findFormat:self.encodeFormat.name];
}

-(NSString *) description {
	return [NSString stringWithFormat:@"Subscription:%@ lastAt:%@ format:%@", self.seriesTitle, self.lastRecordedTime, self.encodeFormat];
}


- (void)dealloc
{
     _encodeFormat = nil;
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}
@end


@implementation NSMutableArray (MTSubscriptionList)


#pragma mark - Subscription Management

-(void) checkSubscriptionShow:(MTTiVoShow *) thisShow {
	DDLogVerbose(@"checking Subscription for %@", thisShow);
	if ([self isSubscribed:thisShow]) {
		if ([tiVoManager findInDownloadQueue: thisShow] == nil) {
			DDLogDetail(@"Subscribed; adding %@", thisShow);
			MTDownload * newDownload = [[MTDownload  alloc] init];
			newDownload.show= thisShow;
			[newDownload prepareForDownload:YES];
			MTSubscription * subscription = [self findShow:thisShow];
			newDownload.encodeFormat = subscription.encodeFormat;
			newDownload.addToiTunesWhenEncoded = ([subscription canAddToiTunes] && [subscription shouldAddToiTunes]);
//			newDownload.simultaneousEncode = ([subscription canSimulEncode] && [subscription shouldSimulEncode]);
			newDownload.downloadDirectory = [tiVoManager downloadDirectory];  //should we have one per subscription? UI?

			newDownload.exportSubtitles = subscription.exportSubtitles;
			newDownload.skipCommercials = newDownload.encodeFormat.comSkip.boolValue && subscription.skipCommercials.boolValue;
			newDownload.markCommercials = newDownload.encodeFormat.canMarkCommercials && subscription.canMarkCommercials;
			newDownload.genTextMetaData = subscription.genTextMetaData;
			newDownload.genXMLMetaData = subscription.genXMLMetaData;
			newDownload.includeAPMMetaData =[NSNumber numberWithBool:(newDownload.encodeFormat.canAtomicParsley && subscription.includeAPMMetaData.boolValue)];
			
			[tiVoManager addToDownloadQueue:@[newDownload] beforeDownload:nil];    //should this be on main thread
		}
	}
}

-(void) checkSubscription: (NSNotification *) notification {
	[self checkSubscriptionShow: (MTTiVoShow *) notification.object];
}

-(void) checkSubscriptionsAll {
	DDLogVerbose(@"checking Subscriptions");
	for (MTTiVoShow * show in tiVoManager.tiVoShows.reverseObjectEnumerator) {
		[self checkSubscriptionShow:show];
	}
}

- (MTSubscription *) findShow: (MTTiVoShow *) show {
	NSString * seriesSearchString = show.seriesTitle;
	if (!seriesSearchString) return nil;
	BOOL isNotSuggestion = ! show.isSuggestion;
    for (MTSubscription * possMatch in self) {
        if (isNotSuggestion || possMatch.includeSuggestions.boolValue  ) {
			if ([possMatch.seriesTitle localizedCaseInsensitiveCompare:seriesSearchString] == NSOrderedSame) {
				DDLogVerbose(@"found show %@ in subscription %@", show, possMatch);
				return possMatch;
			}
        }
    }
    return nil;
}

-(BOOL) isSubscribed:(MTTiVoShow *) tivoShow {
	MTSubscription * seriesMatch = [self findShow:tivoShow];
	if (seriesMatch == nil) return NO;
    BOOL before = (tivoShow.showDate != nil) &&
                 [seriesMatch.lastRecordedTime compare: tivoShow.showDate] == NSOrderedAscending;
	DDLogVerbose(@"%@ for %@, date:%@ prev:%@", before ? @"YES": @"NO",tivoShow.showTitle, tivoShow.showDate, seriesMatch.lastRecordedTime);
	return before;
}

-(NSArray *) addSubscriptions: (NSArray *) shows {
	
	NSMutableArray * newSubs = [NSMutableArray arrayWithCapacity:shows.count];
    DDLogDetail(@"Subscribing to %@", shows);
	for (MTTiVoShow * thisShow in shows) {
		MTSubscription * newSub = [self subscribeShow:thisShow];
		if (newSub) {
			[newSubs addObject:newSub];
		}
	}
	if (newSubs.count > 0) {
		[self saveSubscriptions];
		[self checkSubscriptionsAll];
		[[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationSubscriptionsUpdated object:nil];
		return newSubs;
	} else {
		return nil;
	}
}

-(NSArray *) addSubscriptionsDL: (NSArray *) downloads {
	
	NSMutableArray * newSubs = [NSMutableArray arrayWithCapacity:downloads.count];
    DDLogDetail(@"Subscribing to %@", downloads);
	for (MTDownload * download in downloads) {
		MTSubscription * newSub = [self subscribeDownload:download];
		if (newSub) {
			[newSubs addObject:newSub];
		}
	}
	if (newSubs.count > 0) {
		[self saveSubscriptions];
		[self checkSubscriptionsAll];
		[[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationSubscriptionsUpdated object:nil];
		return newSubs;
	} else {
		return nil;
	}
}

-(MTSubscription *) createSubscription: (MTTiVoShow *) tivoShow {
	//set the "lastrecording" time for one second before this show, to include this show.
	NSDate *earlierTime = [NSDate dateWithTimeIntervalSinceReferenceDate: 0];
	if (tivoShow.showDate) {
		earlierTime = [tivoShow.showDate  dateByAddingTimeInterval:-1];
	}
	MTSubscription *newSub = [MTSubscription new];
	newSub.seriesTitle = tivoShow.seriesTitle;
	newSub.lastRecordedTime = earlierTime;
	newSub.includeSuggestions = [[NSUserDefaults standardUserDefaults] objectForKey:kMTShowSuggestions];
	[self addObject:newSub];
	return newSub;
}

-(MTSubscription *) subscribeShow:(MTTiVoShow *) tivoShow {
	if ([self findShow:tivoShow] == nil) {
		MTSubscription * newSub = [self createSubscription:tivoShow];
		//use default properties
		NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
		newSub.encodeFormat = tiVoManager.selectedFormat;
		newSub.addToiTunes = [NSNumber numberWithBool:([defaults boolForKey:kMTiTunesSubmit] && newSub.encodeFormat.canAddToiTunes)];
//		newSub.simultaneousEncode = [NSNumber numberWithBool:([defaults boolForKey:kMTSimultaneousEncode] && newSub.encodeFormat.canSimulEncode)];
		newSub.skipCommercials = [NSNumber numberWithBool:([defaults boolForKey:@"RunComSkip"] && newSub.encodeFormat.comSkip.boolValue)];
		newSub.markCommercials = [NSNumber numberWithBool:([defaults boolForKey:@"MarkCommercials"] && newSub.encodeFormat.canMarkCommercials)];
		newSub.genTextMetaData	  = [defaults objectForKey:kMTExportTextMetaData];
		newSub.genXMLMetaData	  =	[defaults objectForKey:kMTExportTivoMetaData];
		newSub.includeAPMMetaData = [defaults objectForKey:kMTExportAtomicParsleyMetaData];
		newSub.exportSubtitles	  =[defaults objectForKey:kMTExportSubtitles];
	
		DDLogVerbose(@"Subscribing show %@ as: %@ ", tivoShow, newSub);
		return newSub;
 	} else {
		return nil;
	}
}

-(MTSubscription *) subscribeDownload:(MTDownload *) download {
	//set the "lastrecording" time for one second before this show, to include this show.
	MTTiVoShow * tivoShow = download.show;
	if ([self findShow:tivoShow] == nil) {
		MTSubscription * newSub = [self createSubscription:download.show];
		// use queued properties
		newSub.encodeFormat = download.encodeFormat;
		newSub.addToiTunes = [NSNumber numberWithBool: download.addToiTunesWhenEncoded ];
//		newSub.simultaneousEncode = [NSNumber numberWithBool: download.simultaneousEncode];
		newSub.skipCommercials = [NSNumber numberWithBool: download.skipCommercials];
		newSub.markCommercials = [NSNumber numberWithBool: download.markCommercials];
		newSub.genTextMetaData = [NSNumber numberWithBool: download.genTextMetaData];
		newSub.genXMLMetaData = [NSNumber numberWithBool: download.genXMLMetaData];
		newSub.includeAPMMetaData = [NSNumber numberWithBool: download.includeAPMMetaData];
		newSub.exportSubtitles= [NSNumber numberWithBool: download.exportSubtitles];
		DDLogVerbose(@"Subscribing download %@ as: %@ ", tivoShow, newSub);
		return newSub;
 	} else {
		return nil;
	}
}


-(void) deleteSubscriptions:(NSArray *) subscriptions {
	DDLogDetail(@"Removing Subscriptions: %@", subscriptions);
	[self  removeObjectsInArray:subscriptions];
	[self saveSubscriptions];
	[[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationSubscriptionsUpdated object:nil];

}

-(void)updateSubscriptionWithDate: (NSNotification *) notification
{
	MTDownload * download = (MTDownload *)notification.object;
	MTTiVoShow * tivoShow = download.show;
	MTSubscription * seriesMatch = [self findShow:tivoShow];
	if (seriesMatch && tivoShow.showDate) {
		DDLogDetail(@"Updating time on Subscriptions: %@ to %@", seriesMatch, tivoShow.showDate);
		seriesMatch.lastRecordedTime = tivoShow.showDate;
		[self saveSubscriptions];
		
	}
}
-(void) loadSubscriptions {
    NSArray * tempArray = [[NSUserDefaults standardUserDefaults] objectForKey:kMTSubscriptionList];
    [self removeAllObjects];
    
	DDLogDetail(@"Loading subscriptions");
    for (NSDictionary * sub in tempArray) {
        MTSubscription * tempSub = [[MTSubscription alloc] init];
        tempSub.seriesTitle = sub[kMTSubscribedSeries];
		NSDate *earlierTime = [NSDate dateWithTimeIntervalSinceReferenceDate: 0];
        if (sub[kMTSubscribedDate]) {
            earlierTime = sub[kMTSubscribedDate];
        }
       tempSub.lastRecordedTime = earlierTime;
        
        tempSub.encodeFormat= [tiVoManager findFormat:sub[kMTSubscribedFormat] ];
        
        tempSub.addToiTunes = sub[kMTSubscribediTunes];
        if (tempSub.addToiTunes ==nil) tempSub.addToiTunes = [NSNumber numberWithBool:([[NSUserDefaults standardUserDefaults] boolForKey:kMTiTunesSubmit] && tempSub.encodeFormat.canAddToiTunes)];
                                                    
//        tempSub.simultaneousEncode = sub[kMTSubscribedSimulEncode];
//        if (tempSub.simultaneousEncode ==nil) tempSub.simultaneousEncode = [NSNumber numberWithBool: ([[NSUserDefaults standardUserDefaults] boolForKey:kMTSimultaneousEncode] && tempSub.encodeFormat.canSimulEncode)];
		tempSub.includeSuggestions = sub[kMTSubscribedIncludeSuggestions];
		if (tempSub.includeSuggestions ==nil) tempSub.includeSuggestions = [[NSUserDefaults standardUserDefaults] objectForKey:kMTShowSuggestions];
		tempSub.skipCommercials = sub[kMTSubscribedSkipCommercials];
		if (tempSub.skipCommercials ==nil) tempSub.skipCommercials = [[NSUserDefaults standardUserDefaults] objectForKey:kMTRunComSkip];
		tempSub.markCommercials = sub[kMTSubscribedMarkCommercials];
		if (tempSub.markCommercials ==nil) tempSub.markCommercials = [[NSUserDefaults standardUserDefaults] objectForKey:kMTMarkCommercials];
		tempSub.genTextMetaData = sub[kMTSubscribedGenTextMetaData];
		if (tempSub.genTextMetaData ==nil) tempSub.genTextMetaData = [[NSUserDefaults standardUserDefaults] objectForKey:kMTExportTextMetaData];
		tempSub.genXMLMetaData = sub[kMTSubscribedGenXMLMetaData];
		if (tempSub.genXMLMetaData ==nil) tempSub.genXMLMetaData = [[NSUserDefaults standardUserDefaults] objectForKey:kMTExportTivoMetaData];
		tempSub.includeAPMMetaData = sub[kMTSubscribedIncludeAPMMetaData];
		if (tempSub.includeAPMMetaData ==nil) tempSub.includeAPMMetaData = [[NSUserDefaults standardUserDefaults] objectForKey:kMTExportAtomicParsleyMetaData];
		tempSub.exportSubtitles = sub[kMTSubscribedExportSubtitles];
		if (tempSub.exportSubtitles ==nil) tempSub.exportSubtitles = [[NSUserDefaults standardUserDefaults] objectForKey:kMTExportSubtitles];

		DDLogVerbose(@"Loaded Sub: %@ from %@",tempSub, sub);
        [self addObject:tempSub];
    }
}

- (void)saveSubscriptions {
    NSMutableArray *tempArray = [[NSMutableArray alloc] initWithCapacity:self.count];
    for (MTSubscription * sub in self) {
        NSDictionary * tempSub = [NSDictionary dictionaryWithObjectsAndKeys:
                                  sub.seriesTitle, kMTSubscribedSeries,
                                  sub.encodeFormat.name, kMTSubscribedFormat,
                                  sub.lastRecordedTime, kMTSubscribedDate,
                                  sub.addToiTunes, kMTSubscribediTunes,
//                                  sub.simultaneousEncode, kMTSubscribedSimulEncode,
                                  sub.includeSuggestions, kMTSubscribedIncludeSuggestions,
								  sub.skipCommercials, kMTSubscribedSkipCommercials,
								  sub.markCommercials, kMTSubscribedMarkCommercials,
                                  sub.genTextMetaData , kMTSubscribedGenTextMetaData,
                                  sub.genXMLMetaData, kMTSubscribedGenXMLMetaData,
                                  sub.includeAPMMetaData, kMTSubscribedIncludeAPMMetaData,
                                  sub.exportSubtitles, kMTSubscribedExportSubtitles,
								  nil];
		DDLogVerbose(@"Saving Sub: %@ ",tempSub);
		[tempArray addObject:tempSub];
    }
    [[NSUserDefaults standardUserDefaults] setObject:tempArray forKey:kMTSubscriptionList];
    [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationSubscriptionsUpdated object:nil];
}

- (void)dealloc
{
    
}

@end
