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
#define kMTNotificationSubscriptionsUpdated @"MTNotificationSubscriptionsUpdated"

//Download Progress Notifications
#define kMTNotificationDownloadDidFinish @"MTNotificationDownloadDidFinish"
#define kMTNotificationDecryptDidFinish @"MTNotificationDecryptDidFinish"
#define kMTNotificationEncodeDidFinish @"MTNotificationEncodeDidFinish"
#define kMTNotificationEncodeWasCanceled @"MTNotificationEncodeWasCanceled"
#define kMTNotificationCommercialDidFinish @"MTNotificationCommercialDidFinish"
#define kMTNotificationCommercialWasCanceled @"MTNotificationCommercialWasCanceled"
#define kMTNotificationDownloadStatusChanged @"MTNotificationDownloadStatusChanged"

//UI Change Notifications

#define kMTNotificationTiVoListUpdated @"MTNotificationTiVoListUpdated"
#define kMTNotificationFormatListUpdated @"MTNotificationFormatListUpdated"
#define kMTNotificationProgressUpdated @"MTNotificationProgressUpdated"
#define kMTNotificationNetworkChanged @"MTNotificationNetworkChanged"
#define kMTNotificationDetailsLoaded @"MTNotificationDetailsLoaded"
//#define kMTNotificationReloadEpisode @"MTNotificationReloadEpisode"
#define kMTNotificationMediaKeyNeeded @"MTNotificationMediaKeyNeeded"
#define kMTNotificationFormatChanged @"MTNotificationFormatChanged"

//Tivo busy indicator
#define kMTNotificationShowListUpdating @"MTNotificationShowListUpdating"
#define kMTNotificationShowListUpdated @"MTNotificationShowListUpdated"

//Download Status
#define kMTStatusNew 0
#define kMTStatusDownloading 1
#define kMTStatusDownloaded 2
#define kMTStatusDecrypting 3
#define kMTStatusDecrypted 4
#define kMTStatusCommercialing 5
#define kMTStatusCommercialed 6
#define kMTStatusEncoding 7
#define kMTStatusDone 8
#define kMTStatusDeleted 13
#define kMTStatusFailed 15
//note that all "Done" status must be bigger than kMTStatusDone

//Contants

#define kMTMaxNumDownloaders 2		//Limit number of encoders to limit cpu usage
#define kMTUpdateIntervalMinutes 15 //Update interval for re-checking current TiVo
#define kMTMaxDownloadRetries 3		// Only allow 3 retries to download a show
#define kMTMaxDownloadStartupRetries 20		// Only allow 20 retries due to a download startup failuer
#define kMTProgressCheckDelay 60	//Check progress every 60 seconds to make sure its not stalled
//#define kMTRetryNetworkInterval 15	//Re-Check for network connectivity every X seconds
#define kMTTiVoAccessDelay 7		//Seconds to wait after TiVo is found on network

//Subscribed Show userDefaults
#define kMTSubscribedSeries @"MTSubscribedSeries"
#define kMTSubscribedDate	@"MTSubscribedSeriesDate"
#define kMTSubscribedFormat @"MTSubscribedSeriesFormat"
#define kMTSubscribediTunes @"addToiTunes"
#define kMTSubscribedSimulEncode @"simultaneousEncode"
#define kMTSubscribedSkipCommercials @"skipCommercials"

//Download queue userDefaults
#define kMTQueue      @"Queue"
#define kMTQueueID    @"QueueID"
#define kMTQueueTitle @"QueueTitle"
#define kMTQueueTivo  @"QueueTivo"
#define kMTQueueFormat  @"QueueFormat"
#define kMTQueueStatus  @"QueueStatus"
#define kMTQueueShowStatus @"QueueShowStatus"
#define kMTQueueDirectory @"QueueDirectory"
#define kMTQueueDownloadFile @"QueueDownloadFile"
#define kMTQueueBufferFile @"QueueBufferFile"
#define kMTQueueFinalFile @"QueueFileName"

//Column editing userDefaults
#define kMTProgramTableColumns @"ProgramTableColumns"
#define kMTDownloadTableColumns @"DownloadTableColumns"
#define kMTSubscriptionTableColumns @"kMTSubscriptionTableColumns"
#define kMTHideTiVoColumnPrograms @"HideTiVoColumnPrograms"
#define kMTHideTiVoColumnDownloads @"HideTiVoColumnDownloads"

//Misc

#define kMTFirstName @"MTFirstName"
#define kMTLastName @"MTLastName"
#define kMTAllTiVos @"All TiVos"
#define kMTDefaultDownloadDir  @"Movies/TiVoShows/"

#define kMTTivoShowPasteBoardType @"com.cTiVo.TivoShow"


//USER DEFAULTS

#define	kMTQueuePaused @"QueuePaused"			//State of pause for the download queue
#define kMTManualTiVos @"ManualTiVos"           //Array of manually defined tiVo address.  
#define kMTPreventSleep @"PreventSleep"			//If true this will prevent sleep when possible
#define kMTQuitWhileProcessing @"QuitWhileProcessing" //Don't warn user when quitting if active job
#define kMTFormats @"Formats"                        //User defined Formats
#define kMTHiddenFormats @"HiddenFormats"        //User defined list of built-in formats to be hidden in the UI
#define kMTMediaKeys @"MediaKeys"                   //MAK dictionary, indexed by TiVo Name
#define kMTSelectedTiVo @"SelectedTiVo"             //Name of currently selected TiVo
#define kMTSelectedFormat @"SelectedFormat"         //Name of currently selected format for conversion
#define kMTDownloadDirectory  @"DownloadDirectory"  //Pathname for directory for dowloaded files
#define kMTSubscriptionList @"SubscriptionList"     //Array of subscription dictionaries
#define kMTiTunesSubmit @"iTunesSubmit"             //Whether to submit to iTunes after encoding
#define kMTiTunesSync @"iTunesSync"                 // Whether to sync iDevices after iTunes submital
#define kMTSimultaneousEncode @"SimultaneousEncode" //Whether to encode while downloading
#define kMTDisableDragSelect @"DisableDragSelect"   //Whether to disable drag-select in downloadshow list (vs drag/drop
#define kMTMakeSubDirs @"MakeSubDirs"               // Whether to make separate subdirectories for each series (in download dir)
#define kMTShowCopyProtected @"ShowCopyProtected"   // Whether to display uncopyable shows (greyed out)

//NOT IMPLEMENTED YET, but preferences imported from iTivo
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
#define kMTPostDownloadCommand @"PostDownloadCommand" // Example: "# mv \"$file\" ~/.Trash ;";

#define kMTDebugLevel       @"DebugLevel"
#define kMTDebugLevelDetail @"DebugLevelDetail"

//Growl notification constants (see growlRegDict file)
#define kMTGrowlBeginDownload @"Begin Download"
#define kMTGrowlEndDownload   @"End Download"
#define kMTGrowlCantDownload  @"Can't Download"

