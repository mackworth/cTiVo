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


-(MTDownload *) downloadForSubscribedShow: (MTTiVoShow *) thisShow {
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

#pragma mark - create Subscriptions

#define kMTSubSeries 0
#define kMTSubRegExPattern 1
#define kMTSubFormat 2
#define kMTSubDate 3
#define kMTSubTiVo 4
#define kMTSubMin 5

#define kMTSubStringsArray  @[@"iTunes", @"skipAds", @"markAds",  @"suggestions",  @"pyTiVo",  @"subtitles",  @"HDOnly",  @"SDOnly"]
#define kMTSubiTunes 0
#define kMTSubSkipAds 1
#define kMTSubMarkAds 2
#define kMTSubSuggestions 3
#define kMTSubPyTiVo 4
#define kMTSubCaptions 5
#define kMTSubHD 6
#define kMTSubSD 7

+(instancetype) subscriptionFromString:(NSString *) str {
    //set the "lastrecording" time for one second before this show, to include this show.
    NSArray * strArray = [str componentsSeparatedByString:@"\t"];
    if (strArray.count < kMTSubMin ) {
        DDLogReport(@"Importing Subscription: Not enough fields in %@",str);
        return nil;  //improperly formatted subscription text
    }

#warning need check in next line
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
        if (newSub.createdTime) newSub.createdTime = [NSDate date];
        newSub.preferredTiVo= strArray[kMTSubTiVo];

        newSub.addToiTunes = @NO;
        newSub.skipCommercials = @NO;
        newSub.markCommercials = @NO;
        newSub.includeSuggestions = @NO;
        newSub.genTextMetaData = @NO;
        newSub.exportSubtitles=  @NO;
        newSub.HDOnly= @NO;
        newSub.SDOnly= @NO;

        for (NSUInteger i = kMTSubMin; i < strArray.count; i++ ) {
            NSString * keyWord = ((NSString *)strArray[i]).lowercaseString;
            if (keyWord.length > 0 &&
                [kMTSubStringsArray indexOfObjectPassingTest:^BOOL(id obj, NSUInteger idx, BOOL *stop) {
                NSString * s = (NSString *) obj;
                return[keyWord isEqualToString:s.lowercaseString];
            }] != NSNotFound) {
                switch (i) {
                    case kMTSubiTunes:      newSub.addToiTunes = @YES;          break;
                    case kMTSubSkipAds:     newSub.skipCommercials = @YES;      break;
                    case kMTSubMarkAds:     newSub.markCommercials = @YES;      break;
                    case kMTSubSuggestions: newSub.includeSuggestions = @YES;   break;
                    case kMTSubPyTiVo:      newSub.genTextMetaData = @YES;      break;
                    case kMTSubCaptions:    newSub.exportSubtitles=  @YES;      break;
                    case kMTSubHD:          newSub.HDOnly= @YES;                break;
                    case kMTSubSD:          newSub.SDOnly= @YES;                break;
                    default:  break;
                }
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
    newSub.HDOnly= @NO;
    newSub.SDOnly= @NO;
    return newSub;
}

-(NSString *) subscribeString  {
    NSMutableArray * outString = [NSMutableArray arrayWithCapacity:12];

    outString[kMTSubSeries] = self.displayTitle;
    outString[kMTSubRegExPattern] = self.subscriptionRegex.pattern;
    outString[kMTSubFormat] = self.encodeFormat.name;
    outString[kMTSubDate] = [self.displayDate descriptionWithLocale:nil ];
    outString[kMTSubTiVo] = self.preferredTiVo;

    if (self.addToiTunes.boolValue )        [outString addObject: kMTSubStringsArray [kMTSubiTunes]];
    if (self.skipCommercials.boolValue )    [outString addObject: kMTSubStringsArray [kMTSubSkipAds]];
    if (self.markCommercials.boolValue )    [outString addObject: kMTSubStringsArray [kMTSubMarkAds]];
    if (self.includeSuggestions.boolValue ) [outString addObject: kMTSubStringsArray [kMTSubSuggestions]];
    if (self.genTextMetaData.boolValue )    [outString addObject: kMTSubStringsArray [kMTSubPyTiVo]];
    if (self.exportSubtitles.boolValue )    [outString addObject: kMTSubStringsArray [kMTSubCaptions]];
    if (self.HDOnly.boolValue )             [outString addObject: kMTSubStringsArray [kMTSubHD]];
    if (self.SDOnly.boolValue )             [outString addObject: kMTSubStringsArray [kMTSubSD]];
    return [outString componentsJoinedByString:@"\t"];
}

#pragma mark - Pasteboard routines

- (id)pasteboardPropertyListForType:(NSString *)type {
    //	NSLog(@"QQQ:pboard Type: %@",type);
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


