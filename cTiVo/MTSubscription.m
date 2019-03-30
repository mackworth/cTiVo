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

-(BOOL) canSkipCommercials {
    return self.encodeFormat.comSkip.boolValue;
}

-(BOOL) canMarkCommercials {
	NSArray * allowedExtensions = @[@".mp4", @".m4v"];
	NSString * extension = [self.encodeFormat.filenameExtension lowercaseString];
	return [allowedExtensions containsObject: extension];
}

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

-(BOOL) canSkipModeCommercials {
	return (self.canMarkCommercials || self.canSkipCommercials);
}

-(void) setEncodeFormat:(MTFormat *) encodeFormat {
    if (_encodeFormat != encodeFormat ) {
        BOOL iTunesWasDisabled = ![self canAddToiTunes];
        BOOL skipWasDisabled = ![self canSkipCommercials];
        BOOL markWasDisabled = ![self canMarkCommercials];
		BOOL skipModeWasDisabled = ![self canSkipModeCommercials];
       _encodeFormat = encodeFormat;

		NSUserDefaults * defaults = [NSUserDefaults standardUserDefaults];
		if ([self canAddToiTunes]) { //if newly possible, take user default
			if (iTunesWasDisabled) self.addToiTunes = @([defaults boolForKey:kMTiTunesSubmit] );
		} else { //no longer possible
            self.addToiTunes = @NO;
        }
		if ([self canSkipCommercials]) {
			if (skipWasDisabled) self.skipCommercials = @([defaults boolForKey:kMTSkipCommercials]);
		} else { //no longer possible
            self.skipCommercials = @NO;
        }
		if ([self canMarkCommercials]) {
			if (markWasDisabled) self.markCommercials = @([defaults boolForKey:kMTMarkCommercials]);
		} else { //no longer possible
			self.markCommercials = @NO;
		}
		if ([self canSkipModeCommercials]) {
			if (skipModeWasDisabled) self.useSkipMode = @([defaults integerForKey:kMTCommercialStrategy] > 0);
		} else { //no longer possible
			self.useSkipMode = @NO;
		}
    }
}

-(void) setSkipCommercials:(NSNumber *)skipCommercials {
	_skipCommercials = skipCommercials;
	if (_skipCommercials.boolValue && _markCommercials.boolValue) {
		self.markCommercials = @NO;
	}
}

-(void) setMarkCommercials:(NSNumber *)markCommercials {
	_markCommercials = markCommercials;
	if (_skipCommercials.boolValue && _markCommercials.boolValue) {
		self.skipCommercials = @NO;
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
	//check that we're on right station if specified
	if (self.stationCallSign.length > 0 && ![self.stationCallSign isEqualToString:tivoShow.stationCallsign]) {
		return NO;	
	}
	
	//Check if we've already recorded it
	NSString * thisShowID = tivoShow.uniqueID;
	for (NSDictionary * prevShow in self.prevRecorded ) {
		if ([prevShow[@"episodeID"] isEqualToString: thisShowID]) {
			DDLogVerbose(@"Already recorded: %@ ",prevShow);
			return NO;
		}
	}
	return YES;
}

-(MTDownload *) downloadForSubscribedShow: (MTTiVoShow *) thisShow {
	DDLogDetail(@"Subscribed; adding %@", thisShow);
    MTDownload * newDownload = [MTDownload downloadForShow:thisShow withFormat:self.encodeFormat  withQueueStatus: kMTStatusNew];

    //should we have a directory per subscription? UI?
	newDownload.addToiTunesWhenEncoded = ([self canAddToiTunes] && [self shouldAddToiTunes]);
	newDownload.exportSubtitles = self.exportSubtitles;
	newDownload.deleteAfterDownload = self.deleteAfterDownload;
	newDownload.skipCommercials = self.shouldSkipCommercials && self.canSkipCommercials;
	newDownload.useSkipMode =     self.useSkipMode.boolValue;
	newDownload.markCommercials = self.shouldMarkCommercials && self.canMarkCommercials ;
	newDownload.genTextMetaData = self.genTextMetaData;
    DDLogDetail(@"Adding %@: ID: %@, Sub: %@, date: %@, Tivo: %@", thisShow, thisShow.episodeID, thisShow.uniqueID, thisShow.showDate, thisShow.tiVoName );

    if ( thisShow.showTitle &&  thisShow.uniqueID && thisShow.showDate && thisShow.tiVoName ) { //protective only; should always be non-nil
            NSDictionary *thisRecording = @{
             @"showTitle": thisShow.showTitle ,
             @"episodeID": thisShow.uniqueID,
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
        if (index ==0) { //later than previous latest, so update table
            [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationSubscriptionChanged object:self];
        }
    }
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

#pragma mark - create Subscriptions

#define kMTSubSeries 0
#define kMTSubRegExPattern 1
#define kMTSubFormat 2
#define kMTSubDate 3
#define kMTSubTiVo 4
#define kMTSubChannel 5
#define kMTSubMin 6

#define kMTSubStringsArray  @[@"iTunes", @"skipAds", @"markAds",  @"suggestions",  @"pyTiVo",  @"subtitles",  @"HDOnly",  @"SDOnly", @"SkipMode", @"Delete"]
#define kMTSubiTunes 0
#define kMTSubSkipAds 1
#define kMTSubMarkAds 2
#define kMTSubSuggestions 3
#define kMTSubPyTiVo 4
#define kMTSubCaptions 5
#define kMTSubHD 6
#define kMTSubSD 7
#define kMTSubSkipMode 8
#define kMTSubDelete 9

+(instancetype) subscriptionFromString:(NSString *) str {
    //imports a subscription from an imported string
    //syntax is the following (separated by tabs)
    // displayTitle SubscriptionRegex Format createdTime PreferredTiVo keywords*
    //createdTime can be blank (or not legible) ==> current time
    //preferred Tivo can be blank ==> any Tivo
    //keywords are case insensitive, in any order; default is off; include to turn on
    NSArray * strArray = [str componentsSeparatedByString:@"\t"];
    if (strArray.count < kMTSubMin ) {
        DDLogReport(@"Importing Subscription: Not enough fields in %@",str);
        return nil;  //improperly formatted subscription text
    }
     //future: || [[NSUserDefaults standardUserDefaults] boolForKey:kMTAllowDups] ||
        MTSubscription *newSub = [MTSubscription new];

        //required fields:
        newSub.displayTitle = strArray[kMTSubSeries];
        newSub.subscriptionRegex = [NSRegularExpression regularExpressionWithPattern:strArray[kMTSubRegExPattern]options:NSRegularExpressionCaseInsensitive error:nil];
        if (!newSub.subscriptionRegex) {
            DDLogReport(@"Importing subscription %@; faulty regex %@",str,strArray[kMTSubRegExPattern]);
            return nil;
        }
        newSub.encodeFormat = [tiVoManager findFormat:strArray[kMTSubFormat] ];
        newSub.createdTime = [NSDate dateWithString:strArray[kMTSubDate]];
        if (!newSub.createdTime) newSub.createdTime = [NSDate date];
        newSub.preferredTiVo= strArray[kMTSubTiVo];
		newSub.stationCallSign = strArray[kMTSubChannel];

        newSub.addToiTunes = @NO;
        newSub.skipCommercials = @NO;
		newSub.markCommercials = @NO;
		newSub.useSkipMode = @NO;
        newSub.includeSuggestions = @NO;
        newSub.genTextMetaData = @NO;
        newSub.exportSubtitles=  @NO;
		newSub.deleteAfterDownload=  @NO;
        newSub.HDOnly= @NO;
        newSub.SDOnly= @NO;

        for (NSUInteger i = kMTSubMin; i < strArray.count; i++ ) {
            NSString * keyWord = ((NSString *)strArray[i]).lowercaseString;
            if (keyWord.length == 0 ) continue;
            NSInteger whichKeyword =  [kMTSubStringsArray indexOfObjectPassingTest:^BOOL(id obj, NSUInteger idx, BOOL *stop) {
                NSString * s = (NSString *) obj;
                return[keyWord isEqualToString:s.lowercaseString];
            }];
            switch (whichKeyword) {
                case kMTSubiTunes:      newSub.addToiTunes = @YES;          break;
                case kMTSubSkipAds:     newSub.skipCommercials = @YES;      break;
                case kMTSubMarkAds:     newSub.markCommercials = @YES;      break;
                case kMTSubSuggestions: newSub.includeSuggestions = @YES;   break;
                case kMTSubPyTiVo:      newSub.genTextMetaData = @YES;      break;
                case kMTSubCaptions:    newSub.exportSubtitles=  @YES;      break;
				case kMTSubDelete:      newSub.deleteAfterDownload =  @YES; break;
                case kMTSubHD:          newSub.HDOnly= @YES;                break;
				case kMTSubSD:          newSub.SDOnly= @YES;                break;
				case kMTSubSkipMode:    newSub.useSkipMode= @YES;           break;
                default:  break;

            }
        }
        DDLogVerbose(@"Subscribing string %@ as: %@ ", str, newSub);
        return newSub;
//    } else {
//        return nil;
//    }
}

+(NSRegularExpression *) matchFull:(NSString *) showName {
    NSString * pattern = [NSString stringWithFormat:@"^%@$", [NSRegularExpression escapedPatternForString:showName]];
    NSError * error = nil;
    NSRegularExpression * tempRegex = [NSRegularExpression regularExpressionWithPattern:pattern options:NSRegularExpressionCaseInsensitive error:&error];
    if (error) return nil;
    return tempRegex;
}

+ (instancetype) subscriptionFromDictionary: (NSDictionary *) sub {
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

    tempSub.includeSuggestions = sub[kMTSubscribedIncludeSuggestions];
    if (tempSub.includeSuggestions ==nil) tempSub.includeSuggestions = [[NSUserDefaults standardUserDefaults] objectForKey:kMTShowSuggestions];
    tempSub.skipCommercials = sub[kMTSubscribedSkipCommercials];
    if (tempSub.skipCommercials ==nil) tempSub.skipCommercials = [[NSUserDefaults standardUserDefaults] objectForKey:kMTSkipCommercials];
	tempSub.useSkipMode = sub[kMTSubscribedUseSkipMode] ?:  @([[NSUserDefaults standardUserDefaults] integerForKey:kMTCommercialStrategy] > 0);

    tempSub.markCommercials = sub[kMTSubscribedMarkCommercials];
    if (tempSub.markCommercials ==nil) tempSub.markCommercials = [[NSUserDefaults standardUserDefaults] objectForKey:kMTMarkCommercials];
    tempSub.genTextMetaData = sub[kMTSubscribedGenTextMetaData];
    if (tempSub.genTextMetaData ==nil) tempSub.genTextMetaData = [[NSUserDefaults standardUserDefaults] objectForKey:kMTExportTextMetaData];
    tempSub.exportSubtitles = sub[kMTSubscribedExportSubtitles];
    if (tempSub.exportSubtitles ==nil) tempSub.exportSubtitles = [[NSUserDefaults standardUserDefaults] objectForKey:kMTExportSubtitles];
	tempSub.deleteAfterDownload = sub[kMTSubscribedDeleteAfterDownload];
	if (tempSub.deleteAfterDownload == nil) tempSub.deleteAfterDownload = @NO;
    tempSub.preferredTiVo = sub[kMTSubscribedPreferredTiVo];
    if (!tempSub.preferredTiVo || ([tempSub.preferredTiVo isEqualToString:@"Any TiVo"]) ){
        tempSub.preferredTiVo = @"";
    }
	tempSub.stationCallSign = sub[kMTSubscribedCallSign];
	if ([tempSub.stationCallSign isEqualToString:@""] || ([tempSub.stationCallSign isEqualToString:@"Any"]) ){
		tempSub.stationCallSign = nil;
	}
    tempSub.HDOnly = sub[kMTSubscribedHDOnly];
    if (!tempSub.HDOnly) tempSub.HDOnly = @NO;
    tempSub.SDOnly = sub[kMTSubscribedSDOnly ];
    if (!tempSub.SDOnly) tempSub.SDOnly = @NO;
    if (sub[	kMTSubscribedPrevRecorded]) {
        tempSub.prevRecorded = [sub[	kMTSubscribedPrevRecorded] mutableCopy];
    }
    DDLogVerbose(@"Loaded Sub: %@ from %@",tempSub, sub);
    return tempSub;
}

+(MTSubscription *) subscriptionFromShow: (MTTiVoShow *) tivoShow {
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
	newSub.stationCallSign= @"";
    newSub.HDOnly= @NO;
    newSub.SDOnly= @NO;
	newSub.useSkipMode = @([[NSUserDefaults standardUserDefaults] integerForKey:kMTCommercialStrategy] > 0);
    return newSub;
}

-(NSString *) subscribeString  {
    NSMutableArray * outString = [NSMutableArray arrayWithCapacity:15];

    outString[kMTSubSeries] = self.displayTitle;
    outString[kMTSubRegExPattern] = self.subscriptionRegex.pattern;
    outString[kMTSubFormat] = self.encodeFormat.name;
    outString[kMTSubDate] = [self.displayDate descriptionWithLocale:nil ];
	outString[kMTSubTiVo] = self.preferredTiVo;
	outString[kMTSubChannel] = self.stationCallSign ?: @"";

    if (self.addToiTunes.boolValue )        [outString addObject: kMTSubStringsArray [kMTSubiTunes]];
    if (self.skipCommercials.boolValue )    [outString addObject: kMTSubStringsArray [kMTSubSkipAds]];
	if (self.markCommercials.boolValue )    [outString addObject: kMTSubStringsArray [kMTSubMarkAds]];
	if (self.useSkipMode.boolValue )        [outString addObject: kMTSubStringsArray [kMTSubSkipMode]];
    if (self.includeSuggestions.boolValue ) [outString addObject: kMTSubStringsArray [kMTSubSuggestions]];
    if (self.genTextMetaData.boolValue )    [outString addObject: kMTSubStringsArray [kMTSubPyTiVo]];
	if (self.exportSubtitles.boolValue )    [outString addObject: kMTSubStringsArray [kMTSubCaptions]];
	if (self.exportSubtitles.boolValue )    [outString addObject: kMTSubStringsArray [kMTSubDelete]];
    if (self.HDOnly.boolValue )             [outString addObject: kMTSubStringsArray [kMTSubHD]];
    if (self.SDOnly.boolValue )             [outString addObject: kMTSubStringsArray [kMTSubSD]];
    return [outString componentsJoinedByString:@"\t"];
}

#pragma mark - Pasteboard routines

- (id)pasteboardPropertyListForType:(NSString *)type {
    if ( [type isEqualToString:NSPasteboardTypeString]) {
        return [self subscribeString] ;
    } else {
        return nil;
    }
}
-(NSArray *)writableTypesForPasteboard:(NSPasteboard *)pasteboard {
    NSArray* result = [NSArray  arrayWithObjects: NSPasteboardTypeString, nil];
    return result;
}

- (NSPasteboardWritingOptions)writingOptionsForType:(NSString *)type pasteboard:(NSPasteboard *)pasteboard {
    return 0;
}

+ (NSArray *)readableTypesForPasteboard:(NSPasteboard *)pasteboard {
    return @[kMTDownloadPasteBoardType, NSPasteboardTypeString];

}

+ (NSPasteboardReadingOptions)readingOptionsForType:(NSString *)type pasteboard:(NSPasteboard *)pasteboard {
    if ([type compare:kMTDownloadPasteBoardType] ==NSOrderedSame)
        return NSPasteboardReadingAsKeyedArchive;
    return 0;
}

- (void)dealloc {
     _encodeFormat = nil;
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}
@end


