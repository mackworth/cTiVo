//
//  MTConstants.h
//  myTivo
//
//  Created by Scott Buchanan on 12/6/12.
//  Copyright (c) 2012 Scott Buchanan. All rights reserved.
//

//Queue change notifications
#define kMTNotificationTiVoShowsUpdated @"MTNotificationTiVoShowsUpdated"
#define kMTNotificationDownloadQueueUpdated @"MTNotificationDownloadQueueUpdated"

//Download Progress Notifications
#define kMTNotificationDownloadDidFinish @"MTNotificationDownloadDidFinish"
#define kMTNotificationDecryptDidFinish @"MTNotificationDecryptDidFinish"
#define kMTNotificationEncodeDidFinish @"MTNotificationEncodeDidFinish"

//UI Change Notifications
#define kMTNotificationTiVoChanged @"MTNotificationTiVoChanged"
#define kMTNotificationTiVoListUpdated @"MTNotificationTiVoListUpdated"
#define kMTNotificationDownloadListUpdated @"MTNotificationDownloadListUpdated"
#define kMTNotificationFormatListUpdated @"MTNotificationFormatListUpdated"
#define kMTNotificationProgressUpdated @"MTNotificationProgressUpdated"
#define kMTNotificationShowListUpdating @"MTNotificationShowListUpdating"
#define kMTNotificationShowListUpdated @"MTNotificationShowListUpdated"
#define kMTNotificationDetailsLoaded @"MTNotificationDetailsLoaded"

//Download Status
#define kMTStatusNew 0
#define kMTStatusDownloading 1
#define kMTStatusDownloaded 2
#define kMTStatusDecrypting 3
#define kMTStatusDecrypted 4
#define kMTStatusEncoding 5
#define kMTStatusDone 6

#define kMTMaxNumDownloaders 2

//Subscribed Show
#define kMTSubscribedSeries @"MTSubscribedSeries"
#define kMTSubscribedSeriesDate	@"MTSubscribedSeriesDate"

//Misc

#define kMTUpdateIntervalMinutes 15 //Update interval for re-checking current TiVo
#define kMTFirstName @"MTFirstName"
#define kMTLastName @"MTLastName"


//USER DEFAULTS

#define kMTMediaKeys @"MediaKeys"
#define kMTSelectedTiVo @"SelectedTiVo"
#define kMTSelectedFormat @"SelectedFormat"
#define kMTDownloadDirectory  @"DownloadDirectory"
#define kMTSubscriptionList @"SubscriptionList"
#define kMTiTunesEncode @"iTunesEncode"
#define kMTSimultaneousEncode @"SimultaneousEncode"

