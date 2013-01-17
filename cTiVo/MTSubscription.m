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


-(BOOL) canSimulEncode {
    return self.encodeFormat.canSimulEncode;
}

-(BOOL) shouldSimulEncode {
    return [_simultaneousEncode boolValue];
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
        [_encodeFormat release];
        _encodeFormat = [encodeFormat retain];
        if (!self.canSimulEncode && self.shouldSimulEncode) {
            //no longer possible
            self.simultaneousEncode = [NSNumber numberWithBool:NO];
        } else if (simulWasDisabled && [self canSimulEncode]) {
            //newly possible, so take user default
            self.simultaneousEncode = [NSNumber numberWithBool:[tiVoManager simultaneousEncode]];
        }
        if (!self.canAddToiTunes && self.shouldAddToiTunes) {
            //no longer possible
            self.addToiTunes = [NSNumber numberWithBool:NO];
        } else if (iTunesWasDisabled && [self canAddToiTunes]) {
            //newly possible, so take user default
            self.addToiTunes = [NSNumber numberWithBool:[tiVoManager addToItunes]];
        }
    }
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
   if ([self isSubscribed:thisShow] && ([thisShow.downloadStatus intValue] == kMTStatusNew)) {
       MTSubscription * subscription = [self findShow:thisShow];
       thisShow.encodeFormat = subscription.encodeFormat;
       thisShow.addToiTunesWhenEncoded = ([subscription canAddToiTunes] && [subscription shouldAddToiTunes]);
       thisShow.simultaneousEncode = ([subscription canSimulEncode] && [subscription shouldSimulEncode]);
        [tiVoManager addProgramToDownloadQueue:thisShow];
	}
}

-(void) checkSubscription: (NSNotification *) notification {
	[self checkSubscriptionShow: (MTTiVoShow *) notification.object];
}

-(void) checkSubscriptionsAll {
	for (MTTiVoShow * show in tiVoManager.tiVoShows.reverseObjectEnumerator) {
		[self checkSubscriptionShow:show];
	}
}

- (MTSubscription *) findShow: (MTTiVoShow *) show {
	NSString * seriesSearchString = show.seriesTitle;
	if (!seriesSearchString) return nil;
    for (MTSubscription * possMatch in self) {
        if ([possMatch.seriesTitle localizedCaseInsensitiveCompare:seriesSearchString] == NSOrderedSame) {
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
	//   NSLog(@"%@ for %@, date:%@ prev:%@", before ? @"YES": @"NO",tivoShow.showTitle, tivoShow.showDate, prevRecording);
	return before;
}


-(void) addSubscription:(MTTiVoShow *) tivoShow {
	//set the "lastrecording" time for one second before this show, to include this show.
	if ([self findShow:tivoShow] == nil) {
        NSDate *earlierTime = [NSDate dateWithTimeIntervalSinceReferenceDate: 0];
        if (tivoShow.showDate) {
            earlierTime = [tivoShow.showDate  dateByAddingTimeInterval:-1];
        }
        MTSubscription *newSub = [[MTSubscription new] autorelease];
        newSub.seriesTitle = tivoShow.seriesTitle;
        newSub.lastRecordedTime = earlierTime;
        newSub.encodeFormat = tiVoManager.selectedFormat;
        newSub.addToiTunes = [NSNumber numberWithBool:
                                    tiVoManager.addToItunes];
        newSub.simultaneousEncode = [NSNumber numberWithBool:
                                     tiVoManager.simultaneousEncode];
        [self addObject:newSub];
        [self saveSubscriptions];
 	}
}

-(void)updateSubscriptionWithDate: (NSNotification *) notification
{
	MTTiVoShow * tivoShow = (MTTiVoShow *)notification.object;
	MTSubscription * seriesMatch = [self findShow:tivoShow];
	if (seriesMatch && tivoShow.showDate) {
		seriesMatch.lastRecordedTime = tivoShow.showDate;
		[self saveSubscriptions];
		
	}
}
-(void) loadSubscriptions {
    NSArray * tempArray = [[NSUserDefaults standardUserDefaults] objectForKey:kMTSubscriptionList];
    [self removeAllObjects];
    
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
        if (tempSub.addToiTunes ==nil) tempSub.addToiTunes = [NSNumber numberWithBool: [tiVoManager addToItunes]];
                                                    
        tempSub.simultaneousEncode = sub[kMTSubscribedSimulEncode];
        if (tempSub.simultaneousEncode ==nil) tempSub.simultaneousEncode = [NSNumber numberWithBool: [tiVoManager simultaneousEncode]];
        
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
