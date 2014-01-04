//
//  MTAppDelegate.m
//  myTivo
//
//  Created by Scott Buchanan on 12/6/12.
//  Copyright (c) 2012 Scott Buchanan. All rights reserved.
//

#import "MTAppDelegate.h"
#import "MTTiVo.h"

#import "DDLog.h"
#import "DDTTYLogger.h"
#import "DDFileLogger.h"
#import "MTLogFormatter.h"

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

void MySleepCallBack( void * refCon, io_service_t service, natural_t messageType, void * messageArgument )
{
    printf( "messageType %08lx, arg %08lx\n",
		   (long unsigned int)messageType,
		   (long unsigned int)messageArgument );
	
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
			//			NSLog(@"ZZZReceived Soft Sleep Notice");
			
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
			
			//			NSLog(@"ZZZReceived Forced Sleep Notice and shutting down downloads");
			[tiVoManager cancelAllDownloads];
            IOAllowPowerChange( root_port, (long)messageArgument );
            break;
			
        case kIOMessageSystemWillPowerOn:
            //System has started the wake up process...
			//			NSLog(@"ZZZReceived Wake Notice");
            break;
			
        case kIOMessageSystemHasPoweredOn:
            //System has finished waking up...
			[[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationDownloadQueueUpdated object:nil];
			break;
			
        default:
            break;
			
    }
}

void signalHandler(int signal)
{
	//Do nothing only use to intercept SIGPIPE.  Ignoring this should be fine as the the retry system should catch the failure and cancel and restart
	tiVoManager.signalError = signal;
	NSLog(@"Got signal %d",signal);
}

@implementation MTAppDelegate


__DDLOGHERE__

- (void)dealloc
{
	DDLogDetail(@"deallocing AppDelegate");
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
	CGEventRef event = CGEventCreate(NULL);
    CGEventFlags modifiers = CGEventGetFlags(event);
    CFRelease(event);
	
    CGEventFlags flags = (kCGEventFlagMaskAlternate | kCGEventFlagMaskControl);
    if ((modifiers & flags) == flags) {
		[[NSUserDefaults standardUserDefaults] setObject:@{} forKey:kMTDebugLevelDetail];
		[[NSUserDefaults standardUserDefaults] setObject:@15 forKey:kMTDebugLevel];
		[DDLog setAllClassesLogLevelFromUserDefaults:kMTDebugLevel];
	} else {
		[[NSUserDefaults standardUserDefaults]  registerDefaults:@{kMTDebugLevel: @1}];
		[DDLog setAllClassesLogLevelFromUserDefaults:kMTDebugLevel];
		
	}
	
	// Insert code here to initialize your application
	
	//	[[NSUserDefaults standardUserDefaults] setObject:@{} forKey:kMTMediaKeys];  //Test code for starting from scratch
	MTLogFormatter * logFormat = [MTLogFormatter new];

	[DDLog addLogger:[DDTTYLogger sharedInstance]];
	[[DDTTYLogger sharedInstance] setLogFormatter:logFormat];
	
	[[DDTTYLogger sharedInstance] setColorsEnabled:YES];
#define MakeColor(r, g, b) [NSColor colorWithCalibratedRed:(r/255.0f) green:(g/255.0f) blue:(b/255.0f) alpha:1.0f]
	[[DDTTYLogger sharedInstance] setForegroundColor:MakeColor(80,0,0) backgroundColor:nil forFlag:LOG_FLAG_REPORT];
	[[DDTTYLogger sharedInstance] setForegroundColor:MakeColor(160,0,0) backgroundColor:nil forFlag:LOG_FLAG_MAJOR];
	[[DDTTYLogger sharedInstance] setForegroundColor:MakeColor(0,128,0)  backgroundColor:nil forFlag:LOG_FLAG_DETAIL];
	[[DDTTYLogger sharedInstance] setForegroundColor:MakeColor(160,160,160)  backgroundColor:nil forFlag:LOG_FLAG_VERBOSE];
	// Initialize File Logger
    DDFileLogger *fileLogger = [[DDFileLogger alloc] init];
    // Configure File Logger
    [fileLogger setMaximumFileSize:(10 * 1024 * 1024)];
    [fileLogger setRollingFrequency:(3600.0 * 24.0)];
    [[fileLogger logFileManager] setMaximumNumberOfLogFiles:3];
	[fileLogger setLogFormatter:logFormat];
    [DDLog addLogger:fileLogger];

	DDLogReport(@"Starting cTiVo; version: %@", [[[NSBundle mainBundle] infoDictionary] valueForKey:@"CFBundleVersion"]);
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateTivoRefreshMenu) name:kMTNotificationTiVoListUpdated object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(trackListUpdates) name:kMTNotificationTiVoListUpdated object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(getMediaKeyFromUserOnMainThread:) name:kMTNotificationMediaKeyNeeded object:nil];

	NSDictionary *userDefaultsDefaults = [NSDictionary dictionaryWithObjectsAndKeys:
										  @NO, kMTShowCopyProtected,
										  @YES, kMTShowSuggestions,
										  @NO, kMTPreventSleep,
										  @kMTMaxDownloadRetries, kMTNumDownloadRetries,
										  @kMTUpdateIntervalMinDefault, kMTUpdateIntervalMinutes,
										  @NO, kMTiTunesDelete,
										  @NO, kMTHasMultipleTivos,
										  @NO, kMTMarkCommercials,
                                          @YES, kMTiTunesIcon,
										  @YES, kMTUseMemoryBufferForDownload,
										  // @NO, kMTAllowDups, future
										  [NSString pathWithComponents:@[NSHomeDirectory(),kMTDefaultDownloadDir]],kMTDownloadDirectory,
                                          kMTTmpDir,kMTTmpFilesDirectory,
                                          @{},kMTTheTVDBCache,
										  @"",kMTFileNameFormat,
										  @YES,kMTGetEpisodeArt,
										  @NO, kMTiTunesContentIDExperiment,
										  nil];
    
	[[NSUserDefaults standardUserDefaults] registerDefaults:userDefaultsDefaults];
	
	if (![[NSUserDefaults standardUserDefaults] objectForKey:kMTSelectedFormat]) {
		//What? No previous format,must be our first run. Let's see if there's any iTivo prefs.
		[MTiTiVoImport checkForiTiVoPrefs];
	}
	
	mediaKeyQueue = [NSMutableArray new];
//	[self updateManualTiVosWithID];
    [self updateTiVos];
	_tiVoGlobalManager = [MTTiVoManager sharedTiVoManager];
    [_tiVoGlobalManager loadManualTiVos];
    [_tiVoGlobalManager searchForBonjourTiVos];

    [_tiVoGlobalManager addObserver:self forKeyPath:@"selectedFormat" options:NSKeyValueChangeSetting context:nil];
    [_tiVoGlobalManager addObserver:self forKeyPath:@"processingPaused" options:NSKeyValueChangeSetting context:nil];
	[[NSUserDefaults standardUserDefaults] addObserver:self forKeyPath:kMTRunComSkip options:NSKeyValueObservingOptionNew context:nil];
	[[NSUserDefaults standardUserDefaults] addObserver:self forKeyPath:kMTMarkCommercials options:NSKeyValueObservingOptionNew context:nil];
	[[NSUserDefaults standardUserDefaults] addObserver:self forKeyPath:kMTTmpFilesDirectory options:NSKeyValueObservingOptionNew context:nil];
	mainWindowController = nil;
	//	_formatEditorController = nil;
	[self showMainWindow:nil];
	[self updateTivoRefreshMenu];
	gettingMediaKey = NO;
	signal(SIGPIPE, &signalHandler);
	signal(SIGABRT, &signalHandler );
	
    //Initialize tmp directory
    [self validateTmpDirectory];
	[self clearTmpDirectory];

	//Turn off check mark on Pause/Resume queue menu item
	[pauseMenuItem setOnStateImage:nil];
	[self.tiVoGlobalManager determineCurrentProcessingState];
    
    
    
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
    
    //Make sure details directory is available
    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL isDir;
    BOOL fileExists = [fm fileExistsAtPath:kMTTmpDetailsDir isDirectory:&isDir];
    if (fileExists && !isDir) {
        [fm removeItemAtPath:kMTTmpDetailsDir error:nil];
        fileExists = NO;
    }
    if (!fileExists) {
        [fm createDirectoryAtPath:kMTTmpDetailsDir withIntermediateDirectories:YES attributes:nil error:nil];
    } else {  //Get rid of 'old' file
		NSArray *files = [fm contentsOfDirectoryAtPath:kMTTmpDetailsDir error:nil];
		for (NSString *file in files) {
			NSString *filePath = [NSString stringWithFormat:@"%@/%@",kMTTmpDetailsDir,file];
			NSDictionary *attrs = [fm attributesOfItemAtPath:filePath error:nil];
			NSDate *creationDate = [attrs objectForKey: NSFileModificationDate];
			if ([[NSDate date] timeIntervalSinceDate:creationDate] > 3600 * 24 * 30) {
				[fm removeItemAtPath:filePath error:nil];
				DDLogVerbose(@"Removed file %@",filePath);
			}
		}
		
	}
	saveQueueTimer = [NSTimer scheduledTimerWithTimeInterval: ([[NSUserDefaults standardUserDefaults] integerForKey:kMTUpdateIntervalMinutes] * 60.0) + 1.0 target:tiVoManager selector:@selector(writeDownloadQueueToUserDefaults) userInfo:nil repeats:YES];
	
	//Update atomicparsley default to metatdata default
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	if ([defaults objectForKey:@"ExportAtomicParsleyMetaData"]) {  //Old name
		NSNumber *md = [defaults objectForKey:@"ExportAtomicParsleyMetaData"];
		[defaults removeObjectForKey:@"ExportAtomicParsleyMetaData"];
		[defaults setObject:md forKey:@"ExportMetaData"];
	}
//    manualTiVoArrayController = [NSArrayController new];
//    [manualTiVoArrayController bind:@"content" toObject:[NSUserDefaults standardUserDefaults] withKeyPath:@"TiVos" options:nil];
//    
//    [manualTiVoArrayController setFilterPredicate:[NSPredicate predicateWithBlock:^BOOL(id item, NSDictionary *bindings){
//        NSDictionary *tiVo = (NSDictionary *)item;
//        return [tiVo[kMTTiVoManualTiVo] boolValue];
//    }]];
//    networkTiVoArrayController = [NSArrayController new];
//    [networkTiVoArrayController bind:@"content" toObject:[NSUserDefaults standardUserDefaults] withKeyPath:@"TiVos" options:nil];
//    [networkTiVoArrayController setFilterPredicate:[NSPredicate predicateWithBlock:^BOOL(id item, NSDictionary *bindings){
//        NSDictionary *tiVo = (NSDictionary *)item;
//        return ![tiVo[kMTTiVoManualTiVo] boolValue];
//    }]];


}
-(void) trackListUpdates {
//	NSLog(@"trackListUpdates");
	
}

/* 
Routine to update and combine both the manual tivo preferences and the media keys, all of which are TiVo related into 1 preference
 array for TiVos to eliminate duplication and simplify maintanence.  This only needs to be done once.
 
 */

-(void)updateTiVos
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults objectForKey:kMTTiVos]) return;  //We've already done this.
    NSArray *manualTiVos = [self updateManualTiVosWithID];
    NSMutableDictionary *mediaKeys = [NSMutableDictionary dictionaryWithDictionary:[defaults objectForKey:kMTMediaKeys]];
    NSDictionary *mediaKeyFixed = [defaults objectForKey:kMTMediaKeys];
    NSMutableArray *newTiVoList = [NSMutableArray array];
    for (NSDictionary *manualTiVo in manualTiVos) {
        NSMutableDictionary *newManualTiVo = [NSMutableDictionary dictionaryWithDictionary:manualTiVo];
        //correct for change from iPAddress to IPAddress
        if (newManualTiVo[@"iPAddress"]) {
            newManualTiVo[kMTTiVoIPAddress] = newManualTiVo[@"iPAddress"];
            [newManualTiVo removeObjectForKey:@"iPAddress"];
        }
        newManualTiVo[kMTTiVoManualTiVo] = @YES;
        NSString *tname = [manualTiVo objectForKey:kMTTiVoUserName];
        for (NSString *key in mediaKeyFixed) {
            if ([key isEqualTo:tname]) {
                newManualTiVo[kMTTiVoMediaKey] = mediaKeys[key];
                [mediaKeys removeObjectForKey:key];
            }
        }
        [newTiVoList addObject:newManualTiVo];  //Updated manual tivo added to TiVo list
    }
    for (NSString *name in mediaKeys) {
        [newTiVoList addObject:@{kMTTiVoEnabled : @YES, kMTTiVoUserName : name, kMTTiVoMediaKey : mediaKeys[name]}];
    }
    [defaults removeObjectForKey:kMTMediaKeys];
    [defaults removeObjectForKey:kMTManualTiVos];
    [defaults setValue:newTiVoList forKeyPath:kMTTiVos];
    [defaults synchronize];
    
}

/*
 Routine to update the manual tivo list with an ID.  This only needs to be done once.
 
 */
-(NSArray *)updateManualTiVosWithID
{
	NSArray *manualTiVoDescriptions = [[NSUserDefaults standardUserDefaults] arrayForKey:kMTManualTiVos];
	if (manualTiVoDescriptions && manualTiVoDescriptions.count && ![manualTiVoDescriptions[0] objectForKey:@"id"]) {
		int idNum = 1;
		NSMutableArray *newManualTiVos = [NSMutableArray array];
		for (NSDictionary *mTiVo in manualTiVoDescriptions) {
			NSMutableDictionary *newMTiVo = [NSMutableDictionary dictionaryWithDictionary:mTiVo];
			newMTiVo[@"id"] = [NSNumber numberWithInt:idNum++];
			[newManualTiVos addObject:newMTiVo];
		}
        return [NSArray arrayWithArray:newManualTiVos];
	} else {
        return manualTiVoDescriptions;
    }
}

-(void)validateTmpDirectory
{
    //Validate users choice for tmpFilesDirectory
    NSString *tmpdir = [[NSUserDefaults standardUserDefaults] stringForKey:kMTTmpFilesDirectory];
    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL isDir, newDir = YES;
    if (![fm fileExistsAtPath:tmpdir isDirectory:&isDir]) {
        NSError *error = nil;
        newDir = [fm createDirectoryAtPath:tmpdir withIntermediateDirectories:YES attributes:nil error:&error];
        if (error) DDLogMajor(@"Error %@ creating new tmp directory",error);

        if (newDir) {
            isDir = YES;
        }
    }
    if (!newDir || !isDir) { //Something wrong with this choice
        if (newDir && !isDir) {
            NSString *message = [NSString stringWithFormat:@"%@ is a file, not a directory.  \nPlease choose a new location and press 'Choose' \nor press 'Cancel' to delete the existing file.",tmpdir];
			NSOpenPanel *myOpenPanel = [[NSOpenPanel alloc] init];
			myOpenPanel.canChooseFiles = NO;
			myOpenPanel.canChooseDirectories = YES;
			myOpenPanel.canCreateDirectories = YES;
			myOpenPanel.directoryURL = [NSURL fileURLWithPath:tmpdir];
			myOpenPanel.message = message;
			myOpenPanel.prompt = @"Choose";
			[myOpenPanel setTitle:@"Select Temp Directory for Files"];
			[myOpenPanel beginSheetModalForWindow:mainWindowController.window completionHandler:^(NSInteger ret){
				if (ret == NSFileHandlingPanelOKButton) {
					NSString *directoryName = myOpenPanel.URL.path;
					[[NSUserDefaults standardUserDefaults] setObject:directoryName forKey:kMTTmpFilesDirectory];
				} else {
					NSError *error = nil;
					[fm removeItemAtPath:tmpdir error:&error];
					if (error) DDLogMajor(@"Error was %@",error);
				}
				[myOpenPanel close];
				[self validateTmpDirectory];
			}];
        } else {
            NSString *message = [NSString stringWithFormat:@"Unable to create directory %@. \n Please choose a new location or fix permissions.",tmpdir];
			NSOpenPanel *myOpenPanel = [[NSOpenPanel alloc] init];
			myOpenPanel.canChooseFiles = NO;
			myOpenPanel.canChooseDirectories = YES;
			myOpenPanel.canCreateDirectories = YES;
			myOpenPanel.directoryURL = [NSURL fileURLWithPath:tmpdir];
			myOpenPanel.message = message;
			myOpenPanel.prompt = @"Choose";
			[myOpenPanel setTitle:@"Select Temp Directory for Files"];
			[myOpenPanel beginSheetModalForWindow:mainWindowController.window completionHandler:^(NSInteger ret){
				if (ret == NSFileHandlingPanelOKButton) {
					NSString *directoryName = myOpenPanel.URL.path;
					[[NSUserDefaults standardUserDefaults] setObject:directoryName forKey:kMTTmpFilesDirectory];
				}
				[myOpenPanel close];
				[self validateTmpDirectory];
			}];
        }
    }
    //Now check for write permission
    NSString *testPath = [NSString stringWithFormat:@"%@/.junk",tmpdir];
    BOOL canWrite = [fm createFileAtPath:testPath contents:[NSData data] attributes:nil];
    if (!canWrite) {
        NSString *message = [NSString stringWithFormat:@"You don't have write permission on %@.  \nPlease fix the permissions or choose a new location.",tmpdir];
		NSOpenPanel *myOpenPanel = [[NSOpenPanel alloc] init];
		myOpenPanel.canChooseFiles = NO;
		myOpenPanel.canChooseDirectories = YES;
		myOpenPanel.canCreateDirectories = YES;
		myOpenPanel.directoryURL = [NSURL fileURLWithPath:tmpdir];
		myOpenPanel.message = message;
		myOpenPanel.prompt = @"Choose";
		[myOpenPanel setTitle:@"Select Temp Directory for Files"];
		[myOpenPanel beginSheetModalForWindow:mainWindowController.window completionHandler:^(NSInteger ret){
			if (ret == NSFileHandlingPanelOKButton) {
				NSString *directoryName = myOpenPanel.URL.path;
				[[NSUserDefaults standardUserDefaults] setObject:directoryName forKey:kMTTmpFilesDirectory];
			}
			[myOpenPanel close];
			[self validateTmpDirectory];
		}];

    } else {
        //Clean up
        [fm removeItemAtPath:testPath error:nil];
    }
    return;
  
}

-(void)clearTmpDirectory
{
	//Make sure the tmp directory exits
	if (![[NSFileManager defaultManager] fileExistsAtPath:tiVoManager.tmpFilesDirectory]) {
		[[NSFileManager defaultManager] createDirectoryAtPath:tiVoManager.tmpFilesDirectory withIntermediateDirectories:YES attributes:nil error:nil];
	} else {
		//Clear it if not saving intermediate files
		if(![[NSUserDefaults standardUserDefaults] boolForKey:kMTSaveTmpFiles]) {
			NSFileManager *fm = [NSFileManager defaultManager];
			NSError *err = nil;
			NSArray *filesToRemove = [fm contentsOfDirectoryAtPath:tiVoManager.tmpFilesDirectory error:&err];
			if (err) {
				DDLogMajor(@"Could not get content of %@.  Got error %@",tiVoManager.tmpFilesDirectory,err);
			} else {
				if (filesToRemove) {
					for (NSString *file in filesToRemove) {
						NSString * path = [NSString pathWithComponents:@[tiVoManager.tmpFilesDirectory,file]];
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
		DDLogDetail(@"Selecting Format");
		BOOL caniTune = [tiVoManager.selectedFormat.iTunes boolValue];
        BOOL canSkip = [tiVoManager.selectedFormat.comSkip boolValue];
		BOOL canMark = tiVoManager.selectedFormat.canMarkCommercials;
//		BOOL canAPM = tiVoManager.selectedFormat.canAcceptMetaData ;
		NSArray *menuItems = [optionsMenu itemArray];
		for (NSMenuItem *mi in menuItems) {
			if ([mi isSeparatorItem]) {
				break;  //leave items after first separator
			}
			[optionsMenu removeItem:mi];
		}
		NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
#ifndef deleteXML
		//		if (canAPM) {
//			apmMenuItem = [[NSMenuItem alloc] init];
//			apmMenuItem.title = @"Add Metadata to Video File";
//			[apmMenuItem bind:@"value" toObject:defaults withKeyPath:kMTExportMetaData options:nil];
//			[optionsMenu insertItem:apmMenuItem atIndex:0];
//		}
#endif
		if (caniTune) {
			iTunesMenuItem = [[NSMenuItem alloc] init];
			iTunesMenuItem.title = @"Add to iTunes when complete";
			[iTunesMenuItem bind:@"value" toObject:defaults withKeyPath:kMTiTunesSubmit options:nil];
			[optionsMenu insertItem:iTunesMenuItem atIndex:0];
			//			[simulEncodeItem setEnabled:YES];
		}
//		if (canSimulEncode) {
//			simulEncodeItem = [[NSMenuItem alloc] init];
//			simulEncodeItem.title = @"Simultaneous Encoding";
//			[simulEncodeItem bind:@"value" toObject:defaults withKeyPath:kMTSimultaneousEncode options:nil];
//			[optionsMenu insertItem:simulEncodeItem atIndex:0];
//			//			[simulEncodeItem setEnabled:YES];
//		}
		
		if (canSkip) {
			skipCommercialsItem = [[NSMenuItem alloc] init];
			skipCommercialsItem.title = @"Skip Commercials";
			[skipCommercialsItem bind:@"value" toObject:defaults withKeyPath:kMTRunComSkip options:nil];
			[optionsMenu insertItem:skipCommercialsItem atIndex:0];
			//			[simulEncodeItem setEnabled:YES];
		}
		
		if (canMark) {
			markCommecialsItem = [[NSMenuItem alloc] init];
			markCommecialsItem.title = @"Mark Commercials";
			[markCommecialsItem bind:@"value" toObject:defaults withKeyPath:kMTMarkCommercials options:nil];
			[optionsMenu insertItem:markCommecialsItem atIndex:0];
			//			[simulEncodeItem setEnabled:YES];
		}
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
	self.tiVoGlobalManager.processingPaused = [self.tiVoGlobalManager.processingPaused boolValue] ? @(NO) : @(YES);
	DDLogDetail(@"User toggled Pause %@", self.tiVoGlobalManager.processingPaused);
	//	pauseMenuItem.title = [self.tiVoGlobalManager.processingPaused boolValue] ? @"Resume Queue" : @"Pause Queue";
	if ([self.tiVoGlobalManager.processingPaused boolValue]) {
		[self.tiVoGlobalManager pauseQueue:@(YES)];
	} else {
		[self.tiVoGlobalManager unPauseQueue];
	}
	
}

-(void)updateTivoRefreshMenu
{
	DDLogDetail(@"Rebuilding TivoRefresh Menu");
	DDLogVerbose(@"Tivos: %@",_tiVoGlobalManager.tiVoList);
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
	[[mainWindowController tiVoShowTable] findShows:sender];
}

- (IBAction)clearHistory:(id)sender {
	[[mainWindowController downloadQueueTable] clearHistory:sender];
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
		DDLogDetail(@"Got new Subscription %@",input.stringValue);
		MTSubscription * sub = [[tiVoManager subscribedShows] addSubscriptionsString:input.stringValue];
		if (!sub) {
			NSAlert * badSub = [NSAlert alertWithMessageText:@"Invalid Subscription" defaultButton:@"Cancel" alternateButton:@"" otherButton:nil informativeTextWithFormat:@"The subscription pattern may be badly formed, or it may already covered by another subscription."];
			[badSub runModal];
		}
	}
}

-(IBAction)editManualTiVos:(id)sender
{
	//	[self.manualTiVoEditorController showWindow:nil];
	//	[NSApp beginSheet:self.manualTiVoEditorController.window modalForWindow:mainWindowController.window modalDelegate:nil didEndSelector:NULL contextInfo:nil];
	self.preferencesController.startingTabIdentifier = @"TiVos";
	[self showPreferences:nil];
}

-(IBAction)showPreferences:(id)sender
{
	[NSApp beginSheet:self.preferencesController.window modalForWindow:mainWindowController.window modalDelegate:nil didEndSelector:NULL contextInfo:nil];
	
}

-(IBAction)showAdvPreferences:(id)sender
{
	[NSApp beginSheet:self.advPreferencesController.window modalForWindow:mainWindowController.window modalDelegate:nil didEndSelector:NULL contextInfo:nil];
}

-(MTPreferencesWindowController *)preferencesController;
{
	if (!_preferencesController) {
		_preferencesController = [[MTPreferencesWindowController alloc] initWithWindowNibName:@"MTPreferencesWindowController"];
	}
	return _preferencesController;
}

-(MTPreferencesWindowController *)advPreferencesController;
{
	if (!_advPreferencesController) {
		_advPreferencesController = [[MTPreferencesWindowController alloc] initWithWindowNibName:@"MTPreferencesWindowController"];
		[_advPreferencesController window];
		MTTabViewItem *advTabViewItem = [[MTTabViewItem alloc] initWithIdentifier:@"AdvPrefs"];
		advTabViewItem.label = @"Advanced Preferences";
		NSViewController *thisController = [[MTAdvPreferencesViewController alloc] initWithNibName:@"MTAdvPreferencesViewController" bundle:nil];
        [thisController loadView];
		advTabViewItem.windowController = (id)thisController;
		[_advPreferencesController.myTabView insertTabViewItem:advTabViewItem atIndex:0];
		NSRect tabViewFrame = ((NSView *)advTabViewItem.view).frame;
		NSRect editorViewFrame = thisController.view.frame;
		[thisController.view setFrameOrigin:NSMakePoint((tabViewFrame.size.width - editorViewFrame.size.width)/2.0, tabViewFrame.size.height - editorViewFrame.size.height)];
		[advTabViewItem.view addSubview:thisController.view];
        [_advPreferencesController.window setFrame:[_advPreferencesController getNewWindowRect:advTabViewItem] display:NO];
		_advPreferencesController.ignoreTabItemSelection = YES;
		[_advPreferencesController.myTabView selectTabViewItem:advTabViewItem];
		_advPreferencesController.ignoreTabItemSelection = NO;;
	}
	return _advPreferencesController;
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
	[mySavePanel beginWithCompletionHandler:^(NSInteger result){
		if (result == NSFileHandlingPanelOKButton) {
			NSMutableArray *formatsToWrite = [NSMutableArray array];
			for (int i = 0; i < _tiVoGlobalManager.userFormats.count; i++) {
				//Get selected formats
				NSButton *checkbox = [exportTableView viewAtColumn:0 row:i makeIfNecessary:NO];
				if (checkbox.state) {
					[formatsToWrite addObject:[_tiVoGlobalManager.userFormats[i] toDictionary]];
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
	
	NSOpenPanel *myOpenPanel = [[NSOpenPanel alloc] init];
	[myOpenPanel setTitle:@"Import User Formats"];
	[myOpenPanel setAllowedFileTypes:@[@"plist",@"enc"]];
	[myOpenPanel beginWithCompletionHandler:^(NSInteger ret){
		NSArray *newFormats = nil;
		if (ret == NSFileHandlingPanelOKButton) {
			NSString *filename = myOpenPanel.URL.path;
			if ([[[filename pathExtension ]lowercaseString] isEqual: @"plist"]) {
				newFormats = [NSArray arrayWithContentsOfFile:filename];
				[_tiVoGlobalManager addFormatsToList:newFormats];
			} else {
				[_tiVoGlobalManager addEncFormatToList:filename];
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
        NSAlert *keyAlert = [NSAlert alertWithMessageText:message defaultButton:@"New Key" alternateButton:@"Ignore TiVo" otherButton:nil informativeTextWithFormat:@""];
        NSView *accView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 300, 50)];
        NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(10, 14, 200, 24)];
        [accView addSubview:input];
        NSButton *helpButton = [NSButton new];
        [helpButton setButtonType:NSMomentaryPushInButton];
        [helpButton setBezelStyle:NSRoundedBezelStyle];
        [helpButton setTitle:@"Help"];
        [helpButton sizeToFit];
        [helpButton setFrame:NSMakeRect(220, 13, 70, 24) ];
        [helpButton setTarget:self];
        [helpButton setAction:@selector(help:)];
        [accView addSubview:helpButton];
        
        [input setStringValue:tiVo.mediaKey];
        [keyAlert setAccessoryView:accView];
        NSInteger button = [keyAlert runModal];
        if (button == NSAlertDefaultReturn) {
            [input validateEditing];
            DDLogDetail(@"Got Media Key %@",input.stringValue);
            tiVo.mediaKey = input.stringValue;
 			tiVo.enabled = YES;
			[tiVo updateShows:nil];
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

-(NSAlert *)alertWithMessage:(NSString *)message andTiVo:(MTTiVo *)tiVo
{
    NSAlert *keyAlert = [NSAlert alertWithMessageText:message defaultButton:@"New Key" alternateButton:@"Ignore TiVo" otherButton:nil informativeTextWithFormat:@""];
    NSView *accView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 300, 50)];
    NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(10, 14, 200, 24)];
    [accView addSubview:input];
    NSButton *helpButton = [NSButton new];
    [helpButton setButtonType:NSMomentaryPushInButton];
    [helpButton setBezelStyle:NSRoundedBezelStyle];
    [helpButton setTitle:@"Help"];
    [helpButton sizeToFit];
    [helpButton setFrame:NSMakeRect(220, 13, 70, 24) ];
    [helpButton setTarget:self];
    [helpButton setAction:@selector(help:)];
    [accView addSubview:helpButton];
    
    [input setStringValue:tiVo.mediaKey];
    [keyAlert setAccessoryView:accView];
    return keyAlert;

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
	if (!mainWindowController) {
		mainWindowController = [[MTMainWindowController alloc] initWithWindowNibName:@"MTMainWindowController"];
		showInFinderMenuItem.target = mainWindowController;
		showInFinderMenuItem.action = @selector(revealInFinder:);
		playVideoMenuItem.target = mainWindowController;
		playVideoMenuItem.action = @selector(playVideo:);
		mainWindowController.showInFinderMenuItem = showInFinderMenuItem;
		mainWindowController.playVideoMenuItem = playVideoMenuItem;
	}
	[mainWindowController showWindow:nil];
	
}

-(void) checkDone:(id) sender {
	DDLogVerbose(@"Checking done");
	if ( ![tiVoManager anyTivoActive] ){
		DDLogDetail(@"Checking finished");
		[checkingDone invalidate]; checkingDone = nil;
		[NSApp endSheet: [mainWindowController window]];
		[self cleanup];
		[NSApp replyToApplicationShouldTerminate:YES];
	}
}

//-(void) doQuit {
//	[checkingDone invalidate]; checkingDone = nil;
//	[NSApp replyToApplicationShouldTerminate:NO];
//}

-(void) confirmUserQuit {
	NSString *message = [NSString stringWithFormat:@"Shows are in process, and would need to be restarted next time. Do you wish them to finish now, or quit immediately?"];
	NSAlert *quitAlert = [NSAlert alertWithMessageText:message defaultButton:@"Finish current show" alternateButton:@"Cancel" otherButton:@"Quit Immediately" informativeTextWithFormat:@""];
	NSInteger returnValue = [quitAlert runModal];
	switch (returnValue) {
		case NSAlertDefaultReturn:
			DDLogDetail(@"User did ask to continue");
			tiVoManager.processingPaused = @(YES);
			tiVoManager.quitWhenCurrentDownloadsComplete = @(YES);
			[mainWindowController.cancelQuitView setHidden:NO];
			[NSApp replyToApplicationShouldTerminate:NO];
			
			//			NSRunLoop* myRunLoop = [NSRunLoop currentRunLoop];
			//			// Create and schedule the  timer.
			//			NSDate* futureDate = [NSDate dateWithTimeIntervalSinceNow:5.0];
			//			checkingDone = [[[NSTimer alloc] initWithFireDate:futureDate
			//														interval:5.0
			//														  target:self
			//														selector:@selector(checkDone:)
			//														userInfo:nil
			//														 repeats:YES] autorelease];
			//			[myRunLoop addTimer:checkingDone forMode:NSRunLoopCommonModes];
			//
			//			NSString *message = [NSString stringWithFormat:@"Please wait for processing to complete..."];
			//			NSAlert *quitAlert = [NSAlert alertWithMessageText:message defaultButton:@"Cancel Quit" alternateButton:nil otherButton:nil informativeTextWithFormat:@""];
			//			[quitAlert beginSheetModalForWindow:mainWindowController.window modalDelegate:self didEndSelector:@selector(doQuit) contextInfo:nil ];
			break;
		case NSAlertOtherReturn:
			DDLogDetail(@"User did ask to quit");
			[self cleanup];
			[NSApp replyToApplicationShouldTerminate:YES];
			break;
		case NSAlertAlternateReturn:
		default:
			[NSApp replyToApplicationShouldTerminate:NO];
			break;
	}
}

-(void) cleanup {
	
	DDLogDetail(@"exiting");
	[saveQueueTimer invalidate];
	[tiVoManager cancelAllDownloads];
	[tiVoManager writeDownloadQueueToUserDefaults];
    [[NSUserDefaults standardUserDefaults] setObject:tiVoManager.tvdbCache forKey:kMTTheTVDBCache];
	 mediaKeyQueue = nil;
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender
{
	if ([tiVoManager anyTivoActive] && ![[NSUserDefaults standardUserDefaults] boolForKey:kMTQuitWhileProcessing] && sender ) {
		[self performSelectorOnMainThread:@selector(confirmUserQuit) withObject:nil waitUntilDone:NO];
		return NSTerminateLater;
	} else {
		[self cleanup];
		return NSTerminateNow;
	}
}

@end
