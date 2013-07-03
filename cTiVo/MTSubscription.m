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

__DDLOGHERE__

-(id) init {
	if ((self = [super init])) {
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(formatMayHaveChanged) name:kMTNotificationFormatListUpdated object:nil];
		_prevRecorded = [NSMutableArray new];
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
        BOOL markWasDisabled = ![self canMarkCommercials];
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
        if (!self.canMarkCommercials && self.shouldMarkCommercials) {
            //no longer possible
            self.markCommercials = NO;
        } else if (markWasDisabled && [self canMarkCommercials]) {
            //newly possible, so take user default
            self.markCommercials = [[NSUserDefaults standardUserDefaults] objectForKey:@"MarkCommercials"];
        }
    }
}
- (void) formatMayHaveChanged{
	//if format list is updated, we need to ensure our format still exists
	//known bug: if name of current format changed, we will not find correct one
	self.encodeFormat = [tiVoManager findFormat:self.encodeFormat.name];
}

-(BOOL) isSubscribed:(MTTiVoShow *) tivoShow ignoreDate:(BOOL)ignoreDate {
	//check for protected shows
	if ( tivoShow.protectedShow.boolValue) {
		return NO;
	}
	
	//check for TiVo suggestions
	if ( tivoShow.isSuggestion && ! self.includeSuggestions.boolValue  ) {
		return NO;
	}
	
	//Series name has to match
	if ([self.subscriptionRegex numberOfMatchesInString:tivoShow.seriesTitle
												 options:0
												   range:NSMakeRange(0,tivoShow.seriesTitle.length)] == 0){
		return NO;
	}
	if (!ignoreDate) {
		//kept for transition from iTivo && cTivo2.0; also for brand new subscriptions
		BOOL afterLast = (tivoShow.showDate != nil) && [self.createdTime isLessThan: tivoShow.showDate];
		DDLogVerbose(@"%@ for %@, date:%@ prev:%@", afterLast ? @"YES": @"NO",tivoShow.showTitle, tivoShow.showDate, self.createdTime);
		if (!afterLast) {
			return NO;
		}
	}
	
	//Now check that we're on the right Tivo, if specified
	if ((self.preferredTiVo.length != 0) && (![self.preferredTiVo isEqualToString: tivoShow.tiVoName]))  {
		return NO;
	}
	//Now check that we're in HD if specified
	if (self.HDOnly.boolValue && ! tivoShow.isHD.boolValue) {
		return NO;
	}
	
	//Now check that we're in SD if specified
	if (self.SDOnly.boolValue && tivoShow.isHD.boolValue) {
		return NO;
	}
	
	//Check if we've already recorded it
	for (NSDictionary * prevShow in self.prevRecorded ) {
		DDLogVerbose(@"check Recorded: %@ v. %@",prevShow[@"episodeID"], tivoShow.episodeID);  //QQQ debug only; pullout
		if ([prevShow[@"episodeID"] isEqualToString: tivoShow.episodeID]) {
			DDLogVerbose(@"Already recorded: %@ ",prevShow);
			return NO;
		}
	}
	return YES;
	
}


-(MTDownload *) downloadForShow: (MTTiVoShow *) thisShow {
	DDLogDetail(@"Subscribed; adding %@", thisShow);
	MTDownload * newDownload = [[MTDownload  alloc] init];
	newDownload.show= thisShow;
	newDownload.encodeFormat = self.encodeFormat;
	newDownload.addToiTunesWhenEncoded = ([self canAddToiTunes] && [self shouldAddToiTunes]);
	//			newDownload.simultaneousEncode = ([subscription canSimulEncode] && [subscription shouldSimulEncode]);
	newDownload.downloadDirectory = [tiVoManager downloadDirectory];  //should we have one per subscription? UI?
	
	newDownload.exportSubtitles = self.exportSubtitles;
	newDownload.skipCommercials = self.shouldSkipCommercials && self.canSkipCommercials;
	newDownload.markCommercials = self.shouldMarkCommercials && self.canMarkCommercials ;
	newDownload.genTextMetaData = self.genTextMetaData;
#ifndef deleteXML
	newDownload.genXMLMetaData = self.genXMLMetaData;
	newDownload.includeAPMMetaData =[NSNumber numberWithBool:(newDownload.encodeFormat.canAcceptMetaData && self.includeAPMMetaData.boolValue)];
#endif
	NSDictionary *thisRecording = @{
		 @"showTitle": thisShow.showTitle ,
		 @"episodeID": thisShow.episodeID,
		 @"startTime": thisShow.showDate,
		 @"tiVoName":  thisShow.tiVoName
	};
	NSUInteger index = 0;
	//keep sorted by startTime
	for (NSDictionary * prevRecording in self.prevRecorded) {
		if ([prevRecording[@"startTime"] isGreaterThan: thisShow.showDate]) {
			index++;
		}
	}
	DDLogVerbose(@"remembering Recording %ld: %@", index, thisRecording);
	[self.prevRecorded insertObject:thisRecording atIndex:index];
	return newDownload;
}

-(NSString *) description {
	return [NSString stringWithFormat:@"Subscription:%@ lastAt:%@ format:%@", self.displayTitle, self.displayDate, self.encodeFormat];
}

-(NSDate *) displayDate {
	NSDate * tempDate = [self.createdTime dateByAddingTimeInterval:1]; //display one second later to avoid second we stole above.
	if (self.prevRecorded.count > 0) {
		NSDate *lastRecord = self.prevRecorded[0][@"startTime"];
		if ([lastRecord isGreaterThan:tempDate]) {
			tempDate = lastRecord;
		}
	}
	return tempDate;
}
	
- (void)dealloc {
     _encodeFormat = nil;
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}
@end


@implementation NSMutableArray (MTSubscriptionList)


#pragma mark - Subscription Management

-(void) initialLastLoadedTimes { //called when TivoList changes
	for (MTTiVo * tivo in tiVoManager.tiVoList) {  //ensure all are in the dictionary
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
	NSDate * returnDate = [NSDate dateWithTimeIntervalSinceNow:-60*60*24*7]; //keep at least 7 days
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


-(void) checkSubscription: (NSNotification *) notification {
	//called by system when a new show appears in listing, including all shows at startup
	MTTiVoShow * thisShow = (MTTiVoShow *) notification.object;
	NSDate * earliestTime = [tiVoManager. lastLoadedTivoTimes[thisShow.tiVoName] dateByAddingTimeInterval:-60*60*12];
	//any show that started within twelve hours of last checkin is worth looking at.
	//note that theoretically, 12 hours could be replace by thisshow.duration if we parsed Tivos'  PT00H0M0S format;
	if ([thisShow.showDate isGreaterThan: earliestTime]) {
		DDLogVerbose(@"Subscription check: recent enough %@", thisShow);
		for (MTSubscription * possMatch in self) {
			if ([possMatch isSubscribed:thisShow ignoreDate:NO]) {
				MTDownload * newDownload = [possMatch downloadForShow:thisShow];
				[tiVoManager addToDownloadQueue:@[newDownload] beforeDownload:nil];    
			}
		}
	} else {
		DDLogVerbose(@"Subscription check: too old: %@", thisShow);
	}
}

-(void) checkSubscriptionsNew:(NSArray *) newSubs {
	//Called after one or more subscriptions have been created or when reapplying. Ignores tivoLoadTimes to incorporate all current shows
	DDLogVerbose(@"checking New Subscriptions");
	for (MTTiVoShow * thisShow in tiVoManager.tiVoShows.reverseObjectEnumerator) {
		for (MTSubscription * possMatch in newSubs) {
			if ([possMatch isSubscribed:thisShow ignoreDate:YES]) {
				MTDownload * newDownload = [possMatch downloadForShow:thisShow];
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
	NSString * seriesSearchString = show.seriesTitle;
	if (!seriesSearchString) return nil;
	BOOL isNotSuggestion = ! show.isSuggestion;
    for (MTSubscription * possMatch in self) {
        if (isNotSuggestion || possMatch.includeSuggestions.boolValue  ) {
			if ([possMatch.subscriptionRegex
				     numberOfMatchesInString:seriesSearchString
				     options:0
					 range:NSMakeRange(0,seriesSearchString.length)
				 ] > 0) {
				DDLogVerbose(@"found show %@ in subscription %@", show, possMatch);
				return possMatch;
			}
        }
    }
    return nil;
}


-(NSArray *) addSubscriptions: (NSArray *) shows {
	
	NSMutableArray * newSubs = [NSMutableArray arrayWithCapacity:shows.count];
    DDLogDetail(@"Subscribing to shows %@", shows);
	for (MTTiVoShow * thisShow in shows) {
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
		MTSubscription * newSub = [self subscribeDownload:download];
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

-(MTSubscription *) addSubscriptionsString: (NSString *) pattern {
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
		//for manual titles, we allow regex matching without being the entire series
		newSub.subscriptionRegex = tempRegex;				
		[self checkSubscriptionsNew:@[newSub]];
		[[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationSubscriptionsUpdated object:nil];
		return newSub;
	} else {
		return nil;
	}
}

-(NSRegularExpression *) matchFull:(NSString *) showName {
	NSString * pattern = [NSString stringWithFormat:@"^%@$", [NSRegularExpression escapedPatternForString:showName]];
	NSError * error = nil;
	NSRegularExpression * tempRegex = [NSRegularExpression regularExpressionWithPattern:pattern options:NSRegularExpressionCaseInsensitive error:&error];
	if (error) return nil;
	return tempRegex;
}

-(MTSubscription *) createSubscription: (MTTiVoShow *) tivoShow {
	//set the "lastrecording" time for one second before this show, to include this show.
	DDLogVerbose(@"creating Subscription based on Show %@", tivoShow);
	NSDate *earlierTime = [NSDate dateWithTimeIntervalSinceReferenceDate: 0];
	if (tivoShow.showDate) {
		earlierTime = [tivoShow.showDate  dateByAddingTimeInterval:-1];
	}
	DDLogVerbose(@"Subscription time of %@",earlierTime);
	NSRegularExpression * tempRegex = [self matchFull:tivoShow.seriesTitle];
	
	if (!tempRegex) return nil;
	MTSubscription *newSub = [MTSubscription new];
	newSub.displayTitle = tivoShow.seriesTitle;
	newSub.subscriptionRegex = tempRegex;
	newSub.createdTime = earlierTime;
	newSub.includeSuggestions = [[NSUserDefaults standardUserDefaults] objectForKey:kMTShowSuggestions];
	newSub.preferredTiVo= @"";
	newSub.HDOnly= @NO;
	newSub.SDOnly= @NO;
	[self addObject:newSub];
	return newSub;
}

-(MTSubscription *) subscribeShow:(MTTiVoShow *) tivoShow {
	if ([self findShow:tivoShow] == nil) {      //future: || [[NSUserDefaults standardUserDefaults] boolForKey:kMTAllowDups] || 
		MTSubscription * newSub = [self createSubscription:tivoShow];
		//use default properties
		NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
		newSub.encodeFormat = tiVoManager.selectedFormat;
		newSub.addToiTunes = [NSNumber numberWithBool:([defaults boolForKey:kMTiTunesSubmit] && newSub.encodeFormat.canAddToiTunes)];
//		newSub.simultaneousEncode = [NSNumber numberWithBool:([defaults boolForKey:kMTSimultaneousEncode] && newSub.encodeFormat.canSimulEncode)];
		newSub.skipCommercials = [NSNumber numberWithBool:([defaults boolForKey:@"RunComSkip"] && newSub.encodeFormat.comSkip.boolValue)];
		newSub.markCommercials = [NSNumber numberWithBool:([defaults boolForKey:@"MarkCommercials"] && newSub.encodeFormat.canMarkCommercials)];
		newSub.genTextMetaData	  = [defaults objectForKey:kMTExportTextMetaData];
#ifndef deleteXML
		newSub.genXMLMetaData	  =	[defaults objectForKey:kMTExportTivoMetaData];
		newSub.includeAPMMetaData = [defaults objectForKey:kMTExportMetaData];
#endif
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
	if ([self findShow:tivoShow] == nil) {//future: || [[NSUserDefaults standardUserDefaults] boolForKey:kMTAllowDups] ||
		MTSubscription * newSub = [self createSubscription:download.show];
		// use queued properties
		newSub.encodeFormat = download.encodeFormat;
		newSub.addToiTunes = [NSNumber numberWithBool: download.addToiTunesWhenEncoded ];
//		newSub.simultaneousEncode = [NSNumber numberWithBool: download.simultaneousEncode];
		newSub.skipCommercials = [NSNumber numberWithBool: download.skipCommercials];
		newSub.markCommercials = [NSNumber numberWithBool: download.markCommercials];
		newSub.genTextMetaData = [NSNumber numberWithBool: download.genTextMetaData];
#ifndef deleteXML
		newSub.genXMLMetaData = [NSNumber numberWithBool: download.genXMLMetaData];
		newSub.includeAPMMetaData = [NSNumber numberWithBool: download.includeAPMMetaData];
#endif
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
	[[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationSubscriptionsUpdated object:nil];
}

-(void) loadSubscriptions {
    NSArray * tempArray = [[NSUserDefaults standardUserDefaults] objectForKey:kMTSubscriptionList];
    [self removeAllObjects];
    
	DDLogDetail(@"Loading subscriptions");
    for (NSDictionary * sub in tempArray) {
        MTSubscription * tempSub = [[MTSubscription alloc] init];
		tempSub.displayTitle = sub[kMTSubscribedSeries];
		NSString * regexPattern = sub[kMTSubscribedRegExPattern];
		if(regexPattern) {
			tempSub.subscriptionRegex = [NSRegularExpression regularExpressionWithPattern:regexPattern options:NSRegularExpressionCaseInsensitive error:nil];
		} else {
			tempSub.subscriptionRegex = [self matchFull:sub[kMTSubscribedSeries]];			
		}

       tempSub.createdTime = sub[kMTCreatedDate];
        
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
#ifndef deleteXML
		tempSub.genXMLMetaData = sub[kMTSubscribedGenXMLMetaData];
		if (tempSub.genXMLMetaData ==nil) tempSub.genXMLMetaData = [[NSUserDefaults standardUserDefaults] objectForKey:kMTExportTivoMetaData];
		tempSub.includeAPMMetaData = sub[kMTSubscribedIncludeAPMMetaData];
		if (tempSub.includeAPMMetaData ==nil) tempSub.includeAPMMetaData = [[NSUserDefaults standardUserDefaults] objectForKey:kMTExportMetaData];
#endif
		tempSub.exportSubtitles = sub[kMTSubscribedExportSubtitles];
		if (tempSub.exportSubtitles ==nil) tempSub.exportSubtitles = [[NSUserDefaults standardUserDefaults] objectForKey:kMTExportSubtitles];
		tempSub.preferredTiVo = sub[kMTSubscribedPreferredTiVo];
		if (!tempSub.preferredTiVo) tempSub.preferredTiVo = @"";
		tempSub.HDOnly = sub[kMTSubscribedHDOnly];
		if (!tempSub.HDOnly) tempSub.HDOnly = @NO;
		tempSub.SDOnly = sub[kMTSubscribedSDOnly ];
		if (!tempSub.SDOnly) tempSub.SDOnly = @NO;
		if (sub[	kMTSubscribedPrevRecorded]) {
			tempSub.prevRecorded = [sub[	kMTSubscribedPrevRecorded] mutableCopy];
		}		DDLogVerbose(@"Loaded Sub: %@ from %@",tempSub, sub);
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
        NSDictionary * tempSub = [NSDictionary dictionaryWithObjectsAndKeys:
                                  sub.displayTitle, kMTSubscribedSeries,
								  pattern, kMTSubscribedRegExPattern,
                                  sub.encodeFormat.name, kMTSubscribedFormat,
                                  sub.createdTime, kMTCreatedDate,
                                  sub.addToiTunes, kMTSubscribediTunes,
                                  sub.includeSuggestions, kMTSubscribedIncludeSuggestions,
								  sub.skipCommercials, kMTSubscribedSkipCommercials,
								  sub.markCommercials, kMTSubscribedMarkCommercials,
                                  sub.genTextMetaData , kMTSubscribedGenTextMetaData,
#ifndef deleteXML
                                  sub.genXMLMetaData, kMTSubscribedGenXMLMetaData,
                                  sub.includeAPMMetaData, kMTSubscribedIncludeAPMMetaData,
#endif
                                  sub.exportSubtitles, kMTSubscribedExportSubtitles,
								  sub.preferredTiVo, kMTSubscribedPreferredTiVo,
								  sub.HDOnly,kMTSubscribedHDOnly,
								  sub.SDOnly,kMTSubscribedSDOnly,
								  sub.prevRecorded,
								      kMTSubscribedPrevRecorded,
								  nil];
		DDLogVerbose(@"Saving Sub: %@ ",tempSub);
		[tempArray addObject:tempSub];
    }
	[[NSUserDefaults standardUserDefaults] setObject:tiVoManager.lastLoadedTivoTimes forKey:kMTTiVoLastLoadTimes];
	[[NSUserDefaults standardUserDefaults] setObject:tempArray forKey:kMTSubscriptionList];
	//May not be necessary   [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationSubscriptionsUpdated object:nil];
}

- (void)dealloc
{
    
}

@end
