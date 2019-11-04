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
#import "MTRemoteWindowController.h"
#import "MTSubscriptionTableView.h"
#import "MTPreferencesWindowController.h"
#import "MTHelpViewController.h"
#import "MTTiVo.h"
#import "MTSubscriptionList.h"
#import "NSDate+Tomorrow.h"
#import "MTGCDTimer.h"
#import "MTiTunes.h"

#import "DDFileLogger.h"
#import "MTLogFormatter.h"
#ifdef DEBUG
#import "DDOSLogger.h"
#else
#import "CrashlyticsLogger.h"
#import "Crashlytics/crashlytics.h"
#endif

#ifndef MAC_APP_STORE
#import "Sparkle/SUUpdater.h"
#import "PFMoveApplication.h"
#import "NSTask+RunTask.h"
#endif

#import "NSNotificationCenter+Threads.h"
#ifndef DEBUG
#import "Fabric/Fabric.h"
#import "Crashlytics/Crashlytics.h"
#endif
#import "NSString+Helpers.h"

#import <IOKit/pwr_mgt/IOPMLib.h>

#define cTiVoLogDirectory @"~/Library/Logs/cTiVo"

static DDLogLevel ddLogLevel = LOG_LEVEL_REPORT;


void signalHandler(int signal)
{
	//Do nothing only use to intercept SIGPIPE.  Ignoring this should be fine as the the retry system should catch the failure and cancel and restart
	tiVoManager.signalError = signal;
    //NSLog(@"Got signal %d",signal); not safe
}

@interface MTAppDelegate  () {
	IBOutlet NSMenuItem *refreshTiVoMenuItem, *iTunesMenuItem, *markCommercialsItem, *skipCommercialsItem, *pauseMenuItem;
	__weak IBOutlet NSMenuItem *checkForUpdatesMenuItem;
	IBOutlet NSMenu *optionsMenu;
    IBOutlet NSView *formatSelectionTable;
    IBOutlet NSTableView *exportTableView;

	NSMutableArray *mediaKeyQueue;
	BOOL gettingMediaKey;
	NSTimer * saveQueueTimer;
	
    BOOL quitWhenCurrentDownloadsComplete;
}

@property (nonatomic, strong) MTPreferencesWindowController *preferencesController;
@property (nonatomic, strong) MTMainWindowController  *mainWindowController;
@property (weak, nonatomic, readonly) NSNumber *numberOfUserFormats;
@property (nonatomic, strong) MTTiVoManager *tiVoGlobalManager;
#define pseudoEventTime 45
#define pseudoCheckTime 71
@property (atomic, strong) NSTimer * pseudoTimer;
@property (nonatomic, strong) MTGCDTimer * screenFrozenTimer;

@property (nonatomic, strong) NSDate * lastPseudoTime;
@property (nonatomic, strong) NSOpenPanel* myOpenPanel;
@property (nonatomic, assign) BOOL myOpenPanelIsTemp;
#ifndef MAC_APP_STORE
@property (nonatomic, strong) SUUpdater * sparkleUpdater;
#endif

@end

@implementation MTAppDelegate

+ (DDLogLevel)ddLogLevel { return ddLogLevel; }+ (void)ddSetLogLevel:(int)logLevel {ddLogLevel = logLevel;}

- (void)awakeFromNib {
#ifdef MAC_APP_STORE
	[[checkForUpdatesMenuItem menu] removeItem:checkForUpdatesMenuItem];
#else
	self.sparkleUpdater = [[SUUpdater alloc] init];
	checkForUpdatesMenuItem.target = self;
	checkForUpdatesMenuItem.enabled = YES;
	checkForUpdatesMenuItem.action = @selector(checkForUpdates:);
#endif
}

- (IBAction)checkForUpdates:(id)sender {
#ifndef MAC_APP_STORE
	[[SUUpdater sharedUpdater] checkForUpdates:sender];
#endif
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
	
	//first check if we're migrating from MAS to direct version
	// if so, copy prefs and cache over
	//(other direction is handled by OS migration
	NSUserDefaults * defaults = [NSUserDefaults standardUserDefaults];
#ifndef SANDBOX
	NSFileManager *fm = [NSFileManager defaultManager];
	NSString * prefPath = [@"~/Library/Preferences/com.cTiVo.cTiVo.plist" stringByExpandingTildeInPath];
	NSString * containerPrefPath = [@"~/Library/Containers/com.cTiVo.cTiVo/Data/Library/Preferences/com.cTiVo.cTiVo.plist" stringByExpandingTildeInPath];
	if (![fm fileExistsAtPath: prefPath] &&  [fm fileExistsAtPath: containerPrefPath]) {
		//
		if ([defaults objectForKey:kMTQueue]) {
			//defaults persistence wierdness; need to run again from scratch
			NSLog(@"cTiVo run too soon after last time!  Try again!");
			NSAlert *quitAlert = [NSAlert alertWithMessageText:@"cTiVo was run too soon after cTV exited." defaultButton:@"OK" alternateButton:nil otherButton:nil informativeTextWithFormat:@"You'll need to run it again now."];
			[quitAlert runModal];
			[[NSApplication sharedApplication] terminate:nil];
		}
		NSString * tempDefaultsName = @"com.cTiVo.cTiVoMAS";
		NSString * prefs = [NSTask runProgram:@"/usr/bin/defaults"
							withArguments:@[@"import",
											tempDefaultsName,
											containerPrefPath]];
		
		if (prefs.length > 0) NSLog(@"Tried to import prefs, but got: %@", prefs);
		NSDictionary<NSString *,id> * prefsMAS = [defaults persistentDomainForName:tempDefaultsName];
		for (NSString * key in prefsMAS.allKeys ) {
			[defaults setObject:prefsMAS[key] forKey:key];
		}
		NSLog (@"Migrated Preferences from Mac App Store version: %@",[prefsMAS.allKeys sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)]);
//
		//now clean up...
		[fm removeItemAtPath:[@"~/Library/Preferences/com.cTiVo.cTiVoMAS.plist" stringByExpandingTildeInPath]  error:nil ];
		
		//now move caches directory back to Direct location
		NSString * oldCachesPath = [@"~/Library/Containers/com.cTiVo.cTiVo/Data/Library/Caches/com.cTiVo.cTiVo" stringByExpandingTildeInPath];
		NSString * newCachesPath = [@"~/Library/Caches/com.cTiVo.cTiVo" stringByExpandingTildeInPath];
		if (![fm fileExistsAtPath: newCachesPath] &&  [fm fileExistsAtPath: oldCachesPath]) {
			[fm moveItemAtPath:oldCachesPath toPath:newCachesPath error:nil];
		}
		
		NSString * oldLogPath = [@"~/Library/Containers/com.cTiVo.cTiVo/Data/Library/Logs/cTiVo" stringByExpandingTildeInPath];
		NSString * newLogPath = [@"~/Library/Logs/cTiVo" stringByExpandingTildeInPath];
		if (![fm fileExistsAtPath: newLogPath] &&  [fm fileExistsAtPath: oldLogPath]) {
			[fm moveItemAtPath:oldLogPath toPath:newLogPath error:nil];
		}

		//and delete the sandbox Container; will be recreated if they run that app again.
		[fm removeItemAtPath:[@"~/Library/Containers/com.cTiVo.cTiVo" stringByExpandingTildeInPath] error:nil ];
	}
#endif

	[defaults registerDefaults:@{ @"NSApplicationCrashOnExceptions": @YES }];
	
#ifndef DEBUG
    if (![defaults boolForKey:kMTCrashlyticsOptOut]) {
        [Fabric with:@[[Crashlytics class]]];
    }
#ifndef MAC_APP_STORE
	PFMoveToApplicationsFolderIfNecessary();
#endif
#endif
	CGEventRef event = CGEventCreate(NULL);
    CGEventFlags modifiers = CGEventGetFlags(event);
    CFRelease(event);
	[MTLogWatcher sharedInstance]; //self retained
    CGEventFlags flags = (kCGEventFlagMaskAlternate | kCGEventFlagMaskControl);
    if ((modifiers & flags) == flags) {
        [defaults removeObjectForKey:kMTDebugLevelDetail];
		[defaults setObject:@15 forKey:kMTDebugLevel];
    } else if ( [defaults integerForKey:kMTDebugLevel] == 15){
        [defaults setObject:@3 forKey:kMTDebugLevel];
   } else {
        [defaults  registerDefaults:@{kMTDebugLevel: @1}];
    }

#ifdef DEBUG
    MTLogFormatter * ttyLogFormat = [MTLogFormatter new];
	[DDLog addLogger:[DDOSLogger sharedInstance]];
	[[DDOSLogger sharedInstance] setLogFormatter:ttyLogFormat];
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

    DDLogReport(@"Starting " kcTiVoName @"%@; version: %@",
#ifdef SANDBOX
	@" Sandboxed",
#else
	@"",
#endif
[[[NSBundle mainBundle] infoDictionary] valueForKey:@"CFBundleVersion"]);

#ifdef SANDBOX
	//in case we're porting from non-sandboxed:
	NSString * oldTempPath = [defaults objectForKey:kMTTmpFilesPath];
	if (oldTempPath.length) {  //remember in case we go back to non-sandboxed
		[defaults setObject:oldTempPath forKey: @"OldTmpFilePath"];
		[defaults setObject:nil forKey: kMTTmpFilesPath];
	}
#else
	NSString * tempPath = [defaults objectForKey:kMTTmpFilesPath];
	if (!tempPath.length) {
		//maybe coming back from sandboxed
		NSString * oldTmpPath= [defaults objectForKey: @"OldTmpFilePath"];
		if (oldTmpPath.length) {
			[defaults setObject:oldTmpPath forKey: kMTTmpFilesPath];
			[defaults setObject:nil forKey: @"OldTmpFilePath"];
		}
	}
	//Upgrade old defaults
	NSString * oldtmp = [defaults stringForKey:kMTTmpFilesDirectoryObsolete];
	if (oldtmp) {
		if (![oldtmp isEqualToString:kMTTmpDirObsolete]) {
			[defaults setObject:oldtmp forKey: kMTTmpFilesPath];
		}
		[defaults setObject:nil forKey: kMTTmpFilesDirectoryObsolete];
		NSString * oldDownload = [defaults stringForKey:kMTDownloadDirectory];
		if ([oldDownload isEqualToString:[self defaultDownloadDirectory]]) {
			[defaults setObject:nil forKey: kMTDownloadDirectory];
		}
		[defaults setObject:nil forKey: kMTTmpFilesDirectoryObsolete];
	}

	if ([defaults stringForKey:kMTFileNameFormat].length == 0) {
		NSString * newDefaultFileFormat = kMTcTiVoDefault;
		if ([defaults boolForKey: kMTMakeSubDirsObsolete]) {
			newDefaultFileFormat = kMTcTiVoFolder;
			[defaults setObject:nil forKey: kMTMakeSubDirsObsolete];
		}
		[defaults setObject:newDefaultFileFormat forKey: kMTFileNameFormat];
	}

	if ([defaults boolForKey:kMTSkipCommercials]) {
		//transition from 3.1 to 3.3.1
		[defaults setBool:NO forKey:kMTMarkCommercials];
	}
#endif

	NSDictionary *userDefaultsDefaults = [NSDictionary dictionaryWithObjectsAndKeys:
										  @YES, kMTShowCopyProtected,
										  @NO, kMTShowSuggestions,
										  @YES, kMTShowFolders,
										  @YES, kMTPreventSleep,
										  @kMTMaxDownloadRetries, kMTNumDownloadRetries,
										  @0, kMTUpdateIntervalMinutesNew,
										  @NO, kMTiTunesDelete,
										  @NO, kMTHasMultipleTivos,
										  @YES, kMTMarkCommercials,
                                          @YES, kMTiTunesIcon,
										  @YES, kMTUseMemoryBufferForDownload,
										  // @NO, kMTAllowDups, future
										  [self defaultDownloadDirectory],kMTDownloadDirectory,
                                          [self defaultTmpDirectory],kMTTmpFilesPath,
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
										  @(kMTDefaultDelayForSkipModeInfo), kMTWaitForSkipModeInfoTime,
										  [NSDate tomorrowAtTime:1*60], kMTScheduledStartTime,  //start at 1AM tomorrow]
                                          [NSDate tomorrowAtTime:6*60], kMTScheduledEndTime,  //end at 6AM tomorrow],
										  @YES, kMTScheduledSkipModeScan,
										  [NSDate tomorrowAtTime:30], kMTScheduledSkipModeScanStartTime, //start SkipMode scan at 12:30AM tomorrow]
										  [NSDate tomorrowAtTime:5*60+45], kMTScheduledSkipModeScanEndTime, //end SkipMode scan at 5:45AM tomorrow]
										  @3, kMTCommercialStrategy,
										  nil];

    [defaults registerDefaults:userDefaultsDefaults];
	
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(cancelUserQuit) name:kMTNotificationUserCanceledQuit object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateTivoRefreshMenu) name:kMTNotificationTiVoListUpdated object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(getMediaKeyFromUserOnMainThread:) name:kMTNotificationMediaKeyNeeded object:nil];

    quitWhenCurrentDownloadsComplete = NO;
    mediaKeyQueue = [NSMutableArray new];
    _tiVoGlobalManager = [MTTiVoManager sharedTiVoManager];

	_mainWindowController = nil;
	//	_formatEditorController = nil;
	[self showMainWindow:nil];
	if ([defaults boolForKey:@"RemoteVisible"]) [self showRemoteControlWindow:self];

	gettingMediaKey = NO;
	signal(SIGPIPE, &signalHandler);
	signal(SIGABRT, &signalHandler );

	//Turn off check mark on Pause/Resume queue menu item
	[pauseMenuItem setOnStateImage:nil];
	//Don't reference iTunes on Catalina
	if (@available(macOS 10.15, *)) {
		iTunesMenuItem.title = [iTunesMenuItem.title stringByReplacingOccurrencesOfString:@"iTunes" withString:@"TV" ];
		iTunesMenuItem.toolTip = [iTunesMenuItem.toolTip stringByReplacingOccurrencesOfString:@"iTunes" withString:@"Apple's TV app" ];
	}
	[_tiVoGlobalManager addObserver:self forKeyPath:@"selectedFormat" options:NSKeyValueObservingOptionInitial context:nil];
	[_tiVoGlobalManager addObserver:self forKeyPath:@"processingPaused" options:NSKeyValueObservingOptionInitial context:nil];
	[defaults addObserver:self forKeyPath:kMTSkipCommercials options:NSKeyValueObservingOptionNew context:nil];
	[defaults addObserver:self forKeyPath:kMTMarkCommercials options:NSKeyValueObservingOptionNew context:nil];
#ifdef SANDBOX
	[self validateTmpDirectory];
#else
	[defaults addObserver:self forKeyPath:kMTTmpFilesPath options:NSKeyValueObservingOptionInitial context:nil];
#endif
	[defaults addObserver:self forKeyPath:kMTDownloadDirectory options:NSKeyValueObservingOptionInitial context:nil];
	if (@available(macOS 10.10.3, *)) {
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(thermalStateChanged:) name:NSProcessInfoThermalStateDidChangeNotification object:nil];
	}
	[[[NSWorkspace sharedWorkspace] notificationCenter]   addObserver: self selector: @selector(checkVolumes:) name: NSWorkspaceDidWakeNotification object: NULL];
	[[[NSWorkspace sharedWorkspace] notificationCenter  ] addObserver:self selector:@selector(mountVolume:) name:NSWorkspaceDidMountNotification object:nil];
	[[[NSWorkspace sharedWorkspace] notificationCenter  ] addObserver:self selector: @selector(unmountVolume:) name:NSWorkspaceDidUnmountNotification object:nil];
	[[[NSWorkspace sharedWorkspace] notificationCenter] addObserver: self
            selector: @selector(systemSleep:)
            name: NSWorkspaceWillSleepNotification object: NULL];
	
    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver: self
            selector: @selector(systemWake:)
            name: NSWorkspaceDidWakeNotification object: NULL];

	//Initialize tmp directory
	[self clearTmpDirectory];
	
#ifdef SANDBOX
	//get permission for various older download folders:
	[self accessCachedBookMarks];
#endif
	[tiVoManager launchMetadataQuery];
    //Make sure details and thumbnails directories are available
	[self checkDirectoryAndPurge:[tiVoManager tivoTempDirectory]];
    [self checkDirectoryAndPurge:[tiVoManager tvdbTempDirectory]];
    [self checkDirectoryAndPurge:[tiVoManager detailsTempDirectory]];

	saveQueueTimer = [NSTimer scheduledTimerWithTimeInterval: (5 * 60.0) target:tiVoManager selector:@selector(saveState) userInfo:nil repeats:YES];
	self.lastPseudoTime = [NSDate date];
    self.pseudoTimer = [NSTimer scheduledTimerWithTimeInterval: pseudoEventTime target:self selector:@selector(launchPseudoEvent) userInfo:nil repeats:YES];  //every minute to clear autoreleasepools when no user interaction
	
	__weak __typeof__(self) weakSelf = self;

	self.screenFrozenTimer = [MTGCDTimer scheduledTimerWithTimeInterval:pseudoCheckTime
																repeats:YES
																  queue:dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)
																  block:^{
		  __typeof__(self) strongSelf = weakSelf;
		  NSTimeInterval timeSincePseudo;
		  @synchronized(strongSelf) {
			timeSincePseudo = -[strongSelf.lastPseudoTime timeIntervalSinceNow];
		  }
		  if (timeSincePseudo >= pseudoEventTime) {
			  DDLogReport(@"Turning on screen due to main thread frozen for between %0.1f to %0.1f seconds",timeSincePseudo-pseudoEventTime, timeSincePseudo);
			  IOPMAssertionID userActivityID;
			  IOPMAssertionDeclareUserActivity(CFSTR("waking screen for thread contention"), kIOPMUserActiveLocal , &userActivityID);
		  } else {
			  DDLogReport(@"Error; Frozen timer kicked in too soon after %0.1f seconds",timeSincePseudo );
		  }
	}];
	[self.tiVoGlobalManager determineCurrentProcessingState];
	[self.tiVoGlobalManager startTiVos];
	DDLogDetail(@"Finished appDidFinishLaunch");
 }

-(BOOL) alreadyRunning { //returns true if another instance of cTiVo is running
	NSArray <NSRunningApplication *> * apps = [[NSWorkspace sharedWorkspace] runningApplications];
	int myProcess = [[NSProcessInfo  processInfo]  processIdentifier];
	for (NSRunningApplication * app in apps) {
		if ([app.bundleIdentifier isEqualToString: @"com.ctivo.ctivo"]) {
			if (app.processIdentifier != myProcess ) {
				return YES;
			}
		}
	}
	return NO;
}

-(void) systemSleep: (NSNotification *) notification {
	DDLogReport(@"System Sleeping!");
	[tiVoManager cancelAllDownloads];
}

-(void) systemWake: (NSNotification *) notification {
	DDLogReport(@"System Waking!");
	[NSNotificationCenter postNotificationNameOnMainThread:kMTNotificationDownloadQueueUpdated object:nil];
	@synchronized(self) {
		self.lastPseudoTime = [NSDate date]; //no problem with normal sleep
	}
}

NSObject * assertionID = nil;

-(void) preventSleep {
	if (assertionID) return;
	assertionID = [[NSProcessInfo processInfo] beginActivityWithOptions:NSActivityUserInitiated reason:@"Downloading Shows"];
	DDLogMajor(@"Idle Sleep prevented");
}

-(void)allowSleep {
	if (!assertionID) return;
	[[NSProcessInfo processInfo] endActivity:assertionID];
	DDLogMajor(@"Idle Sleep allowed");
	assertionID = nil;
}

-(void) launchPseudoEvent {
    DDLogDetail(@"PseudoEvent");
	NSTimeInterval sinceLastPseudo;
	@synchronized(self) {
		sinceLastPseudo = -[self.lastPseudoTime timeIntervalSinceNow];
	}
	if (sinceLastPseudo > 1.7 * pseudoEventTime ) {
		DDLogReport(@"Looks like cTiVo was frozen out for %0.0f seconds",sinceLastPseudo-pseudoEventTime);
	}
    NSEvent *pseudoEvent = [NSEvent otherEventWithType:NSApplicationDefined location:NSZeroPoint modifierFlags:0 timestamp:[NSDate timeIntervalSinceReferenceDate] windowNumber:0 context:nil subtype:0 data1:0 data2:0];
    [NSApp postEvent:pseudoEvent atStart:YES];
	@synchronized(self) {
		self.lastPseudoTime = [NSDate date];
		[self.screenFrozenTimer nextFireTimeFromNow: pseudoCheckTime];
	}
}

- (void)applicationDidBecomeActive:(NSNotification *)notification {
    if (_tiVoGlobalManager) { //in case system calls this before applicationDidLaunch (High Sierra)
        [self showMainWindow:notification];
    }
}

-(void) thermalStateChanged: (NSNotification *) notification {
	NSProcessInfo * processInfo  = (NSProcessInfo *) notification.object;
	if (@available(macOS 10.10.3, *)) {
		NSString * state;
		switch (processInfo.thermalState) {
			case NSProcessInfoThermalStateNominal:
				state = @"Nominal";
				break;
			case NSProcessInfoThermalStateFair:
				state = @"Fair";
				break;
			case NSProcessInfoThermalStateSerious:
				state = @"Serious";
				break;
			case NSProcessInfoThermalStateCritical:
				state = @"Critical";
				break;
			default:
				state = @"Unknown";
				break;
		}
		
		DDLogDetail(@"Thermal State Changed to %@ for %@; %@on main thread", state, processInfo, [NSThread mainThread] ? @"" : @"not ");
	}
}

#pragma mark -
#pragma mark Directory Management

-(void)mountVolume: (NSNotification *) notification {
	if (self.myOpenPanel) {
		NSString *devicePath = notification.userInfo[ @"NSDevicePath"];
		if ([[[NSUserDefaults standardUserDefaults] stringForKey:kMTDownloadDirectory] contains:devicePath] ||
			[[[NSUserDefaults standardUserDefaults] stringForKey:kMTTmpFilesPath] contains:devicePath]) {
			if (self.myOpenPanel) {
				//new volume came online during openPanel for tempDir or downloadDir, so let's try it
				[self.myOpenPanel.sheetParent endSheet:self.myOpenPanel returnCode: NSModalResponseCancel ];
			}
			[self checkVolumes:notification];
		}
	}
}

-(void)unmountVolume: (NSNotification *) notification {
	NSString *devicePath = notification.userInfo[ @"NSDevicePath"];
	if ([[[NSUserDefaults standardUserDefaults] stringForKey:kMTDownloadDirectory] contains:devicePath] ||
		[[[NSUserDefaults standardUserDefaults] stringForKey:kMTTmpFilesPath] contains:devicePath]) {
		[self checkVolumes:notification];
	}
}

-(void)checkVolumes: (NSNotification *) notification {
	[self validateDownloadDirectory];
	[self validateTmpDirectory];
}

-(BOOL) moveCacheFile: (NSURL *) url to: (NSURL *) toFolder {
	NSFileManager * fm = [NSFileManager defaultManager];
	NSURL * newURL = [toFolder URLByAppendingPathComponent:url.lastPathComponent ];
	NSError * error = nil;
	if (![fm moveItemAtURL:url
					 toURL:newURL
					 error:&error]) {
		if (error.code == 516) {
			DDLogVerbose(@"When moving %@ to %@, already there?", url, newURL);
			[fm removeItemAtURL:url error:&error]; //no need to keep old one
		} else {
			DDLogReport(@"Could not move cache file %@ to %@: %@", url, newURL, error);
			return NO;
		}
	}
	return YES;
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

-(NSString *) defaultDownloadDirectory {
	NSArray <NSString *> *movieDirs = NSSearchPathForDirectoriesInDomains(NSMoviesDirectory, NSUserDomainMask, YES);
	if (movieDirs.count >0) {
		NSString *moviePath = movieDirs[0];
		return [moviePath stringByAppendingPathComponent:@"TiVoShows"];
	} else {
		DDLogReport(@"Movie Directory not available??");
		return [NSString pathWithComponents:@[@"~/Movies/TiVoShows/"]];
	}
}

-(NSString *) defaultTmpDirectory {
	return [NSTemporaryDirectory() stringByAppendingString:@"ctivo"];
}

#define MTOpenPanelDefault 2873 //random; just different from OK v Cancel

-(IBAction)defaultButton:(id)sender {
	if (self.myOpenPanel) {
		//user tapped "Use Default Button"
		[self.myOpenPanel.sheetParent endSheet:self.myOpenPanel returnCode:MTOpenPanelDefault];
	}
}

- (BOOL)panel:(id)sender
  validateURL:(NSURL *)url
        error:(NSError * _Nullable *)outError {
	//Don't let user pick download directory for temp, nor vice-versa
	NSString *dirPath = url.path;
	if (self.myOpenPanelIsTemp) {
		if ([dirPath isEquivalentToPath: [self defaultDownloadDirectory]] ||
			[dirPath isEquivalentToPath: [[NSUserDefaults standardUserDefaults] stringForKey:kMTDownloadDirectory]] ) {
				//Oops; user confused temp dir with download dir
			return NO;
		} else {
			return YES;
		}
	} else {
		if ([dirPath isEquivalentToPath: [[NSUserDefaults standardUserDefaults] stringForKey:kMTTmpFilesPath]] ) {
			return NO;
		} else {
			return YES;
		}
	}
}

-(void) promptForNewDirectory:(NSString *) oldDir withMessage: (NSString *) message isProblem: (BOOL) isProblem isTempDir:(BOOL) isTemp {
	//user directory prompt for both temp directory and downloading directory
	//used both if there's a problem or if user requests a new directory
	if (self.myOpenPanel) {
		DDLogReport(@"panel already open: %@", self.myOpenPanel);
		return;
	}
	NSOpenPanel * openPanel = [NSOpenPanel openPanel];
	BOOL wasPaused =     [[NSUserDefaults standardUserDefaults] boolForKey:kMTQueuePaused];

	if (isProblem) {
		//if problem, we need to pause processing until directory is resolved
		if (!wasPaused) [[NSUserDefaults standardUserDefaults] setBool:YES forKey:kMTQueuePaused];
		if (![tiVoManager.processingPaused boolValue]) [tiVoManager pauseQueue:@(NO)];
	}
	NSString *fullMessage = [NSString stringWithFormat:message,oldDir];
	NSString * dirType = isTemp ? @"temporary" : @"downloading";
	if (isProblem) {
		DDLogReport(@"Warning \"%@\" while checking %@ directory.",fullMessage, dirType);
	} else {
		DDLogMajor(@"User choosing new %@ directory.", dirType);
	}
	fullMessage = [fullMessage stringByAppendingString:[NSString stringWithFormat: @"\nPlease choose a new %@ directory, or 'Use Default Directory' , or Cancel.", dirType ]] ;
	openPanel.canChooseFiles = NO;
	openPanel.canChooseDirectories = YES;
	openPanel.canCreateDirectories = YES;
	openPanel.releasedWhenClosed = YES;
	openPanel.directoryURL = [NSURL fileURLWithPath:oldDir];
	openPanel.message = fullMessage;
	openPanel.prompt = @"Choose";
	openPanel.delegate = self;
	self.myOpenPanelIsTemp = isTemp;
	[openPanel setTitle:[NSString stringWithFormat:@"Select Directory for %@ " kcTiVoName @" Files", dirType]];

	NSArray * views; //get default button from XIB.
	if ([[NSBundle mainBundle] loadNibNamed:@"MTOpenPanelDefaultView" owner:self topLevelObjects:&views]) {
		NSView * accessoryView = nil;
		for (NSView * possView in views) {
			if ([possView isKindOfClass:[NSView class] ]) {  //seems random v application
				accessoryView = possView;
			}
		}
		if (accessoryView) {
			[openPanel setAccessoryView:accessoryView];
			if (@available(macOS 10.11, *)) {
				openPanel.accessoryViewDisclosed = YES;
			}
		}
	};

	self.myOpenPanel = openPanel;

	NSWindow * window = [NSApp keyWindow] ?: _mainWindowController.window;
	[self.myOpenPanel beginSheetModalForWindow:window completionHandler:^(NSInteger returnCode){
		NSString *directoryName  = nil;
#ifdef SANDBOX
		NSData * newBookMark = nil;
#endif
		switch (returnCode) {
			case NSModalResponseOK: {
				NSURL * newURL = self.myOpenPanel.URL;
				directoryName = newURL.path;
				DDLogReport(@"User chose %@ directory: %@.", dirType, directoryName);
#ifdef SANDBOX
				NSError * error = nil;
				newBookMark = [newURL
					bookmarkDataWithOptions: NSURLBookmarkCreationWithSecurityScope
					includingResourceValuesForKeys:nil
					relativeToURL:nil
					error:&error];
				[self cacheBookmark:newBookMark forURL:newURL  ];
				if (error) {
					DDLogReport(@"Could not create bookmark for %@", newURL);
				}
#endif
				break;
			}
			case NSModalResponseCancel:
				directoryName = oldDir;
				DDLogMajor(@"%@ directory selection cancelled", dirType);
				break;
			case MTOpenPanelDefault:
			default:
				directoryName = nil;
				DDLogMajor(@"User chose default %@ directory.", dirType);
				break;
		}
		[self.myOpenPanel orderOut:nil];
		self.myOpenPanel = nil;
		if (returnCode != NSModalResponseCancel || isProblem) {
			if (isTemp) {
				[[NSUserDefaults standardUserDefaults] setObject:directoryName forKey:kMTTmpFilesPath];
			} else {
#ifdef SANDBOX
				[[NSUserDefaults standardUserDefaults] setObject:newBookMark forKey:kMTDownloadDirBookmark];
#else
				[[NSUserDefaults standardUserDefaults] setObject:directoryName forKey:kMTDownloadDirectory];
				tiVoManager.downloadDirectory = directoryName;
#endif
			}
		} else {
			DDLogMajor(@" %@ directory selection cancelled", dirType);
		}
		if (isProblem) {
			[[NSUserDefaults standardUserDefaults] setBool:wasPaused forKey:kMTQueuePaused];
		}
		[tiVoManager determineCurrentProcessingState];
		[self checkVolumes:nil];
	}];
	if (!window) {
		[openPanel makeKeyAndOrderFront:self];
	}
}

#ifdef  SANDBOX
-(NSURL *)resolveStoredBookmark: (NSData *) bookMark forType:(NSString *) bookMarkKey uponRenewal: (void (^)(NSData * newBookMark))renewedBookmark {
	//returns URL, which has been started under security scope, so we can see files
	//note, we actually don't ever stop using to stop using (same for tmp)

	if (bookMark == nil) {
		DDLogReport(@"No bookmark stored for %@", bookMarkKey);
		return nil;
	}
	BOOL isStale = NO;
	NSError * error = nil;
	NSURL * url = [NSURL URLByResolvingBookmarkData:bookMark
											options:NSURLBookmarkResolutionWithSecurityScope
									  relativeToURL:nil
								bookmarkDataIsStale:&isStale
											  error:&error];
	if (error != nil) {
		DDLogReport(@"Error resolving URL from %@ bookmark: %@", bookMarkKey, error);
		return nil;
	} else if (isStale) {
		if ([url startAccessingSecurityScopedResource]) {
			DDLogReport(@"Attempting to renew stale %@ bookmark for %@", bookMarkKey, url);
			// NOTE: This is the bit that fails, a 256 error is
			//       returned due to a deny file-read-data from sandboxd
			bookMark = [url bookmarkDataWithOptions:NSURLBookmarkCreationWithSecurityScope
					 includingResourceValuesForKeys:nil
									  relativeToURL:nil
											  error:&error];
			if (error != nil) {
				[url stopAccessingSecurityScopedResource];
				DDLogReport(@"Failed to renew %@ bookmark: %@", bookMarkKey, error);
				return nil;
			}
			if (renewedBookmark) renewedBookmark(bookMark);
			DDLogReport(@"Bookmark renewed, yay.");
		} else {
			DDLogReport(@"Could not start using the bookmarked, stale %@ url: %@", bookMarkKey, url);
			return nil;
		}
	} else if (! [url startAccessingSecurityScopedResource]) {
		DDLogReport(@"Could not start using the bookmarked %@ url: %@", bookMarkKey, url);
		return nil;
	}
	DDLogDetail(@"Bookmarked %@ url %@ resolved successfully!", bookMarkKey, url);
	return url;
}

#define maxCacheSize 7
-(void) cacheBookmark: (NSData *) bookmark forURL: (NSURL *) url{
	if (!bookmark) return;
	BOOL found = NO;
	NSArray <NSData *> * oldCache = [[NSUserDefaults standardUserDefaults ] objectForKey:kMTRecentDownloadBookMarks];
	NSMutableArray <NSData *> * newCache = [NSMutableArray arrayWithCapacity:MIN(oldCache.count+1,maxCacheSize)];
	[newCache addObject:bookmark];
	for (NSData * oldBookmark in oldCache) {
		if (newCache.count >= maxCacheSize) {
			break;
		} else if (found) {
			[newCache addObject:oldBookmark]; //just copy the rest
		} else { //check not the same as url
			BOOL isStale = NO;
			NSError * error = nil;
			NSURL * oldURL = [NSURL URLByResolvingBookmarkData:oldBookmark
													   options:NSURLBookmarkResolutionWithSecurityScope
												 relativeToURL:nil
										   bookmarkDataIsStale:&isStale
														 error:&error];
			if (error != nil || isStale || !oldURL) {
				DDLogReport(@"Error resolving old URL from %@bookmark: %@", isStale ? @"stale ":@"",error);
			} else if ([oldURL isEqual:url]) {
				DDLogReport(@"Reusing bookmark for URL: %@",url);
				found = YES;
			} else 	{
				[newCache addObject:oldBookmark];
			}
		}
	}
	[[NSUserDefaults standardUserDefaults] setObject:newCache forKey:kMTRecentDownloadBookMarks];
	[tiVoManager launchMetadataQuery];
}

-(void) accessCachedBookMarks {
	NSArray <NSData *> * cache = [[NSUserDefaults standardUserDefaults ] objectForKey:kMTRecentDownloadBookMarks];
	NSMutableArray <NSData *> * newCache = [NSMutableArray arrayWithCapacity:cache.count];
	NSString * downloadDir =[tiVoManager downloadDirectory];
	if (!downloadDir) {
		DDLogReport(@"No download directory??");
		return;
	}
	NSURL * downURL = [NSURL fileURLWithPath:downloadDir isDirectory:YES];
	if (!downURL) {
		DDLogReport(@"Invalid download dir for URL: %@??", downloadDir);
		return;
	}
	NSMutableSet <NSURL *> * urls = [NSMutableSet setWithObject:downURL];
	__block BOOL didChange = NO;
	for (NSData * oldBookmark in cache) {
		__block NSData * tempBookmark = oldBookmark;
		NSURL * url = [self resolveStoredBookmark:oldBookmark forType:@"cached" uponRenewal:^(NSData *newBookmark) {
			tempBookmark = newBookmark;
			didChange = YES;
		}];
		if (tempBookmark && url && ![urls containsObject:url]) {
			[newCache addObject:tempBookmark];
			[urls addObject:url];
		}
	}
	if (didChange)[[NSUserDefaults standardUserDefaults] setObject:newCache forKey:kMTRecentDownloadBookMarks];
}
#endif

-(void)validateDownloadDirectory {
	NSUserDefaults * defaults = [NSUserDefaults standardUserDefaults];
#ifdef SANDBOX
	if ([defaults objectForKey:kMTDownloadDirBookmark]) { //if URL bookmark exists, then it overrides download dir
		NSURL * downloadURL = [self resolveStoredBookmark:[defaults objectForKey:kMTDownloadDirBookmark]  forType:@"Download Directory" uponRenewal:^(NSData *newBookMark) {
			[defaults setObject: newBookMark forKey:kMTDownloadDirBookmark];
		} ];
		DDLogMajor(@"Sandbox found %@: %@",kMTDownloadDirBookmark, downloadURL);
		NSString *oldDownloadDir = [defaults stringForKey:kMTDownloadDirectory];
		NSString * newDownloadDir = downloadURL.path;
		if (![oldDownloadDir isEqualToString:newDownloadDir]) { //avoid recursion
			tiVoManager.downloadDirectory =  downloadURL.path;
		}
	}
#endif

	 NSString *downloadDir = [defaults stringForKey:kMTDownloadDirectory];
	 if ([downloadDir isEquivalentToPath: [[NSUserDefaults standardUserDefaults] stringForKey:kMTTmpFilesPath]] ) {
		//Oops; user confused temp dir with download dir
		[self promptForNewDirectory:downloadDir withMessage:@"Your temp directory %@ needs to be separate from your download directory." isProblem: YES isTempDir:NO];
	} else {
		[self validateDirectoryShared:downloadDir isTempDir:NO];
	}
}

-(void)validateTmpDirectory {
	//Validate users choice for tmpFilesDirectory
	NSString *tmpdir = tiVoManager.tmpFilesDirectory;
	if ([tmpdir isEquivalentToPath: [self defaultDownloadDirectory]] ||
	    [tmpdir isEquivalentToPath: [[NSUserDefaults standardUserDefaults] stringForKey:kMTDownloadDirectory]] ) {
			//Oops; user confused temp dir with download dir
			[self promptForNewDirectory:tmpdir withMessage:@"Your temp directory %@ needs to be separate from your download directory." isProblem: YES isTempDir:YES];
	} else {
		[self validateDirectoryShared:tmpdir isTempDir:YES];
	}
}

-(void)validateDirectoryShared: (NSString *) dirPath isTempDir:(BOOL) isTempDir {
	if (self.myOpenPanel) return; // already looking for one
	NSString * dirType = isTempDir ? @"temp" : @"downloading";

	NSFileManager *fm = [NSFileManager defaultManager];
	BOOL isDir = YES;
	if (![fm fileExistsAtPath:dirPath isDirectory:&isDir]) {
		NSError *error = nil;

		if ([dirPath hasPrefix:@"/Volumes"]) {
			NSArray <NSString *> * pathComponents = [dirPath pathComponents];
			if (pathComponents.count > 1) {
				NSString * volume = [[pathComponents[0] stringByAppendingPathComponent:pathComponents[1]] stringByAppendingPathComponent:pathComponents[2]];  //  "/", "Volumes", "volname"
				if (![fm fileExistsAtPath:volume isDirectory:&isDir]) {
					DDLogReport(@"Volume %@ not online for %@", volume, dirType);
					[self promptForNewDirectory:dirPath withMessage:@"Unable to find volume for %@; maybe need to plug in?" isProblem: YES isTempDir:isTempDir];
					return;
				}
			}
		}
		if ([fm createDirectoryAtPath:dirPath withIntermediateDirectories:YES attributes:nil error:&error]) {
			DDLogReport(@"Creating new %@ directory at %@",dirType, dirPath);
		} else {
			DDLogReport(@"Error %@ creating new %@ directory at %@",error, dirType, dirPath);
			[self promptForNewDirectory:dirPath withMessage:@"Unable to create directory %@; maybe need to fix permissions?" isProblem: YES isTempDir:isTempDir];
			return;
		}
		isDir = YES;
	}
	if ( !isDir) {
		[self promptForNewDirectory:dirPath withMessage:@"%@ is a file, not a directory" isProblem: YES isTempDir:YES];
		return;
	}

	//Now check for read permission
	NSURL * dirURL = [NSURL fileURLWithPath:dirPath ];
	NSError * error = nil;
	[fm contentsOfDirectoryAtURL:dirURL
		includingPropertiesForKeys:[NSArray array]
						   options:0
							 error:&error
	   ];
	if (error) {
		DDLogReport(@"Could not read %@ directory at %@", dirType, error);
		NSString * message = (error.code == 257) ?
			//sandbox violation
			@"Please allow " kcTiVoName @" to access %@." :
			@"You don't have read permission on %@.";
		[self promptForNewDirectory:dirPath withMessage: message isProblem: YES isTempDir:isTempDir];
		return;
	}

	//Now check for write permission
	NSString *testPath = [NSString stringWithFormat:@"%@/.junk",dirPath];
	
	BOOL canWrite = [fm createFileAtPath:testPath contents:[NSData data] attributes:nil];
	if (!canWrite) {
		[self promptForNewDirectory:dirPath withMessage:@"You don't have write permission on %@." isProblem: YES isTempDir:isTempDir];
		return;
	} else {
		//Clean up
		[fm removeItemAtPath:testPath error:nil];
	}
}

-(void)clearTmpDirectory
{
	//Make sure the tmp directory exists and delete
	NSString * tmpPath = tiVoManager.tmpFilesDirectory;
	if(![[NSUserDefaults standardUserDefaults] boolForKey:kMTSaveTmpFiles]) {
		if ([tmpPath contains: NSTemporaryDirectory()]) {
		//only erase all files if we're in default temp dir. Too risky elsewise;
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
							DDLogReport(@"Could not delete file %@ in temp directory.  Got error %@",file,err);
							break; // shouldn't keep trying if we have a problem
						}
					}
				}
			}
		}
	}
}

#pragma mark - UI support
//particularly for Menu management
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
		BOOL skipComm = [[NSUserDefaults standardUserDefaults] boolForKey:kMTSkipCommercials];
		if (markCom && skipComm) {
			[[NSUserDefaults standardUserDefaults] setBool:NO forKey:kMTSkipCommercials];
		}
	} else if ([keyPath compare:kMTSkipCommercials] == NSOrderedSame) {
		BOOL markCom = [[NSUserDefaults standardUserDefaults] boolForKey:kMTMarkCommercials];
		BOOL skipComm = [[NSUserDefaults standardUserDefaults] boolForKey:kMTSkipCommercials];
		if (markCom && skipComm) {
			[[NSUserDefaults standardUserDefaults] setBool:NO forKey:kMTMarkCommercials];
		}
	} else if ([keyPath compare:@"processingPaused"] == NSOrderedSame) {
		pauseMenuItem.title = [self.tiVoGlobalManager.processingPaused boolValue] ? @"Resume Queue" : @"Pause Queue";
	} else if ([keyPath compare:kMTTmpFilesPath] == NSOrderedSame) {
		[self validateTmpDirectory];
	} else if ([keyPath compare:kMTDownloadDirectory] == NSOrderedSame) {
		[self validateDownloadDirectory];
	} else {
		[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
	}
}

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
			if (!tiVo.tiVo.name) continue;
			if (!tiVo.manualTiVo && lastTivoWasManual) { //Insert a separator
				NSMenuItem *menuItem = [NSMenuItem separatorItem];
				[thisMenu addItem:menuItem];
			}
			lastTivoWasManual = tiVo.manualTiVo;
			NSMenuItem *thisMenuItem = [[NSMenuItem alloc] initWithTitle:tiVo.tiVo.name action:NULL keyEquivalent:@""];
			NSColor * red =  [NSColor redColor];
			if (@available(macOS 10.10, *)) red = [NSColor systemRedColor];
			if (!tiVo.isReachable) {
				NSFont *thisFont = [NSFont systemFontOfSize:13];
				NSString *thisTitle = [NSString stringWithFormat:@"%@ offline",tiVo.tiVo.name];
				NSAttributedString *aTitle = [[NSAttributedString alloc] initWithString:thisTitle attributes:[NSDictionary dictionaryWithObjectsAndKeys:red, NSForegroundColorAttributeName, thisFont, NSFontAttributeName, nil]];
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
    NSWindow * mainWindow =  _mainWindowController.window ?: [NSApp mainWindow];
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
	return [programs actionItems];
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
        result.textField.textColor = [NSColor controlTextColor];
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
		[self getMediaKeyFromUser:nil];//Process rest of queue
		return;
    }
	NSString *reason = request[@"reason"];
    NSString *message = nil;
	if ([reason isEqualToString:@"new"]) {
        [tiVo getMediaKey];
        if (tiVo.mediaKey.length ==0) {
            message = [NSString stringWithFormat:@"Need Media Access Key for %@",tiVo.tiVo.name];
		} else {
			tiVo.enabled = YES;
			[tiVo updateShows:nil];
			//yay. someone else filled in our media key
		}
	} else {
		message = [NSString stringWithFormat:@"Incorrect Media Access Key for %@",tiVo.tiVo.name];
	}
    if (message) {
        NSAlert *keyAlert = [NSAlert alertWithMessageText:message defaultButton:@"Save Key" alternateButton:@"Ignore TiVo" otherButton:nil informativeTextWithFormat:@" "];
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
        
        if (tiVo.mediaKey.length) [input setStringValue:tiVo.mediaKey];
        [keyAlert setAccessoryView:accView];
        NSInteger button = [keyAlert runModal];
        if (button == NSAlertDefaultReturn) {
            [input validateEditing];
            DDLogDetail(@"Got New Media Key" );
            tiVo.mediaKey = input.stringValue;
			tiVo.enabled = tiVo.mediaKey.length > 0;
			if (tiVo.enabled) {
				[tiVo updateShows:nil];
				if (keychainButton.state == NSOnState ) {
					tiVo.storeMediaKeyInKeychain = YES;
				}
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


-(void)help:(id)sender {
	//Get help text for MAK
	MTHelpViewController *helpController = [[MTHelpViewController alloc] init];
	[helpController loadResource:@"MAKHelpFile"];
	[helpController pointToView:sender preferredEdge:NSMaxXEdge];
}

#pragma mark - Application Support

- (NSURL *)applicationFilesDirectory
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSURL *appSupportURL = [[fileManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask] lastObject];
	DDLogVerbose(@"App Support Dir: %@",appSupportURL);
    return [appSupportURL URLByAppendingPathComponent:@"com.cTiVo.cTivo"];
}

-(MTMainWindowController *) mainWindowController {
	if (!_mainWindowController) {
		_mainWindowController = [[MTMainWindowController alloc] initWithWindowNibName:@"MTMainWindowController"];
	}
	return _mainWindowController;
}

-(BOOL)validateMenuItem:(NSMenuItem *)menuItem {
	if (menuItem.action == @selector(showRemoteControlWindow:)) {
		return [NSApp keyWindow ] != _remoteControlWindowController.window;
	} else 	if (menuItem.action == @selector(showMainWindow:)) {
		return [NSApp keyWindow ] != _mainWindowController.window;
	} else {
		return YES;
	}
}

-(IBAction)showMainWindow:(id)sender {
	[self.mainWindowController showWindow:nil];
}

-(MTRemoteWindowController *) remoteControlWindowController {
	if (!_remoteControlWindowController) {
		self.remoteControlWindowController = [[MTRemoteWindowController alloc] init];
	}
	return _remoteControlWindowController;
}

-(IBAction) showRemoteControlWindow: (id) sender {
	[self.remoteControlWindowController showWindow:nil];
}

-(void) cancelUserQuit {
	quitWhenCurrentDownloadsComplete = NO;
    [tiVoManager determineCurrentProcessingState];
	[self.mainWindowController showCancelQuitView:NO];

}

-(void) confirmUserQuit {
	NSString *message = [NSString stringWithFormat:@"Shows are in process, and would need to be restarted next time. Do you wish them to finish now, or quit immediately?"];
	NSAlert *quitAlert = [NSAlert alertWithMessageText:message defaultButton:@"Finish current show" alternateButton:@"Cancel" otherButton:@"Quit Immediately" informativeTextWithFormat:@" "]; //space necessary to avoid constraint error msg
	NSInteger returnValue = [quitAlert runModal];
	switch (returnValue) {
		case NSAlertDefaultReturn:
			DDLogMajor(@"User did ask to continue until finished");
			tiVoManager.processingPaused = @(YES);
			quitWhenCurrentDownloadsComplete = YES;
			[self.mainWindowController showCancelQuitView:YES];
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
	[[NSUserDefaults standardUserDefaults] setBool: _remoteControlWindowController.window.isVisible forKey:@"RemoteVisible"];
	 mediaKeyQueue = nil;
    DDLogReport(@"" kcTiVoName @" exiting");
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
