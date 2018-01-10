//
//  MTAppDelegate.m
//  myTivo
//
//  Created by Scott Buchanan on 12/6/12.
//  Copyright (c) 2012 Scott Buchanan. All rights reserved.
//

#import "MTAppDelegate.h"
#import "MTProgramTableView.h"
#import "MTDownloadTableView.h"
#import "MTMainWindowController.h"
#import "MTSubscriptionTableView.h"
#import "MTPreferencesWindowController.h"
#import "MTHelpViewController.h"
#import "MTTiVo.h"
#import "MTSubscriptionList.h"
#import "PFMoveApplication.h"

#import "DDFileLogger.h"
#import "MTLogFormatter.h"
#ifdef DEBUG
#import "DDTTYLogger.h"
#else
#import "CrashlyticsLogger.h"
#import "Crashlytics/crashlytics.h"
#endif

#import "NSNotificationCenter+Threads.h"
#ifndef DEBUG
#import "Fabric/Fabric.h"
#import "Crashlytics/Crashlytics.h"
#endif
#import "NSString+Helpers.h"

#import <IOKit/pwr_mgt/IOPMLib.h>
#include <ctype.h>
#include <stdlib.h>
#include <stdio.h>

#include <mach/mach_port.h>
#include <mach/mach_interface.h>
#include <mach/mach_init.h>

#include <IOKit/pwr_mgt/IOPMLib.h>
#include <IOKit/IOMessage.h>

io_connect_t  root_port; // a reference to the Root Power Domain IOService

#define cTiVoLogDirectory @"~/Library/Logs/cTiVo"

static int ddLogLevel = LOG_LEVEL_REPORT;

void MySleepCallBack( void * refCon, io_service_t service, natural_t messageType, void * messageArgument )
{
    switch ( messageType )
    {
			
        case kIOMessageCanSystemSleep:
            /* Idle sleep is about to kick in. This message will not be sent for forced sleep.
			 Applications have a chance to prevent sleep by calling IOCancelPowerChange.
			 Most applications should not prevent idle sleep.
			 
			 Power Management waits up to 30 seconds for you to either allow or deny idle
			 sleep. If you don't acknowledge this power change by calling either
			 IOAllowPowerChange or IOCancelPowerChange, the system will wait 30
			 seconds then go to sleep.
			 */
			
            //Uncomment to cancel idle sleep
            //IOCancelPowerChange( root_port, (long)messageArgument );
            // we will allow idle sleep
			DDLogCMajor(@"cTiVo Received Soft Sleep Notice");
			if ([[NSUserDefaults standardUserDefaults] boolForKey:kMTPreventSleep]) { //We want to prevent sleep if still downloading
				if ([tiVoManager numberOfShowsToDownload]) {
					//					NSLog(@"ZZZReceived Soft Sleep Notice and cancelling");
					IOCancelPowerChange(root_port, (long)messageArgument);
				} else { //THere are no shows pending so sleeep
						 //					NSLog(@"ZZZReceived Soft Sleep Notice but no shows downloading so allowing");
					IOAllowPowerChange( root_port, (long)messageArgument );
				}
			} else { //Cancel things and get on with it.
					 //				NSLog(@"ZZZReceived Soft Sleep Notice and allowing");
				IOAllowPowerChange( root_port, (long)messageArgument );
			}
            break;
			
        case kIOMessageSystemWillSleep:
            /* The system WILL go to sleep. If you do not call IOAllowPowerChange or
			 IOCancelPowerChange to acknowledge this message, sleep will be
			 delayed by 30 seconds.
			 
			 NOTE: If you call IOCancelPowerChange to deny sleep it returns
			 kIOReturnSuccess, however the system WILL still go to sleep.
			 */
			
			DDLogCMajor(@"cTiVo received Forced Sleep Notice, shutting down downloads");
			[tiVoManager cancelAllDownloads];
            IOAllowPowerChange( root_port, (long)messageArgument );
            break;
			
        case kIOMessageSystemWillPowerOn:
            //System has started the wake up process...
			DDLogCMajor(@"cTiVo received Wake notice");
            break;
			
        case kIOMessageSystemHasPoweredOn:
            //System has finished waking up...
			DDLogCMajor(@"cTiVo finished Waking notice");
			[NSNotificationCenter postNotificationNameOnMainThread:kMTNotificationDownloadQueueUpdated object:nil];
			break;
			
        default:
			DDLogCMajor( @"cTiVo received messageType %08lx, arg %08lx\n",
				   (long unsigned int)messageType,
				   (long unsigned int)messageArgument );
			break;
			
    }
}

void signalHandler(int signal)
{
	//Do nothing only use to intercept SIGPIPE.  Ignoring this should be fine as the the retry system should catch the failure and cancel and restart
	tiVoManager.signalError = signal;
    //NSLog(@"Got signal %d",signal); not safe
}

@interface MTAppDelegate  () {
	IBOutlet NSMenuItem *refreshTiVoMenuItem, *iTunesMenuItem, *markCommercialsItem, *skipCommercialsItem, *pauseMenuItem, *apmMenuItem;
	IBOutlet NSMenuItem *playVideoMenuItem, *showInFinderMenuItem;
	IBOutlet NSMenu *optionsMenu;
    IBOutlet NSView *formatSelectionTable;
    IBOutlet NSTableView *exportTableView;

	NSMutableArray *mediaKeyQueue;
	BOOL gettingMediaKey;
	NSTimer * checkingDone;
	NSTimer * saveQueueTimer;
    BOOL quitWhenCurrentDownloadsComplete;
}

@property (nonatomic, strong) MTPreferencesWindowController *preferencesController;
@property (nonatomic, strong) MTMainWindowController  *mainWindowController;
@property (weak, nonatomic, readonly) NSNumber *numberOfUserFormats;
@property (nonatomic, strong) MTTiVoManager *tiVoGlobalManager;
@property (nonatomic, strong) NSTimer * pseudoTimer;


@end

@implementation MTAppDelegate

+ (int)ddLogLevel { return ddLogLevel; }+ (void)ddSetLogLevel:(int)logLevel {ddLogLevel = logLevel;}


- (void)dealloc
{
	DDLogDetail(@"deallocing AppDelegate");
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
   [[NSUserDefaults standardUserDefaults] registerDefaults:@{ @"NSApplicationCrashOnExceptions": @YES }];
#ifndef DEBUG
    if (![[NSUserDefaults standardUserDefaults] boolForKey:kMTCrashlyticsOptOut]) {
        [Fabric with:@[[Crashlytics class]]];
    }
#endif
	PFMoveToApplicationsFolderIfNecessary();
    CGEventRef event = CGEventCreate(NULL);
    CGEventFlags modifiers = CGEventGetFlags(event);
    CFRelease(event);
	
    CGEventFlags flags = (kCGEventFlagMaskAlternate | kCGEventFlagMaskControl);
    if ((modifiers & flags) == flags) {
        [[NSUserDefaults standardUserDefaults] setObject:@{} forKey:kMTDebugLevelDetail];
		[[NSUserDefaults standardUserDefaults] setObject:@15 forKey:kMTDebugLevel];
		[DDLog setAllClassesLogLevelFromUserDefaults:kMTDebugLevel];
    } else if ( [[NSUserDefaults standardUserDefaults] integerForKey:kMTDebugLevel] == 15){
        [[NSUserDefaults standardUserDefaults] setObject:@3 forKey:kMTDebugLevel];
        [DDLog setAllClassesLogLevelFromUserDefaults:kMTDebugLevel];
   } else {
        [[NSUserDefaults standardUserDefaults]  registerDefaults:@{kMTDebugLevel: @1}];
        [DDLog setAllClassesLogLevelFromUserDefaults:kMTDebugLevel];
        
    }

#ifdef DEBUG
    MTLogFormatter * ttyLogFormat = [MTLogFormatter new];
	[DDLog addLogger:[DDTTYLogger sharedInstance]];
	[[DDTTYLogger sharedInstance] setLogFormatter:ttyLogFormat];
	
	[[DDTTYLogger sharedInstance] setColorsEnabled:YES];
#define MakeColor(r, g, b) [NSColor colorWithCalibratedRed:(r/255.0f) green:(g/255.0f) blue:(b/255.0f) alpha:1.0f]
	[[DDTTYLogger sharedInstance] setForegroundColor:MakeColor(80,0,0) backgroundColor:nil forFlag:LOG_FLAG_REPORT];
	[[DDTTYLogger sharedInstance] setForegroundColor:MakeColor(160,0,0) backgroundColor:nil forFlag:LOG_FLAG_MAJOR];
	[[DDTTYLogger sharedInstance] setForegroundColor:MakeColor(0,128,0)  backgroundColor:nil forFlag:LOG_FLAG_DETAIL];
	[[DDTTYLogger sharedInstance] setForegroundColor:MakeColor(160,160,160)  backgroundColor:nil forFlag:LOG_FLAG_VERBOSE];
#else
    MTLogFormatter * crashLyticsLogFormat = [MTLogFormatter new];
    [[CrashlyticsLogger sharedInstance] setLogFormatter: crashLyticsLogFormat];
    [DDLog addLogger:[CrashlyticsLogger sharedInstance]];
#endif
	// Initialize File Logger
    DDLogFileManagerDefault *ddlogFileManager = [[DDLogFileManagerDefault alloc] initWithLogsDirectory:[cTiVoLogDirectory stringByExpandingTildeInPath]];
    DDFileLogger *fileLogger = [[DDFileLogger alloc] initWithLogFileManager:ddlogFileManager];
    // Configure File Logger
     [fileLogger setMaximumFileSize:(20 * 1024 * 1024)];
    [fileLogger.logFileManager setLogFilesDiskQuota:0]; //only delete max files
    [fileLogger setRollingFrequency:(3600.0 * 24.0)];
    [[fileLogger logFileManager] setMaximumNumberOfLogFiles:4];
    MTLogFormatter * fileLogFormat = [MTLogFormatter new];
	[fileLogger setLogFormatter:fileLogFormat];
    [DDLog addLogger:fileLogger];

    DDLogReport(@"Starting cTiVo; version: %@", [[[NSBundle mainBundle] infoDictionary] valueForKey:@"CFBundleVersion"]);

	NSDictionary *userDefaultsDefaults = [NSDictionary dictionaryWithObjectsAndKeys:
										  @NO, kMTShowCopyProtected,
										  @YES, kMTShowSuggestions,
										  @YES, kMTShowFolders,
										  @NO, kMTPreventSleep,
										  @kMTMaxDownloadRetries, kMTNumDownloadRetries,
										  @0, kMTUpdateIntervalMinutesNew,
										  @NO, kMTiTunesDelete,
										  @NO, kMTHasMultipleTivos,
										  @NO, kMTMarkCommercials,
                                          @YES, kMTiTunesIcon,
										  @YES, kMTUseMemoryBufferForDownload,
										  // @NO, kMTAllowDups, future
										  [NSString pathWithComponents:@[NSHomeDirectory(),kMTDefaultDownloadDir]],kMTDownloadDirectory,
                                          kMTTmpDir,kMTTmpFilesDirectory,
                                          @{},kMTTheTVDBCache,
										  kMTcTiVoDefault,kMTFileNameFormat,
										  @NO, kMTiTunesContentIDExperiment,
										  @NO, kMTTrustTVDBEpisodes,
                                          @(1), KMTPreferredImageSource,  //TiVoSource; see MTTiVoShow for MTImageSource enum
                                          @2, kMTMaxNumEncoders,
                                          @240, kMTMaxProgressDelay,
                                          @"tivodecode-ng", kMTDecodeBinary,
                                          @NO, kMTDownloadTSFormat,
                                          @NO, kMTExportTextMetaData,
                                          @NO, kMTExportSubtitles,
                                          @NO, kMTSaveMPGFile,
                                          @[], kMTChannelInfo,
                                          nil];

    [[NSUserDefaults standardUserDefaults] registerDefaults:userDefaultsDefaults];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(cancelUserQuit) name:kMTNotificationUserCanceledQuit object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateTivoRefreshMenu) name:kMTNotificationTiVoListUpdated object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(getMediaKeyFromUserOnMainThread:) name:kMTNotificationMediaKeyNeeded object:nil];

    quitWhenCurrentDownloadsComplete = NO;
    mediaKeyQueue = [NSMutableArray new];
    _tiVoGlobalManager = [MTTiVoManager sharedTiVoManager];

   [_tiVoGlobalManager addObserver:self forKeyPath:@"selectedFormat" options:NSKeyValueObservingOptionInitial context:nil];
    [_tiVoGlobalManager addObserver:self forKeyPath:@"processingPaused" options:NSKeyValueObservingOptionInitial context:nil];
	[[NSUserDefaults standardUserDefaults] addObserver:self forKeyPath:kMTRunComSkip options:NSKeyValueObservingOptionNew context:nil];
	[[NSUserDefaults standardUserDefaults] addObserver:self forKeyPath:kMTMarkCommercials options:NSKeyValueObservingOptionNew context:nil];
	[[NSUserDefaults standardUserDefaults] addObserver:self forKeyPath:kMTTmpFilesDirectory options:NSKeyValueObservingOptionNew context:nil];
	_mainWindowController = nil;
	//	_formatEditorController = nil;
	[self showMainWindow:nil];
	gettingMediaKey = NO;
	signal(SIGPIPE, &signalHandler);
	signal(SIGABRT, &signalHandler );
	
	if ([[NSUserDefaults standardUserDefaults] stringForKey:kMTFileNameFormat].length == 0) {
		NSString * newDefaultFileFormat = kMTcTiVoDefault;
		if ([[NSUserDefaults standardUserDefaults] boolForKey: kMTMakeSubDirs]) {
			newDefaultFileFormat = kMTcTiVoFolder;
		}
		[[NSUserDefaults standardUserDefaults] setObject:newDefaultFileFormat forKey: kMTFileNameFormat];

	}
	[[NSUserDefaults standardUserDefaults] setObject:nil forKey: kMTMakeSubDirs];

	//Turn off check mark on Pause/Resume queue menu item
	[pauseMenuItem setOnStateImage:nil];
	[self.tiVoGlobalManager determineCurrentProcessingState];

    //Initialize tmp directory
    [self clearTmpDirectory];

	//Set up callback for sleep notification (this is 10.5 method and is still valid.  There is newer UI in 10.6 on.
	
	// notification port allocated by IORegisterForSystemPower
    IONotificationPortRef  notifyPortRef;
	
    // notifier object, used to deregister later
    io_object_t            notifierObject;
	// this parameter is passed to the callback
    void*                  refCon  = NULL;
	
    // register to receive system sleep notifications
	
    root_port = IORegisterForSystemPower( refCon, &notifyPortRef, MySleepCallBack, &notifierObject );
    if ( root_port == 0 )
    {
        printf("IORegisterForSystemPower failed\n");
    }
	
    // add the notification port to the application runloop
    CFRunLoopAddSource( CFRunLoopGetCurrent(),
					   IONotificationPortGetRunLoopSource(notifyPortRef), kCFRunLoopCommonModes );
    
    //Make sure details and thumbnails directories are available
    [self checkDirectoryAndPurge:[tiVoManager tivoTempDirectory]];
    [self checkDirectoryAndPurge:[tiVoManager tvdbTempDirectory]];
    [self checkDirectoryAndPurge:[tiVoManager detailsTempDirectory]];


	saveQueueTimer = [NSTimer scheduledTimerWithTimeInterval: (5 * 60.0) target:tiVoManager selector:@selector(saveState) userInfo:nil repeats:YES];
	
    self.pseudoTimer = [NSTimer scheduledTimerWithTimeInterval: 61 target:self selector:@selector(launchPseudoEvent) userInfo:nil repeats:YES];  //every minute to clear autoreleasepools when no user interaction
    DDLogDetail(@"Finished appDidFinishLaunch");

 }

-(void) launchPseudoEvent {
    DDLogVerbose(@"PseudoEvent");
    NSEvent *pseudoEvent = [NSEvent otherEventWithType:NSApplicationDefined location:NSZeroPoint modifierFlags:0 timestamp:[NSDate timeIntervalSinceReferenceDate] windowNumber:0 context:nil subtype:0 data1:0 data2:0];
    [NSApp postEvent:pseudoEvent atStart:YES];

}
- (void)applicationDidBecomeActive:(NSNotification *)notification {
    if (_tiVoGlobalManager) { //in case system calls this before applicationDidLaunch (High Sierra)
        [self showMainWindow:notification];
    }
}

NSOpenPanel* myOpenPanel = nil;  //weird bug where sometimes we're called twice for directory change.
                          //from [NSUserDefaultsController _setSingleValue:forKey:]
BOOL wasPaused = NO;
BOOL tempDirectory = NO;

-(void) closeDirectoryPanel {
    [myOpenPanel close];
    myOpenPanel = nil;
    [[[NSWorkspace sharedWorkspace] notificationCenter  ] removeObserver:self];

    [[NSUserDefaults standardUserDefaults] setBool:wasPaused forKey:kMTQueuePaused];
    [tiVoManager determineCurrentProcessingState];
}

-(void)newVolume: (NSNotification *) notification {
    if (!myOpenPanel) return;
    //new volume came online during openPanel for tempDir, so let's try it for tmpDir
    [self closeDirectoryPanel];
    [self validateTmpDirectory];
}

-(void) checkDirectoryAndPurge: (NSURL *) directory  {
    NSFileManager *fm = [NSFileManager defaultManager];

    NSNumber *isDirectory = nil;
    NSError * error;
    BOOL fileExists = [directory getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:nil];

    if (fileExists && (isDirectory && !(isDirectory.boolValue))) {
        [fm removeItemAtURL:directory error:nil];
        fileExists = NO;
    } else if (error) {
        DDLogReport(@"Error in checking directory %@: %@", directory, error.localizedDescription);
        return;
    }

    if (!fileExists) {
        [fm createDirectoryAtURL:directory
     withIntermediateDirectories:YES
                      attributes:nil
                           error:&error];
    } else {  //Get rid of 'old' files    }
        NSArray <NSURL *> *files = [fm contentsOfDirectoryAtURL:directory
                                     includingPropertiesForKeys:@[NSURLContentModificationDateKey]
                                                        options:NSDirectoryEnumerationSkipsHiddenFiles
                                                          error:nil];
        for (NSURL *fileURL in files) {
            NSDictionary *attributes = [fm attributesOfItemAtPath:fileURL.path error:nil];
            NSDate * modifiedDate = attributes[NSFileModificationDate];
            if (modifiedDate && [[NSDate date] timeIntervalSinceDate:modifiedDate] > 3600 * 24 * 30) {
                [fm removeItemAtURL:fileURL  error:nil];
                DDLogVerbose(@"Removed file %@",fileURL);
            }
        }
    }
}

-(void) promptForNewDirectory:(NSString *) oldTmpDir withMessage: (NSString *) message tempDir:(BOOL) tempDir{
    NSString * dirType = tempDir ? @"temp" : @"downloading";
    if (myOpenPanel) return;
    tempDirectory = tempDir;
    //need to pause until directory is resolved
    myOpenPanel = [[NSOpenPanel alloc] init];
    wasPaused =     [[NSUserDefaults standardUserDefaults] boolForKey:kMTQueuePaused];
    if (!wasPaused) [[NSUserDefaults standardUserDefaults] setBool:YES forKey:kMTQueuePaused];
    if (![tiVoManager.processingPaused boolValue]) [tiVoManager pauseQueue:@(NO)];
    NSString *fullMessage = [NSString stringWithFormat:message,oldTmpDir];
    DDLogReport(@"Error \"%@\" while checking %@ directory.",fullMessage, dirType);
    if ( [oldTmpDir isEquivalentToPath:  kMTTmpDir]) {
        fullMessage = [fullMessage stringByAppendingString:[NSString stringWithFormat: @"\nPlease fix directory problem, or choose a new %@ location.", dirType ]] ;
    } else {
        fullMessage = [fullMessage stringByAppendingString:[NSString stringWithFormat: @"\nPlease choose a new location, or press 'Cancel' to use default %@ directory.", dirType ]] ;
    }
    myOpenPanel.canChooseFiles = NO;
    myOpenPanel.canChooseDirectories = YES;
    myOpenPanel.canCreateDirectories = YES;
    myOpenPanel.directoryURL = [NSURL fileURLWithPath:oldTmpDir];
    myOpenPanel.message = fullMessage;
    myOpenPanel.prompt = @"Choose";
    [myOpenPanel setTitle:[NSString stringWithFormat:@"Select Directory for %@ cTiVo Files", dirType]];

    [[[NSWorkspace sharedWorkspace] notificationCenter  ] addObserver:self selector:@selector(newVolume:) name:NSWorkspaceDidMountNotification object:nil];
    NSWindow * window = [NSApp keyWindow] ?: _mainWindowController.window;
    [myOpenPanel beginSheetModalForWindow:window completionHandler:^(NSInteger ret){
        NSString *directoryName = (ret == NSFileHandlingPanelOKButton) ? myOpenPanel.URL.path : kMTTmpDir;
        [self closeDirectoryPanel];
        if (tempDir) {
            [[NSUserDefaults standardUserDefaults] setObject:directoryName forKey:kMTTmpFilesDirectory];
            [self validateTmpDirectory];
        } else {
            //XXX handle download directory here
        }
   }];
    [myOpenPanel makeKeyAndOrderFront:nil];
}

-(void)validateTmpDirectory
{
    //Validate users choice for tmpFilesDirectory
    NSString *tmpdir = [[NSUserDefaults standardUserDefaults] stringForKey:kMTTmpFilesDirectory];
    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL isDir = YES;
    if (!tmpdir) {
        [self promptForNewDirectory:kMTTmpDir withMessage:@"Need temporary directory?" tempDir:YES ];
        return;
    }
    if (![fm fileExistsAtPath:tmpdir isDirectory:&isDir]) {
        NSError *error = nil;

        if ([tmpdir hasPrefix:@"/Volumes"]) {
            NSArray <NSString *> * pathComponents = [tmpdir pathComponents];
            if (pathComponents.count > 1) {
                NSString * volume = [pathComponents[0] stringByAppendingPathComponent:pathComponents[1]];
                if (![fm fileExistsAtPath:volume isDirectory:&isDir])
                    DDLogReport(@"Volume %@ not online", volume);
                [self promptForNewDirectory:tmpdir withMessage:@"Unable to find volume for %@; maybe need to plug in?" tempDir:YES];
                return;
            }
        }
        if ([fm createDirectoryAtPath:tmpdir withIntermediateDirectories:YES attributes:nil error:&error]) {
            DDLogReport(@"Creating new temp directory at %@",tmpdir);
        } else {
            DDLogReport(@"Error %@ creating new temp directory at %@",error, tmpdir);
            [self promptForNewDirectory:tmpdir withMessage:@"Unable to create directory %@; maybe need to fix permissions?" tempDir:YES];
            return;
        }
        isDir = YES;
    }
    if ( !isDir) {
        [self promptForNewDirectory:tmpdir withMessage:@"%@ is a file, not a directory" tempDir:YES];
        return;
    }
    if ( [[tiVoManager downloadDirectory] isEquivalentToPath:  kMTTmpDir]) {
        //well, that's not good
        tiVoManager.downloadDirectory = [tiVoManager defaultDownloadDirectory];
    }
    if ([tmpdir isEquivalentToPath: [tiVoManager defaultDownloadDirectory]  ] ) {
        //Oops; user confused temp dir with download dir
        [self promptForNewDirectory:tmpdir withMessage:@"Your temp directory %@ needs to be separate from your download directory." tempDir:YES];
         return;
    }
    //Now check for write permission
    NSString *testPath = [NSString stringWithFormat:@"%@/.junk",tmpdir];
    BOOL canWrite = [fm createFileAtPath:testPath contents:[NSData data] attributes:nil];
    if (!canWrite) {
         [self promptForNewDirectory:tmpdir withMessage:@"You don't have write permission on %@." tempDir:YES];

    } else {
        //Clean up
        [fm removeItemAtPath:testPath error:nil];
    }
}

-(void)clearTmpDirectory
{
	//Make sure the tmp directory exists
    NSString * tmpPath = tiVoManager.tmpFilesDirectory;
    if(![[NSUserDefaults standardUserDefaults] boolForKey:kMTSaveTmpFiles]) {
      if ([tmpPath isEquivalentToPath:kMTTmpDir]){
        //only erase all files if we're in our original temp dir. Too risky elsewise;
		//Clear it if not saving intermediate files
			NSFileManager *fm = [NSFileManager defaultManager];
			NSError *err = nil;
			NSArray *filesToRemove = [fm contentsOfDirectoryAtPath:tmpPath error:&err];
			if (err) {
				DDLogMajor(@"Could not get content of %@.  Got error %@",tmpPath,err);
			} else {
				if (filesToRemove) {
					for (NSString *file in filesToRemove) {
						NSString * path = [NSString pathWithComponents:@[tmpPath,file]];
						[fm removeItemAtPath:path error:&err];
						if (err) {
							DDLogMajor(@"Could not delete file %@.  Got error %@",file,err);
						}
					}
				}
			}
		}
	}
}

-(void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if ([keyPath compare:@"selectedFormat"] == NSOrderedSame) {
		DDLogDetail(@"Selecting Format: %@", tiVoManager.selectedFormat);
		BOOL caniTune = [tiVoManager.selectedFormat.iTunes boolValue];
        BOOL canSkip = [tiVoManager.selectedFormat.comSkip boolValue];
		BOOL canMark = tiVoManager.selectedFormat.canMarkCommercials;
		[iTunesMenuItem setHidden:!caniTune];
		[skipCommercialsItem setHidden:!canSkip];
		[markCommercialsItem setHidden:!canMark];
	} else if ([keyPath compare:kMTMarkCommercials] == NSOrderedSame) {
		BOOL markCom = [[NSUserDefaults standardUserDefaults] boolForKey:kMTMarkCommercials];
		BOOL runComSkip = [[NSUserDefaults standardUserDefaults] boolForKey:kMTRunComSkip];
		if (markCom && runComSkip) {
			[[NSUserDefaults standardUserDefaults] setBool:NO forKey:kMTRunComSkip];
		}
	} else if ([keyPath compare:kMTRunComSkip] == NSOrderedSame) {
		BOOL markCom = [[NSUserDefaults standardUserDefaults] boolForKey:kMTMarkCommercials];
		BOOL runComSkip = [[NSUserDefaults standardUserDefaults] boolForKey:kMTRunComSkip];
		if (markCom && runComSkip) {
			[[NSUserDefaults standardUserDefaults] setBool:NO forKey:kMTMarkCommercials];
		}
	} else if ([keyPath compare:@"processingPaused"] == NSOrderedSame) {
		pauseMenuItem.title = [self.tiVoGlobalManager.processingPaused boolValue] ? @"Resume Queue" : @"Pause Queue";
	} else if ([keyPath compare:kMTTmpFilesDirectory] == NSOrderedSame) {
		[self validateTmpDirectory];
	}
}

#pragma mark - UI support

-(IBAction)togglePause:(id)sender
{
	DDLogMajor(@"User toggled Pause %@", self.tiVoGlobalManager.processingPaused);
	//	pauseMenuItem.title = [self.tiVoGlobalManager.processingPaused boolValue] ? @"Resume Queue" : @"Pause Queue";
	if (![self.tiVoGlobalManager.processingPaused boolValue]) {
		[self.tiVoGlobalManager pauseQueue:@(YES)];
	} else {
		[self.tiVoGlobalManager unPauseQueue];
	}
    [[NSUserDefaults standardUserDefaults] setBool:[self.tiVoGlobalManager.processingPaused boolValue] forKey:kMTQueuePaused];

}

-(void)updateTivoRefreshMenu
{
	DDLogDetail(@"Rebuilding TivoRefresh Menu");
	DDLogVerbose(@"Tivos: %@",[_tiVoGlobalManager.tiVoList maskMediaKeys]);
	if (_tiVoGlobalManager.tiVoList.count == 0) {
		[refreshTiVoMenuItem setEnabled:NO];
	} else if (_tiVoGlobalManager.tiVoList.count ==1) {
		[refreshTiVoMenuItem setTarget:nil];
		[refreshTiVoMenuItem setAction:NULL];
		if (((MTTiVo *)_tiVoGlobalManager.tiVoList[0]).isReachable) {
			[refreshTiVoMenuItem setTarget:_tiVoGlobalManager.tiVoList[0]];
			[refreshTiVoMenuItem setAction:@selector(updateShows:)];
			[refreshTiVoMenuItem setEnabled:YES];
		} else  {
			[refreshTiVoMenuItem setEnabled:NO];
		}
	} else {
		[refreshTiVoMenuItem setTarget:_tiVoGlobalManager];
		[refreshTiVoMenuItem setAction:@selector(refreshAllTiVos)];
		[refreshTiVoMenuItem setEnabled:YES];
		NSMenu *thisMenu = [[NSMenu alloc] initWithTitle:@"Refresh Tivo"];
		BOOL lastTivoWasManual = NO;
		for (MTTiVo *tiVo in _tiVoGlobalManager.tiVoList) {
			if (!tiVo.manualTiVo && lastTivoWasManual) { //Insert a separator
				NSMenuItem *menuItem = [NSMenuItem separatorItem];
				[thisMenu addItem:menuItem];
			}
			lastTivoWasManual = tiVo.manualTiVo;
			NSMenuItem *thisMenuItem = [[NSMenuItem alloc] initWithTitle:tiVo.tiVo.name action:NULL keyEquivalent:@""];
			if (!tiVo.isReachable) {
				NSFont *thisFont = [NSFont systemFontOfSize:13];
				NSString *thisTitle = [NSString stringWithFormat:@"%@ offline",tiVo.tiVo.name];
				NSAttributedString *aTitle = [[NSAttributedString alloc] initWithString:thisTitle attributes:[NSDictionary dictionaryWithObjectsAndKeys:[NSColor redColor], NSForegroundColorAttributeName, thisFont, NSFontAttributeName, nil]];
				[thisMenuItem setAttributedTitle:aTitle];
			} else {
				[thisMenuItem setTarget:tiVo];
				[thisMenuItem setAction:@selector(updateShows:)];
				[thisMenuItem setEnabled:YES];
			}
			[thisMenu addItem:thisMenuItem];
		}
        [thisMenu addItem:[NSMenuItem separatorItem]];
        NSMenuItem *thisMenuItem = [[NSMenuItem alloc] initWithTitle:@"All TiVos" action:NULL keyEquivalent:@""];
		[thisMenuItem setTarget:self];
		[thisMenuItem setAction:@selector(updateAllTiVos:)];
		[thisMenuItem setEnabled:YES];
		[thisMenu addItem:thisMenuItem];
		[refreshTiVoMenuItem setSubmenu:thisMenu];
		[refreshTiVoMenuItem setEnabled:YES];
	}
	return;
	
}
-(IBAction)findShows:(id)sender {
	[[_mainWindowController tiVoShowTable] findShows:sender];
}

- (IBAction)clearHistory:(id)sender {
	[[_mainWindowController downloadQueueTable] clearHistory:sender];
}


#pragma mark - Preference pages
-(IBAction)editFormats:(id)sender
{
	//	[self.formatEditorController showWindow:nil];
	self.preferencesController.startingTabIdentifier = @"Formats";
	[self showPreferences:nil];
}

-(IBAction)createManualSubscription:(id)sender {
	NSString *message = @"Enter Series Name for new Subscription:";
	NSAlert *keyAlert = [NSAlert alertWithMessageText:message defaultButton:@"New Subscription" alternateButton:@"Cancel" otherButton:nil informativeTextWithFormat:@"Note: enter ALL to record all TiVo shows."];
	NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 200, 24)];
	
	[input setStringValue:@""];
	[keyAlert setAccessoryView:input];
	NSInteger button = [keyAlert runModal];
	if (button == NSAlertDefaultReturn) {
		[input validateEditing];
		DDLogMajor(@"Got new Subscription %@",input.stringValue);
		NSArray * subs = [[tiVoManager subscribedShows]  addSubscriptionsPatterns:@[input.stringValue]];
		if (subs.count == 0) {
			NSAlert * badSub = [NSAlert alertWithMessageText:@"Invalid Subscription" defaultButton:@"Cancel" alternateButton:@"" otherButton:nil informativeTextWithFormat:@"The subscription pattern may be badly formed, or it may already covered by another subscription."];
			[badSub runModal];
        } else {

        }
	}
}

-(IBAction)editManualTiVos:(id)sender
{
	self.preferencesController.startingTabIdentifier = @"TiVos";
	[self showPreferences:nil];
}

-(IBAction)editChannels:(id)sender
{
    self.preferencesController.startingTabIdentifier = @"Channels";
    [self showPreferences:nil];
}

-(void)showWindowController: (MTPreferencesWindowController *) controller {
    //prefer to show window as attached sheet, but sometimes in the field, we don't have a window?, so just show it regular.
    if (!controller.window) return;
    NSWindow * mainWindow =  _mainWindowController.window ?: [NSApp keyWindow];
    if (mainWindow) {
        [mainWindow beginSheet:controller.window completionHandler:nil];
    } else {
        [controller showWindow:nil];
    }
}

-(IBAction)showPreferences:(id)sender {
    [self showWindowController: self.preferencesController];
}

-(MTPreferencesWindowController *)preferencesController
{
	if (!_preferencesController) {
		_preferencesController = [[MTPreferencesWindowController alloc] initWithWindowNibName:@"MTPreferencesWindowController"];
	}
	return _preferencesController;
}

-(IBAction)showLogs:(id)sender {
    NSURL * showURL =[NSURL fileURLWithPath:[
                                             cTiVoLogDirectory
                                             stringByExpandingTildeInPath] isDirectory:YES];
    if (showURL) {
        DDLogMajor(@"Showing logs at %@ ", showURL);
        [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:@[ showURL ]];
    }
}

-(NSArray <MTTiVoShow *> *) currentSelectedShows {
    MTProgramTableView * programs = self.mainWindowController.tiVoShowTable;
	return [programs selectedShows];
}

#pragma mark - Export Formats Methods

-(NSNumber *)numberOfUserFormats
//used for menu binding
{
	return [NSNumber numberWithInteger:_tiVoGlobalManager.userFormats.count];
}

-(IBAction)exportFormats:(id)sender
{
	NSSavePanel *mySavePanel = [[NSSavePanel alloc] init];
	[mySavePanel setTitle:@"Export User Formats"];
	[mySavePanel setAllowedFileTypes:[NSArray arrayWithObject:@"plist"]];
    [mySavePanel setAccessoryView:formatSelectionTable];
    [exportTableView reloadData];
	[mySavePanel beginWithCompletionHandler:^(NSInteger result){
		if (result == NSFileHandlingPanelOKButton) {
			NSMutableArray *formatsToWrite = [NSMutableArray array];
			for (NSUInteger i = 0; i < self->_tiVoGlobalManager.userFormats.count; i++) {
				//Get selected formats
				NSButton *checkbox = [self->exportTableView viewAtColumn:0 row:i makeIfNecessary:NO];
				if (checkbox.state) {
					[formatsToWrite addObject:[self->_tiVoGlobalManager.userFormats[i] toDictionary]];
				}
			}
			DDLogVerbose(@"formats: %@",formatsToWrite);
			NSString *filename = mySavePanel.URL.path;
			[formatsToWrite writeToFile:filename atomically:YES];
		}
	}];
}

-(NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    return _tiVoGlobalManager.userFormats.count;
}

-(CGFloat)tableView:(NSTableView *)tableView heightOfRow:(NSInteger)row
{
    return 17;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
    // get an existing cell with the MyView identifier if it exists
    NSTableCellView *result = [tableView makeViewWithIdentifier:tableColumn.identifier owner:self];
    MTFormat *thisFomat = [_tiVoGlobalManager.userFormats objectAtIndex:row];
    // There is no existing cell to reuse so we will create a new one
    if (result == nil) {
        
        // create the new NSTextField with a frame of the {0,0} with the width of the table
        // note that the height of the frame is not really relevant, the row-height will modify the height
        // the new text field is then returned as an autoreleased object
        result = [[NSTableCellView alloc] initWithFrame:CGRectMake(0, 0, tableView.frame.size.width, 20)];
        //        result.textField.font = [NSFont userFontOfSize:14];
        result.textField.editable = NO;
        
        // the identifier of the NSTextField instance is set to MyView. This
        // allows it to be re-used
        result.identifier = tableColumn.identifier;
    }
    
    // result is now guaranteed to be valid, either as a re-used cell
    // or as a new cell, so set the stringValue of the cell to the
    // nameArray value at row
	if ([tableColumn.identifier compare:@"checkBox"] == NSOrderedSame) {
	} else if ([tableColumn.identifier compare:@"name"] == NSOrderedSame) {
        result.textField.stringValue = thisFomat.name;
        result.textField.textColor = [NSColor blackColor];
    }     // return the result.
    return result;
    
}



-(IBAction)importFormats:(id)sender
{
	
	NSOpenPanel *formatsOpenPanel = [[NSOpenPanel alloc] init];
	[formatsOpenPanel setTitle:@"Import User Formats"];
	[formatsOpenPanel setAllowedFileTypes:@[@"plist",@"enc"]];
	[formatsOpenPanel beginWithCompletionHandler:^(NSInteger ret){
		NSArray *newFormats = nil;
		if (ret == NSFileHandlingPanelOKButton) {
			NSString *filename = formatsOpenPanel.URL.path;
			if ([[[filename pathExtension ]lowercaseString] isEqualToString: @"plist"]) {
				newFormats = [NSArray arrayWithContentsOfFile:filename];
				[self.tiVoGlobalManager addFormatsToList:newFormats withNotification:YES];
			} else {
				[self.tiVoGlobalManager addEncFormatToList:filename];
			}
		}
	}];
	
}

#pragma mark - MAK routines

-(void)updateAllTiVos:(id)sender
{
	DDLogDetail(@"Updating All TiVos");
	for (MTTiVo *tiVo in _tiVoGlobalManager.tiVoList) {
		[tiVo updateShows:sender];
	}
}

-(void)getMediaKeyFromUserOnMainThread:(NSNotification *)notification
{
    [self performSelectorOnMainThread:@selector(getMediaKeyFromUser:) withObject:notification waitUntilDone:YES];
}

-(void)getMediaKeyFromUser:(NSNotification *)notification
{
	if (notification && notification.object) {  //If sent a new tiVo then add to queue to start
		[mediaKeyQueue addObject:notification.object];
	}
	if (gettingMediaKey || mediaKeyQueue.count == 0) {  //If we're in the middle of a get or nothing to get return
		return;
	}
	gettingMediaKey = YES;
	NSDictionary *request = [mediaKeyQueue objectAtIndex:0]; //Pop off the first in the queue
	MTTiVo *tiVo = request[@"tivo"]; //Pop off the first in the queue
    if (!tiVo.enabled) {
        gettingMediaKey = NO;
        [mediaKeyQueue removeObject:request];
        return;
    }
	NSString *reason = request[@"reason"];
    NSString *message = nil;
	if ([reason isEqualToString:@"new"]) {
        [tiVo getMediaKey];
        if (tiVo.mediaKey.length ==0) {
            message = [NSString stringWithFormat:@"Need new Media Key for %@",tiVo.tiVo.name];
        }
	} else {
		message = [NSString stringWithFormat:@"Incorrect Media Key for %@",tiVo.tiVo.name];
	}
    if (message) {
        NSAlert *keyAlert = [NSAlert alertWithMessageText:message defaultButton:@"Save Key" alternateButton:@"Ignore TiVo" otherButton:nil informativeTextWithFormat:@""];
        NSView *accView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 300, 100)];
        NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(10, 60, 200, 24)];
        [accView addSubview:input];
        NSButton *helpButton = [NSButton new];
        [helpButton setButtonType:NSMomentaryPushInButton];
        [helpButton setBezelStyle:NSRoundedBezelStyle];
        [helpButton setTitle:@"Help"];
        [helpButton sizeToFit];
        [helpButton setFrame:NSMakeRect(220, 60, 70, 24) ];
        [helpButton setTarget:self];
        [helpButton setAction:@selector(help:)];
        [accView addSubview:helpButton];
        
        NSButton *keychainButton = [NSButton new];
        [keychainButton setButtonType:NSSwitchButton];
        [keychainButton setTitle:@"Save in Keychain"];
        [keychainButton sizeToFit];
        NSRect f = keychainButton.frame;
        [keychainButton setFrame:NSMakeRect(50, 20, f.size.width, f.size.height)];
        [keychainButton setState:NSOffState];
        [accView addSubview:keychainButton];
        
        if (tiVo.mediaKey) [input setStringValue:tiVo.mediaKey];
        [keyAlert setAccessoryView:accView];
        NSInteger button = [keyAlert runModal];
        if (button == NSAlertDefaultReturn) {
            [input validateEditing];
            DDLogDetail(@"Got New Media Key" );
            tiVo.mediaKey = input.stringValue;
 			tiVo.enabled = YES;
			[tiVo updateShows:nil];
            if (keychainButton.state == NSOnState ) {
                tiVo.storeMediaKeyInKeychain = YES;
            }
        } else {
            tiVo.enabled = NO;
//            tiVo.mediaKey = input.stringValue;
        }
    }
	[mediaKeyQueue removeObject:request];
	[tiVoManager updateTiVoDefaults:tiVo];

	
	gettingMediaKey = NO;
	[self getMediaKeyFromUser:nil];//Process rest of queue
}


-(void)help:(id)sender
{
	//Get help text for encoder
	NSString *helpFilePath = [[NSBundle mainBundle] pathForResource:@"MAKHelpFile" ofType:@"rtf"];
	NSAttributedString *attrHelpText = [[NSAttributedString alloc] initWithRTF:[NSData dataWithContentsOfFile:helpFilePath] documentAttributes:NULL];
	//	NSString *helpText = [NSString stringWithContentsOfFile:helpFilePath encoding:NSUTF8StringEncoding error:nil];
	NSButton *thisButton = (NSButton *)sender;
    NSPopover *myPopover = [[NSPopover alloc] init];
    myPopover.delegate = self;
    myPopover.behavior = NSPopoverBehaviorTransient;
    MTHelpViewController *helpContoller = [[MTHelpViewController alloc] initWithNibName:@"MTHelpViewController" bundle:nil];
    myPopover.contentViewController = helpContoller;
    [helpContoller loadView];
    [helpContoller.displayMessage.textStorage setAttributedString:attrHelpText];
//	[self.helpController.displayMessage insertText:helpText];
	[myPopover showRelativeToRect:thisButton.bounds ofView:thisButton preferredEdge:NSMaxXEdge];
}




#pragma mark - Application Support

- (NSURL *)applicationFilesDirectory
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSURL *appSupportURL = [[fileManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask] lastObject];
	DDLogVerbose(@"App Support Dir: %@",appSupportURL);
    return [appSupportURL URLByAppendingPathComponent:@"com.cTiVo.cTivo"];
}

-(IBAction)showMainWindow:(id)sender
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
 		_mainWindowController = [[MTMainWindowController alloc] initWithWindowNibName:@"MTMainWindowController"];
		showInFinderMenuItem.target = _mainWindowController;
		showInFinderMenuItem.action = @selector(revealInFinder:);
		playVideoMenuItem.target = _mainWindowController;
		playVideoMenuItem.action = @selector(playVideo:);
		_mainWindowController.showInFinderMenuItem = showInFinderMenuItem;
		_mainWindowController.playVideoMenuItem = playVideoMenuItem;
   });
	[_mainWindowController showWindow:nil];
	
}
-(void) cancelUserQuit {
	quitWhenCurrentDownloadsComplete = NO;
    [tiVoManager determineCurrentProcessingState];
    [self.mainWindowController.cancelQuitView setHidden:YES];

}

-(void) confirmUserQuit {
	NSString *message = [NSString stringWithFormat:@"Shows are in process, and would need to be restarted next time. Do you wish them to finish now, or quit immediately?"];
	NSAlert *quitAlert = [NSAlert alertWithMessageText:message defaultButton:@"Finish current show" alternateButton:@"Cancel" otherButton:@"Quit Immediately" informativeTextWithFormat:@" "];
	NSInteger returnValue = [quitAlert runModal];
	switch (returnValue) {
		case NSAlertDefaultReturn:
			DDLogMajor(@"User did ask to continue until finished");
			tiVoManager.processingPaused = @(YES);
			quitWhenCurrentDownloadsComplete = YES;
			[_mainWindowController.cancelQuitView setHidden:NO];
			[NSApp replyToApplicationShouldTerminate:NO];
            break;
		case NSAlertOtherReturn:
			DDLogMajor(@"User did ask to quit");
			[self cleanup];
			[NSApp replyToApplicationShouldTerminate:YES];
			break;
		case NSAlertAlternateReturn:
		default:
            DDLogMajor(@"User canceled quit");
			[NSApp replyToApplicationShouldTerminate:NO];
			break;
	}
}

-(BOOL)checkForExit {
//return YES if we're trying to exit
	if (quitWhenCurrentDownloadsComplete) {
		if ( ![tiVoManager anyTivoActive]) {
            [[NSApplication sharedApplication] terminate:nil];
        }
	     return YES;
		}
	return NO;
}


-(void) cleanup {
	
	[saveQueueTimer invalidate];
	[tiVoManager cancelAllDownloads];
	[tiVoManager saveState];
	 mediaKeyQueue = nil;
    DDLogReport(@"cTiVo exiting");
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender
{
    DDLogMajor(@"Asked to Quit");
    if ([tiVoManager anyTivoActive] && ![[NSUserDefaults standardUserDefaults] boolForKey:kMTQuitWhileProcessing] && sender ) {
		[self performSelectorOnMainThread:@selector(confirmUserQuit) withObject:nil waitUntilDone:NO];
		return NSTerminateLater;
	} else {
		[self cleanup];
		return NSTerminateNow;
	}
}

@end
