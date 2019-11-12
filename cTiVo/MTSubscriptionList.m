//
//  MTSubscriptionList.m
//  cTiVo
//
//  Created by Hugh Mackworth on 12/9/14.
//  Copyright (c) 2014 cTiVo. All rights reserved.
//

#import "MTSubscriptionList.h"
#import "MTTiVoManager.h"

@implementation NSMutableArray (SubscriptionList)

#define ddLogLevel [[MTSubscription class] ddLogLevel]

#pragma mark - Subscription Management

-(void) initialLastLoadedTimes { //called when TivoList changes
    for (MTTiVo * tivo in tiVoManager.tiVoList) {  //ensure all are in the dictionary
        if (!tivo.tiVo.name) continue;   //should never happen, yet it did once...
        if (!tiVoManager.lastLoadedTivoTimes[tivo.tiVo.name]) {
            tiVoManager.lastLoadedTivoTimes[tivo.tiVo.name] = [NSDate distantPast];  //first time, so mark as not processed yet
        }
    }
}

- (NSDate *) oldestPossibleSubscriptionTime {
    //returns the oldest time our tivos have been seen.
    //used to expire old subscriptions
    //incidentally drops really old tivos (over 90 days)
    //note that this may return "distant past" if a tivo has been seen, but not fully processed yet
    NSInteger numDays = [[NSUserDefaults standardUserDefaults] integerForKey: kMTSubscriptionExpiration];
    if (numDays == 0) numDays = 30;
    NSDate * returnDate = [NSDate dateWithTimeIntervalSinceNow:-60*60*24*numDays]; //keep at least 30 days
    for (NSString * tivoName in [tiVoManager.lastLoadedTivoTimes allKeys]) {
        NSDate * tivoTime=  tiVoManager.lastLoadedTivoTimes[tivoName];
        if ((tivoTime != [NSDate distantPast] && [tivoTime timeIntervalSinceNow] >= 60*60*24*90)) {
            DDLogReport(@"tivo %@ away too long; removing from list",tivoName);
            [tiVoManager.lastLoadedTivoTimes removeObjectForKey: tivoName];
            continue;
        }
        if ([returnDate isGreaterThan: tivoTime] ) {
            returnDate = tivoTime;
        };
    }
    DDLogVerbose(@"oldest Tivo = %@",returnDate);
    return returnDate;

}

/*
 If your TiVo(s) record(s) two copies of the same episode more than a week apart, so will cTiVo.  It does remember episodeIds within the last month to avoid too many dups.

 To be specific, MTSubscription>isSubscribed checks (an expanded version of) episodeID against prevRecording before confirming a subscription, but
 every time we save out the subscription list (MTSubscriptionLIst>saveSubscription, we truncate the prevRecording lists to the most recent ones
 (just ones since  MTSubscriptionList>oldestPossibleSubscriptionTime, which is a little complicated to handle
 multiple TiVos that may not check in regularly, but at least 30 days worth  and at most 90
 */

-(void) launchDownload: (MTDownload *) download {
	[tiVoManager addToDownloadQueue:@[download] beforeDownload:nil];
}

-(void) checkSubscription: (NSNotification *) notification {
    //called by system when a new show appears in listing, including all shows at startup
    MTTiVoShow * thisShow = (MTTiVoShow *) notification.object;
    NSDate * earliestTime = [tiVoManager. lastLoadedTivoTimes[thisShow.tiVoName] dateByAddingTimeInterval:-60*60*12];
    //any show that started within twelve hours of last checkin is worth looking at.
    //note that theoretically, 12 hours could be replace by thisshow.duration if we parsed Tivos'  PT00H0M0S format;
    if ([thisShow.showDate isGreaterThan: earliestTime]) {
        if (!thisShow.isOnDisk) {
            DDLogDetail(@"Subscription check  %@: recent enough: %@ v %@", thisShow, thisShow.showDate, earliestTime);
            for (MTSubscription * possMatch in self) {
                if ([possMatch isSubscribed:thisShow ignoreDate:NO]) {
                    MTDownload * newDownload = [possMatch downloadForSubscribedShow:thisShow];
					if (thisShow.rpcData == nil && thisShow.tiVo.supportsRPC) {
						//wait until tivo has a chance to fill in RPC info
						[self performSelector:@selector(launchDownload:) withObject:newDownload afterDelay:3.0];
					} else {
						[self launchDownload:newDownload];
					}
                }
            }
        } else {
            DDLogDetail(@"Subscription check  %@: already recorded: %@ v %@", thisShow, thisShow.showDate, earliestTime);
        }
    } else {
        DDLogVerbose(@"Subscription check: %@ too old: %@ v %@", thisShow, thisShow.showDate, earliestTime);
    }
}

-(void) checkSubscriptionsNew:(NSArray *) newSubs {
    //Called after one or more subscriptions have been created or when reapplying. Ignores tivoLoadTimes to incorporate all current shows
    DDLogVerbose(@"checking New Subscriptions");
    for (MTTiVoShow * thisShow in tiVoManager.tiVoShows.reverseObjectEnumerator) {
        for (MTSubscription * possMatch in newSubs) {
            if ([possMatch isSubscribed:thisShow ignoreDate:YES]) {
                MTDownload * newDownload = [possMatch downloadForSubscribedShow:thisShow];
                [tiVoManager addToDownloadQueue:@[newDownload] beforeDownload:nil];
            }
        }
    }
}

-(void) clearHistory:(NSArray *) subscriptions {
    for (MTSubscription * sub in subscriptions) {
        sub.prevRecorded = [NSMutableArray new];
        sub.createdTime = [NSDate dateWithTimeIntervalSinceReferenceDate: 0];
    }
}

- (MTSubscription *) findShow: (MTTiVoShow *) show {
    MTSubscription * possMatch = [self findSubscriptionNamed:show.seriesTitle checkSuggestion:show.isSuggestion checkTiVo:show.tiVo checkChannel:show.stationCallsign ];
    if (possMatch) DDLogVerbose(@"found show %@ in subscription %@", show, possMatch);
    return possMatch;
}

-(MTSubscription *) findSubscriptionNamed: (NSString *) seriesSearchString checkSuggestion: (BOOL) followSubsSuggestionValue checkTiVo: (MTTiVo *) tiVo checkChannel: (NSString *) channelName{

    if (!seriesSearchString) return nil;
    for (MTSubscription * possMatch in self) {
        if (!followSubsSuggestionValue || possMatch.includeSuggestions.boolValue  ) {
            if ([possMatch.subscriptionRegex
                 numberOfMatchesInString:seriesSearchString
                 options:0
                 range:NSMakeRange(0,seriesSearchString.length)
                 ] <= 0) {
				continue;
			}
			//Now check that we're on the right Tivo, if specified
			if ((possMatch.preferredTiVo.length > 0) && (![possMatch.preferredTiVo isEqualToString: tiVo.tiVo.name]))  {
				continue;
			}
			//check that we're on right station if specified
			if (possMatch.stationCallSign.length > 0 && ![possMatch.stationCallSign isEqualToString:channelName]) {
				continue;
			}
			return possMatch;
        }
    }
    return nil;
}


-(NSArray *) addSubscriptionsShows: (NSArray *) shows {

    NSMutableArray * newSubs = [NSMutableArray arrayWithCapacity:shows.count];
    DDLogDetail(@"Subscribing to shows %@", shows);
    for (MTTiVoShow * thisShow in shows) {
		if ([newSubs findShow:thisShow]) continue; //only one sub per series
        MTSubscription * newSub = [self subscribeShow:thisShow];
        if (newSub) {
            [newSubs addObject:newSub];
        }
    }
    if (newSubs.count > 0) {
        [self checkSubscriptionsNew:newSubs];
        [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationSubscriptionsUpdated object:nil];
        return newSubs;
    } else {
        return nil;
    }
}

-(NSArray *) addSubscriptionsDL: (NSArray *) downloads {

    NSMutableArray * newSubs = [NSMutableArray arrayWithCapacity:downloads.count];
    DDLogDetail(@"Subscribing to downloads %@", downloads);
    for (MTDownload * download in downloads) {
		if ([newSubs findShow:download.show]) continue; //only one sub per series
		MTSubscription * newSub = [self subscribeDownload:download];
        if (newSub) {
            [newSubs addObject:newSub];
        }
    }
    if (newSubs.count > 0) {
		[self checkSubscriptionsNew:newSubs]; //minor bug: will duplicate the subscribing download.
        [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationSubscriptionsUpdated object:nil];
        return newSubs;
    } else {
        return nil;
    }
}
-(NSArray *) divideStringIntoLines:(NSString *) str {
    NSUInteger length = [str length];
    NSUInteger paraStart = 0, paraEnd = 0, contentsEnd = 0;
    NSMutableArray *array = [NSMutableArray array];
    NSRange currentRange;
    while (paraEnd < length) {
        [str getParagraphStart:&paraStart end:&paraEnd
                      contentsEnd:&contentsEnd forRange:NSMakeRange(paraEnd, 0)];
        currentRange = NSMakeRange(paraStart, contentsEnd - paraStart);
        [array addObject:[str substringWithRange:currentRange]];
    }
    return [NSArray arrayWithArray:array];
}

-(NSArray *) addSubscriptionsFormattedStrings: (NSArray *) strings {
    NSMutableArray * newSubs = [NSMutableArray arrayWithCapacity:strings.count];
    DDLogDetail(@"Subscribing to strings %@", strings);
    for (NSString * multilineString in strings) {
        for (NSString * str in [self divideStringIntoLines:multilineString]) {
            MTSubscription * newSub = [MTSubscription subscriptionFromString:str];
            if (newSub &&  ([[NSUserDefaults standardUserDefaults]boolForKey:kMTAllowDups] || ![self findSubscriptionNamed:newSub.displayTitle checkSuggestion:NO checkTiVo:nil checkChannel:nil]	)) {
                [newSubs addObject:newSub];
                [self addObject:newSub];
            }
        }
    }
    if (newSubs.count > 0) {
        [self checkSubscriptionsNew:newSubs];
        [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationSubscriptionsUpdated object:nil];
        return newSubs;
    } else {
        return nil;
    }


}

-(NSArray *) addSubscriptionsPatterns: (NSArray *) patterns {
    NSMutableArray * newSubs = [NSMutableArray arrayWithCapacity:patterns.count];
   for (NSString * pattern in patterns) {
        NSString * regexPattern = pattern;
        NSString * regexName = pattern;
        //now see if we have a "regexString<regexName>"

        if ([[pattern stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet] ] isEqualToString:@"ALL"]) {
            regexPattern = @".*";
            regexName = @" <<ALL SHOWS>> ";
        } else {
            NSRegularExpression * inputParse =  [NSRegularExpression regularExpressionWithPattern:@"^(.*)<(.*)>\\s*" options:0 error:nil];
            NSTextCheckingResult * textResult = [inputParse firstMatchInString:pattern options:0 range:NSMakeRange(0, pattern.length)];
            if (textResult) {
                regexPattern = [pattern substringWithRange:[textResult rangeAtIndex:1]];
                regexName = [pattern substringWithRange:[textResult rangeAtIndex:2]];
            }
        }
        DDLogDetail(@"Subscribing to string %@ with pattern %@", regexName, regexPattern);
        NSRegularExpression *tempRegex = [NSRegularExpression regularExpressionWithPattern:regexPattern options:NSRegularExpressionCaseInsensitive error:nil];
        if (!tempRegex) return nil;
        MTTiVoShow * pseudoShow = [MTTiVoShow new]; //just a dummy to carry seriesTitle and Date
        pseudoShow.seriesTitle = regexName;

        pseudoShow.showDate = [NSDate dateWithTimeIntervalSince1970:0];

        MTSubscription * newSub = [self subscribeShow:pseudoShow ];
        if (newSub) {
            newSub.subscriptionRegex = tempRegex;
            [newSubs addObject:newSub];
            //for manual titles, we allow regex matching without being the entire series
        }
    }
    if (newSubs.count> 0) {
        [self checkSubscriptionsNew:newSubs];
        [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationSubscriptionsUpdated object:nil];
        return newSubs;
} else {
    return nil;
}

}

-(MTSubscription *) subscribeShow:(MTTiVoShow *) tivoShow {
	if ([self findShow:tivoShow] == nil || [[NSUserDefaults standardUserDefaults] boolForKey:kMTAllowDups]) {
        MTSubscription * newSub = [MTSubscription subscriptionFromShow:tivoShow];
        //use default properties
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        newSub.addToiTunes =     @([defaults boolForKey:kMTiTunesSubmit] && newSub.encodeFormat.canAddToiTunes);
		newSub.useSkipMode =     @(([defaults integerForKey:kMTCommercialStrategy] > 1) && tivoShow.mightHaveSkipModeInfo);
        newSub.skipCommercials = @([defaults boolForKey:kMTSkipCommercials] && newSub.encodeFormat.comSkip.boolValue);
        newSub.markCommercials = @([defaults boolForKey:kMTMarkCommercials] && newSub.encodeFormat.canMarkCommercials);
        newSub.genTextMetaData=  [defaults objectForKey:kMTExportTextMetaData];
        newSub.exportSubtitles	  = [defaults objectForKey:kMTExportSubtitles];
		newSub.deleteAfterDownload= [defaults objectForKey:kMTIfSuccessDeleteFromTiVo];
		newSub.encodeFormat = tiVoManager.selectedFormat;

        DDLogVerbose(@"Subscribing show %@ as: %@ ", tivoShow, newSub);
        [self addObject:newSub];
        return newSub;
    } else {
        return nil;
    }
}

-(MTSubscription *) subscribeDownload:(MTDownload *) download {
    //set the "lastrecording" time for one second before this show, to include this show.
    MTTiVoShow * tivoShow = download.show;
	if ([self findShow:tivoShow] == nil || [[NSUserDefaults standardUserDefaults] boolForKey:kMTAllowDups]) {
        MTSubscription * newSub = [MTSubscription subscriptionFromShow: download.show];
        // use queued properties
        newSub.addToiTunes = [NSNumber numberWithBool: download.addToiTunesWhenEncoded ];
        newSub.skipCommercials = [NSNumber numberWithBool: download.skipCommercials];
		newSub.markCommercials = [NSNumber numberWithBool: download.markCommercials];
		newSub.useSkipMode = [NSNumber numberWithBool: download.useSkipMode];
        newSub.genTextMetaData = download.genTextMetaData;
        newSub.exportSubtitles=  download.exportSubtitles;
		newSub.deleteAfterDownload=  download.deleteAfterDownload;
		newSub.encodeFormat = download.encodeFormat;
        DDLogVerbose(@"Subscribing download %@ as: %@ ", tivoShow, newSub);
        [self addObject:newSub];
        return newSub;
    } else {
        return nil;
    }
}

-(void) deleteSubscriptions:(NSArray *) subscriptions {
    DDLogDetail(@"Removing Subscriptions: %@", subscriptions);
    [self  removeObjectsInArray:subscriptions];
    [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationSubscriptionsUpdated object:nil];
}

-(void) loadSubscriptions {
    NSArray * tempArray = [[NSUserDefaults standardUserDefaults] objectForKey:kMTSubscriptionList];
    [self removeAllObjects];

    DDLogDetail(@"Loading subscriptions");
    for (NSDictionary * sub in tempArray) {
        MTSubscription * tempSub =         [MTSubscription subscriptionFromDictionary: sub];
        [self addObject:tempSub];
    }
}

- (void)saveSubscriptions {
    NSMutableArray *tempArray = [[NSMutableArray alloc] initWithCapacity:self.count];
    NSDate * cutoffDate = [self oldestPossibleSubscriptionTime];
    for (MTSubscription * sub in self) {
        NSMutableArray * removeSubs= [NSMutableArray new];
        for (NSDictionary * recording in sub.prevRecorded) {
            if (recording == sub.prevRecorded[0]) continue; //save youngest to display last recorded date
            if ([recording[@"startTime"] isLessThan: cutoffDate]) {
                //too old; no need to remember this one.
                [removeSubs addObject:recording];
            }
        }
        if (removeSubs.count > 0) {
            DDLogDetail(@"removing old subs older than %@: %@",cutoffDate,removeSubs);
            [sub.prevRecorded removeObjectsInArray:removeSubs];
        }

        NSString * pattern = [sub.subscriptionRegex pattern];
        ///defaults here should not happen, but just to avoid silent nils
        NSDictionary * tempSub = [NSDictionary dictionaryWithObjectsAndKeys:
                                  sub.displayTitle      ?: @"??",   kMTSubscribedSeries,
                                  pattern               ?: @"",     kMTSubscribedRegExPattern,
                                  sub.encodeFormat.name ?: @"",     kMTSubscribedFormat,
                                  sub.createdTime       ?: [NSDate date], kMTCreatedDate,
                                  sub.addToiTunes       ?: @YES,    kMTSubscribediTunes,
                                  sub.includeSuggestions?: @NO,     kMTSubscribedIncludeSuggestions,
                                  sub.skipCommercials   ?: @NO,     kMTSubscribedSkipCommercials,
								  sub.markCommercials   ?: @YES,    kMTSubscribedMarkCommercials,
								  sub.useSkipMode       ?: @YES,    kMTSubscribedUseSkipMode,
                                  sub.genTextMetaData   ?: @NO ,    kMTSubscribedGenTextMetaData,
                                  sub.exportSubtitles   ?: @NO,     kMTSubscribedExportSubtitles,
								  sub.deleteAfterDownload   ?: @NO,     kMTSubscribedDeleteAfterDownload,
                                  sub.preferredTiVo     ?: @"",     kMTSubscribedPreferredTiVo,
                                  sub.HDOnly            ?: @NO,     kMTSubscribedHDOnly,
                                  sub.SDOnly            ?: @NO,     kMTSubscribedSDOnly,
                                  sub.prevRecorded      ?: @[],     kMTSubscribedPrevRecorded,
								  sub.stationCallSign         ,     kMTSubscribedCallSign, // probably nil
								  nil];
        DDLogVerbose(@"Saving Sub: %@ ",tempSub);
        [tempArray addObject:tempSub];
    }
    [[NSUserDefaults standardUserDefaults] setObject:tiVoManager.lastLoadedTivoTimes forKey:kMTTiVoLastLoadTimes];
    [[NSUserDefaults standardUserDefaults] setObject:tempArray forKey:kMTSubscriptionList];
    //May not be necessary   [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationSubscriptionsUpdated object:nil];
}

@end
