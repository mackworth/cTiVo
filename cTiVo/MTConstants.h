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
#define kMTNotificationDownloadStatusChanged @"MTNotificationDownloadStatusChanged"

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

#define kMTMediaKeys @"MediaKeys"                   //MAK dictionary, indexed by TiVo Name
#define kMTSelectedTiVo @"SelectedTiVo"             //Name of currently selected TiVo
#define kMTSelectedFormat @"SelectedFormat"         //Name of currently selected format for conversion
#define kMTDownloadDirectory  @"DownloadDirectory"  //Pathname for directory for dowloaded files
#define kMTSubscriptionList @"SubscriptionList"     //Array of subscription dictionaries
#define kMTiTunesEncode @"iTunesEncode"             //Whether to submit to iTunes after encoding
#define kMTSimultaneousEncode @"SimultaneousEncode" //Whether to encode while downloading

//NOT IMPLEMENTED YET, but preferences imported from iTivo
#define kMTMakeSubDirs @"MakeSubDirs"               // Whether to make separate subdirectories for each series (in download dir)
#define kMTShowCopyProtected @"ShowCopyProtected"   // Whether to display uncopyable shows (greyed out)
#define kMTNumDownloadRetries @"NumDownloadRetries" // How many retries due to download failures

#define kMTRunComSkip @"RunComSkip"                 // Whether to run comSkip program after conversion
#define kMTExportTivoMetaData @"ExportTivoMetaData" // Whether to export XML metadata
#define kMTExportSubtitles @"ExportSubtitles"       // Whether to export subtitles with ts2ami
#define kMTExportTextMetaData @"ExportTextMetaData" // Whether to export text metadata for PyTivo
#define kMTExportAtomicParsleyMetaData @"ExportAtomicParsleyMetaData" // Whether to export metadata with Atomic Parsley

#define kMTScheduledOperations @"ScheduledOperations"// Whether to run queue at a scheduled time;
#define kMTScheduledStartTime  @"ScheduledStartTime" // NSDate when to start queue
#define kMTScheduledEndTime    @"ScheduledEndTime"   // NSDate when to end queue
#define kMTScheduledSleep      @"ScheduledSleep"     // Whether to start queue to sleep after scheduled downloads

#define kMTiTunesIcon @"iTunesIcon"                 // Whether to use video frame (versus cTivo logo) for iTUnes icon
#define kMTiTunesSync @"iTunesSync"                 // Whether to sync iDevices after iTunes submital
#define kMTPostDownloadCommand @"PostDownloadCommand" // Example: "# mv \"$file\" ~/.Trash ;";

