//
//  MTAppDelegate.m
//  myTivo
//
//  Created by Scott Buchanan on 12/6/12.
//  Copyright (c) 2012 Scott Buchanan. All rights reserved.
//

#import "MTAppDelegate.h"
#import "MTTiVo.h"
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
			for (MTTiVoShow *s in tiVoManager.downloadQueue) {
				[s cancel];
			}
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
	NSLog(@"Got signal %d",signal);
}

@implementation MTAppDelegate

__DDLOGHERE__

- (void)dealloc
{
	DDLogDetail(@"deallocing AppDelegate");
	[tiVoGlobalManager release];
    [super dealloc];
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
	[[NSUserDefaults standardUserDefaults]  registerDefaults:@{kMTDebugLevel: @1}];

	[DDLog setAllClassesLogLevelFromUserDefaults:kMTDebugLevel];
	
	// Insert code here to initialize your application
	DDLogDetail(@"Starting Program");
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateTivoRefreshMenu) name:kMTNotificationTiVoListUpdated object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(getMediaKeyFromUser:) name:kMTNotificationMediaKeyNeeded object:nil];
	if (![[[NSUserDefaults standardUserDefaults] objectForKey:kMTPreventSleep] boolValue]) {
		[[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithBool:NO] forKey:kMTPreventSleep];
	}
	if (![[[NSUserDefaults standardUserDefaults] objectForKey:kMTShowCopyProtected] boolValue]) {
		[[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithBool:NO] forKey:kMTShowCopyProtected];
	}
	tiVoGlobalManager = [MTTiVoManager sharedTiVoManager];
    [tiVoGlobalManager addObserver:self forKeyPath:@"selectedFormat" options:NSKeyValueChangeSetting context:nil];
	mainWindowController = nil;
//	_formatEditorController = nil;
	[self showMainWindow:nil];
	[self updateTivoRefreshMenu];
	mediaKeyQueue = [NSMutableArray new];
	gettingMediaKey = NO;
	signal(SIGPIPE, &signalHandler);
	signal(SIGABRT, &signalHandler );
    
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
}

-(void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
	if ([keyPath compare:@"selectedFormat"] == NSOrderedSame) {
		DDLogDetail(@"Selecting Format");
		BOOL caniTune = [tiVoManager.selectedFormat.iTunes boolValue];
        BOOL canSimulEncode = ![tiVoManager.selectedFormat.mustDownloadFirst boolValue];
		NSArray *menuItems = [optionsMenu itemArray];
		for (NSMenuItem *mi in menuItems) {
			if ([mi isSeparatorItem]) {
				break;
			}
			[optionsMenu removeItem:mi];
		}
		NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
		if (caniTune) {
			iTunesMenuItem = [[[NSMenuItem alloc] init] autorelease];
			iTunesMenuItem.title = @"Add to iTunes when complete";
			[iTunesMenuItem bind:@"value" toObject:defaults withKeyPath:@"iTunesSubmit" options:nil];
			[optionsMenu insertItem:iTunesMenuItem atIndex:0];
			//			[simulEncodeItem setEnabled:YES];
		}
		if (canSimulEncode) {
			simulEncodeItem = [[[NSMenuItem alloc] init] autorelease];
			simulEncodeItem.title = @"Simultaneous Encoding";
			[simulEncodeItem bind:@"value" toObject:defaults withKeyPath:@"SimultaneousEncode" options:nil];
			[optionsMenu insertItem:simulEncodeItem atIndex:0];
			//			[simulEncodeItem setEnabled:YES];
		}
	}
}

#pragma mark - UI support

-(void)updateTivoRefreshMenu
{
	DDLogDetail(@"Rebuilding TivoRefresh Menu");
	DDLogVerbose(@"Tivos: %@",tiVoGlobalManager.tiVoList);
	if (tiVoGlobalManager.tiVoList.count == 0) {
		[refreshTiVoMenuItem setEnabled:NO];
	} else if (tiVoGlobalManager.tiVoList.count ==1) {
		[refreshTiVoMenuItem setTarget:nil];
		[refreshTiVoMenuItem setAction:NULL];
		if (((MTTiVo *)tiVoGlobalManager.tiVoList[0]).isReachable) {
			[refreshTiVoMenuItem setTarget:tiVoGlobalManager.tiVoList[0]];
			[refreshTiVoMenuItem setAction:@selector(updateShows:)];
			[refreshTiVoMenuItem setEnabled:YES];
		} else  {
			[refreshTiVoMenuItem setEnabled:NO];
		}
	} else {
		[refreshTiVoMenuItem setTarget:tiVoGlobalManager];
		[refreshTiVoMenuItem setAction:@selector(refreshAllTiVos)];
		[refreshTiVoMenuItem setEnabled:YES];
		NSMenu *thisMenu = [[[NSMenu alloc] initWithTitle:@"Refresh Tivo"] autorelease];
		BOOL lastTivoWasManual = NO;
		for (MTTiVo *tiVo in tiVoGlobalManager.tiVoList) {
			if (!tiVo.manualTiVo && lastTivoWasManual) { //Insert a separator
				NSMenuItem *menuItem = [NSMenuItem separatorItem];
				[thisMenu addItem:menuItem];
			}
			lastTivoWasManual = tiVo.manualTiVo;
			NSMenuItem *thisMenuItem = [[[NSMenuItem alloc] initWithTitle:tiVo.tiVo.name action:NULL keyEquivalent:@""] autorelease];
			if (!tiVo.isReachable) {
				NSFont *thisFont = [NSFont systemFontOfSize:13];
				NSString *thisTitle = [NSString stringWithFormat:@"%@ offline",tiVo.tiVo.name];
				NSAttributedString *aTitle = [[[NSAttributedString alloc] initWithString:thisTitle attributes:[NSDictionary dictionaryWithObjectsAndKeys:[NSColor redColor], NSForegroundColorAttributeName, thisFont, NSFontAttributeName, nil]] autorelease];
				[thisMenuItem setAttributedTitle:aTitle];
			} else {
				[thisMenuItem setTarget:tiVo];
				[thisMenuItem setAction:@selector(updateShows:)];
				[thisMenuItem setEnabled:YES];
			}
			[thisMenu addItem:thisMenuItem];
		}
		NSMenuItem *thisMenuItem = [[[NSMenuItem alloc] initWithTitle:@"All TiVos" action:NULL keyEquivalent:@""] autorelease];
		[thisMenuItem setTarget:self];
		[thisMenuItem setAction:@selector(updateAllTiVos:)];
		[thisMenuItem setEnabled:YES];
		[thisMenu addItem:thisMenuItem];
		[refreshTiVoMenuItem setSubmenu:thisMenu];
		[refreshTiVoMenuItem setEnabled:YES];
	}
	return;
	
}

-(NSNumber *)numberOfUserFormats
{
	return [NSNumber numberWithInteger:tiVoGlobalManager.userFormats.count];
}

-(IBAction)editFormats:(id)sender
{
//	[self.formatEditorController showWindow:nil];
	self.preferencesController.startingTabIdentifier = @"Formats";
	[self showPreferences:nil];
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

-(IBAction)exportFormats:(id)sender
{
	NSSavePanel *mySavePanel = [[[NSSavePanel alloc] init] autorelease];
	[mySavePanel setTitle:@"Export User Formats"];
	[mySavePanel setAllowedFileTypes:[NSArray arrayWithObject:@"plist"]];
    [mySavePanel setAccessoryView:formatSelectionTable];
	
	NSInteger ret = [mySavePanel runModal];
	if (ret == NSFileHandlingPanelOKButton) {
        NSMutableArray *formatsToWrite = [NSMutableArray array];
        for (int i = 0; i < tiVoGlobalManager.userFormats.count; i++) {
            //Get selected formats
            NSButton *checkbox = [exportTableView viewAtColumn:0 row:i makeIfNecessary:NO];
            if (checkbox.state) {
                [formatsToWrite addObject:[tiVoGlobalManager.userFormats[i] toDictionary]];
            }
        }
		DDLogVerbose(@"formats: %@",formatsToWrite);
		NSString *filename = mySavePanel.URL.path;
		[formatsToWrite writeToFile:filename atomically:YES];
	}
}

#pragma mark - Table Support Methods

-(NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    return tiVoGlobalManager.userFormats.count;
}

-(CGFloat)tableView:(NSTableView *)tableView heightOfRow:(NSInteger)row
{
    return 17;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
    // get an existing cell with the MyView identifier if it exists
    NSTableCellView *result = [tableView makeViewWithIdentifier:tableColumn.identifier owner:self];
    MTFormat *thisFomat = [tiVoGlobalManager.userFormats objectAtIndex:row];
    // There is no existing cell to reuse so we will create a new one
    if (result == nil) {
        
        // create the new NSTextField with a frame of the {0,0} with the width of the table
        // note that the height of the frame is not really relevant, the row-height will modify the height
        // the new text field is then returned as an autoreleased object
        result = [[[NSTableCellView alloc] initWithFrame:CGRectMake(0, 0, tableView.frame.size.width, 20)] autorelease];
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
	
	NSArray *newFormats = nil;
	NSOpenPanel *myOpenPanel = [[[NSOpenPanel alloc] init] autorelease];
	[myOpenPanel setTitle:@"Import User Formats"];
	[myOpenPanel setAllowedFileTypes:[NSArray arrayWithObject:@"plist"]];
	NSInteger ret = [myOpenPanel runModal];
	if (ret == NSFileHandlingPanelOKButton) {
		NSString *filename = myOpenPanel.URL.path;
		newFormats = [NSArray arrayWithContentsOfFile:filename];
		[tiVoGlobalManager addFormatsToList:newFormats];	
	}
	
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
		MTTabViewItem *advTabViewItem = [[[MTTabViewItem alloc] initWithIdentifier:@"AdvSettinge"] autorelease];
		advTabViewItem.label = @"Advanced Settings";
		NSViewController *thisController = [[[NSViewController alloc] initWithNibName:@"MTAdvPreferencesViewController" bundle:nil] autorelease];
		advTabViewItem.windowController = (id)thisController;
		[_advPreferencesController.myTabView insertTabViewItem:advTabViewItem atIndex:0];
		NSRect tabViewFrame = ((NSView *)advTabViewItem.view).frame;
		NSRect editorViewFrame = thisController.view.frame;
		[thisController.view setFrameOrigin:NSMakePoint((tabViewFrame.size.width - editorViewFrame.size.width)/2.0, tabViewFrame.size.height - editorViewFrame.size.height)];
		[advTabViewItem.view addSubview:thisController.view];
		_advPreferencesController.ignoreTabItemSelection = YES;
		[_advPreferencesController.myTabView selectTabViewItem:advTabViewItem];
		_advPreferencesController.ignoreTabItemSelection = NO;;
 }
	return _advPreferencesController;
}


-(void)updateAllTiVos:(id)sender
{
	for (MTTiVo *tiVo in tiVoGlobalManager.tiVoList) {
		[tiVo updateShows:sender];
	}
}

-(void)getMediaKeyFromUser:(NSNotification *)notification
{
	if (notification && notification.object) {  //If sent a new tiVo then add to queue to start
		[mediaKeyQueue addObject:notification.object];
	}
	if (gettingMediaKey || mediaKeyQueue.count == 0) {  //If we're in the middle of a get or nothing to get return
		return;
	}
	MTTiVo *tiVo = [mediaKeyQueue objectAtIndex:0]; //Pop off the first in the queue
	gettingMediaKey = YES;
	DDLogDetail(@"Getting MAK for %@",tiVo);
	if ( tiVo.mediaKey.length == 0 && tiVoGlobalManager.tiVoList.count && tiVo != (MTTiVo *)[tiVoGlobalManager.tiVoList objectAtIndex:0]) {
		tiVo.mediaKey = ((MTTiVo *)[tiVoGlobalManager.tiVoList objectAtIndex:0]).mediaKey;
		[mediaKeyQueue removeObject:tiVo];
		DDLogDetail(@"Trying key for tivo %@ to %@",tiVo.tiVo.name,tiVo.mediaKey);
		[tiVo updateShows:nil];
	}  else {
		NSString *message = [NSString stringWithFormat:@"Need Media Key for %@",tiVo.tiVo.name];
		if (!tiVo.mediaKeyIsGood && tiVo.mediaKey.length > 0) {
			message = [NSString stringWithFormat:@"Incorrect Media Key for %@",tiVo.tiVo.name];
		}
		NSAlert *keyAlert = [NSAlert alertWithMessageText:message defaultButton:@"New Key" alternateButton:nil otherButton:nil informativeTextWithFormat:@""];
		NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 200, 24)];
		
		[input setStringValue:tiVo.mediaKey];
		[input autorelease];
		[keyAlert setAccessoryView:input];
		NSInteger button = [keyAlert runModal];
		if (button == NSAlertDefaultReturn) {
			[input validateEditing];
			NSLog(@"Got Media Key %@",input.stringValue);
			tiVo.mediaKey = input.stringValue;
			[mediaKeyQueue removeObject:tiVo];
			[tiVo updateShows:nil]; //Assume if needed and got a key we should reload
		}
	}
	gettingMediaKey = NO;
	[[NSUserDefaults standardUserDefaults] setObject:[tiVoGlobalManager currentMediaKeys] forKey:kMTMediaKeys];
	[self getMediaKeyFromUser:nil];//Process rest of queue
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
        tiVoGlobalManager.mainWindow = mainWindowController.window;
	}
	[mainWindowController showWindow:nil];
	
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender
{
    // Save changes in the application's user defaults before the application terminates.
	DDLogDetail(@"exiting");
	[tiVoManager writeDownloadQueueToUserDefaults];
    [[NSUserDefaults standardUserDefaults] synchronize];
	[mediaKeyQueue release];
    return NSTerminateNow;
}

@end
