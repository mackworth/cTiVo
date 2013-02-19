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
                simultaneousEncode = _simultaneousEncode,
                encodeFormat = _encodeFormat;
__DDLOGHERE__

-(BOOL) canSimulEncode {
    return self.encodeFormat.canSimulEncode;
}

-(BOOL) canSkipCommercials {
    return self.encodeFormat.comSkip.boolValue;
}

-(BOOL) shouldSimulEncode {
    return [_simultaneousEncode boolValue];
}

-(BOOL) shouldSkipCommercials {
    return [_skipCommercials boolValue];
}

-(BOOL) canAddToiTunes {
    return self.encodeFormat.canAddToiTunes;
 }

-(BOOL) shouldAddToiTunes {
    return [self.addToiTunes boolValue];
}

-(void) setEncodeFormat:(MTFormat *) encodeFormat {
    if (_encodeFormat != encodeFormat ) {
        BOOL simulWasDisabled = ![self canSimulEncode];
        BOOL iTunesWasDisabled = ![self canAddToiTunes];
        BOOL skipWasDisabled = ![self canSkipCommercials];
        [_encodeFormat release];
        _encodeFormat = [encodeFormat retain];
        if (!self.canSimulEncode && self.shouldSimulEncode) {
            //no longer possible
            self.simultaneousEncode = [NSNumber numberWithBool:NO];
        } else if (simulWasDisabled && [self canSimulEncode]) {
            //newly possible, so take user default
            self.simultaneousEncode = [NSNumber numberWithBool:([[NSUserDefaults standardUserDefaults] boolForKey:kMTSimultaneousEncode] && self.encodeFormat.canSimulEncode)];
        }
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

-(NSString *) description {
	return [NSString stringWithFormat:@"Subscription:%@ lastAt:%@ format:%@", self.seriesTitle, self.lastRecordedTime, self.encodeFormat];
}


- (void)dealloc
{
    [_seriesTitle release]; _seriesTitle = nil;
    [_lastRecordedTime release]; _lastRecordedTime = nil;
    [_addToiTunes release]; _addToiTunes = nil;
    [_simultaneousEncode release]; _simultaneousEncode = nil;
    [_encodeFormat release]; _encodeFormat = nil;
    [super dealloc];
}
@end


@implementation NSMutableArray (MTSubscriptionList)


#pragma mark - Subscription Management

-(void) checkSubscriptionShow:(MTTiVoShow *) thisShow {
	DDLogVerbose(@"checking Subscription for %@", thisShow);
	if ([self isSubscribed:thisShow] && (thisShow.isNew)) {
		DDLogDetail(@"Subscribed; adding %@", thisShow);
       MTSubscription * subscription = [self findShow:thisShow];
       thisShow.encodeFormat = subscription.encodeFormat;
       thisShow.addToiTunesWhenEncoded = ([subscription canAddToiTunes] && [subscription shouldAddToiTunes]);
       thisShow.simultaneousEncode = ([subscription canSimulEncode] && [subscription shouldSimulEncode]);
	   thisShow.downloadDirectory = [tiVoManager downloadDirectory];  //should we have one per subscription? UI?
	   [tiVoManager addProgramToDownloadQueue:thisShow];
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
    for (MTSubscription * possMatch in self) {
        if ([possMatch.seriesTitle localizedCaseInsensitiveCompare:seriesSearchString] == NSOrderedSame) {
			DDLogVerbose(@"found show %@ in subscription %@", show, possMatch);
            return possMatch;
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
		MTSubscription * newSub = [self addSubscription:thisShow];
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

-(MTSubscription *) addSubscription:(MTTiVoShow *) tivoShow {
	//set the "lastrecording" time for one second before this show, to include this show.
	if ([self findShow:tivoShow] == nil) {
        NSDate *earlierTime = [NSDate dateWithTimeIntervalSinceReferenceDate: 0];
        if (tivoShow.showDate) {
            earlierTime = [tivoShow.showDate  dateByAddingTimeInterval:-1];
        }
		NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        MTSubscription *newSub = [[MTSubscription new] autorelease];
        newSub.seriesTitle = tivoShow.seriesTitle;
        newSub.lastRecordedTime = earlierTime;
        if ([tiVoManager.downloadQueue containsObject:tivoShow]) {
			//then use queued properties
			newSub.encodeFormat = tivoShow.encodeFormat;
			newSub.addToiTunes = tivoShow.addToiTunesWhenEncoded;
			newSub.simultaneousEncode = tivoShow.simultaneousEncode;
			newSub.skipCommercials = tivoShow.skipCommercials;
			newSub.genTextMetaData = tivoShow.genTextMetaData;
			newSub.genXMLMetaData = tivoShow.genXMLMetaData;
			newSub.includeAPMMetaData = tivoShow.includeAPMMetaData;
			newSub.exportSubtitles= tivoShow.exportSubtitles;
		} else {
			//use default properties
			newSub.encodeFormat = tiVoManager.selectedFormat;
			newSub.addToiTunes = [NSNumber numberWithBool:([defaults boolForKey:kMTiTunesSubmit] && newSub.encodeFormat.canAddToiTunes)];
			newSub.simultaneousEncode = [NSNumber numberWithBool:([defaults boolForKey:kMTSimultaneousEncode] && newSub.encodeFormat.canSimulEncode)];
			newSub.skipCommercials = [NSNumber numberWithBool:([defaults boolForKey:@"RunComSkip"] && newSub.encodeFormat.comSkip)];
			newSub.genTextMetaData	  = [defaults objectForKey:kMTExportTextMetaData];
			newSub.genXMLMetaData	  =	[defaults objectForKey:kMTExportTivoMetaData];
			newSub.includeAPMMetaData = [defaults objectForKey:kMTExportAtomicParsleyMetaData];
			newSub.exportSubtitles	  =[defaults objectForKey:kMTExportSubtitles];
		}
		DDLogVerbose(@"Subscribing %@ as: %@ ", tivoShow, newSub);
		[self addObject:newSub];
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
	MTTiVoShow * tivoShow = (MTTiVoShow *)notification.object;
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
        MTSubscription * tempSub = [[[MTSubscription alloc] init] autorelease];
        tempSub.seriesTitle = sub[kMTSubscribedSeries];
		NSDate *earlierTime = [NSDate dateWithTimeIntervalSinceReferenceDate: 0];
        if (sub[kMTSubscribedDate]) {
            earlierTime = sub[kMTSubscribedDate];
        }
       tempSub.lastRecordedTime = earlierTime;
        
        tempSub.encodeFormat= [tiVoManager findFormat:sub[kMTSubscribedFormat] ];
        if (tempSub.encodeFormat ==nil) tempSub.encodeFormat = [tiVoManager selectedFormat];
        
        tempSub.addToiTunes = sub[kMTSubscribediTunes];
        if (tempSub.addToiTunes ==nil) tempSub.addToiTunes = [NSNumber numberWithBool:([[NSUserDefaults standardUserDefaults] boolForKey:kMTiTunesSubmit] && tempSub.encodeFormat.canAddToiTunes)];
                                                    
        tempSub.simultaneousEncode = sub[kMTSubscribedSimulEncode];
        if (tempSub.simultaneousEncode ==nil) tempSub.simultaneousEncode = [NSNumber numberWithBool: ([[NSUserDefaults standardUserDefaults] boolForKey:kMTSimultaneousEncode] && tempSub.encodeFormat.canSimulEncode)];
        DDLogVerbose(@"Loaded Sub: %@ from %@",tempSub, sub);
        [self addObject:tempSub];
    }
}

- (void)saveSubscriptions {
    NSMutableArray *tempArray = [[[NSMutableArray alloc] initWithCapacity:self.count] autorelease];
    for (MTSubscription * sub in self) {
        NSDictionary * tempSub = [NSDictionary dictionaryWithObjectsAndKeys:
                                  sub.seriesTitle, kMTSubscribedSeries,
                                  sub.encodeFormat.name, kMTSubscribedFormat,
                                  sub.lastRecordedTime, kMTSubscribedDate,
                                  sub.addToiTunes, kMTSubscribediTunes,
                                  sub.simultaneousEncode, kMTSubscribedSimulEncode,
                                  nil];
		DDLogVerbose(@"Saving Sub: %@ ",tempSub);
		[tempArray addObject:tempSub];
    }
    [[NSUserDefaults standardUserDefaults] setObject:tempArray forKey:kMTSubscriptionList];
    [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationSubscriptionsUpdated object:nil];
}

/*
- (void)saveSubscriptions {
    NSData *myEncodedObject = [NSKeyedArchiver archivedDataWithRootObject:self];
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:myEncodedObject forKey:@"myEncodedObjectKey"];
}

- (MyCustomObject *)loadCustomObjectWithKey:(NSString *)key {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSData *myEncodedObject = [defaults objectForKey:key];
    MyCustomObject *obj = (MyCustomObject *)[NSKeyedUnarchiver unarchiveObjectWithData: myEncodedObject];
    return obj;
}
*/
- (void)dealloc
{
    
    [super dealloc];
}

@end
