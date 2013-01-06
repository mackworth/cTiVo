//
//  MTAppDelegate.m
//  myTivo
//
//  Created by Scott Buchanan on 12/6/12.
//  Copyright (c) 2012 Scott Buchanan. All rights reserved.
//

#import "MTAppDelegate.h"
#import "MTTiVo.h"

@implementation MTAppDelegate

- (void)dealloc
{
	[tiVoGlobalManager release];
    [super dealloc];
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    // Insert code here to initialize your application
	
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateTivoRefreshMenu) name:kMTNotificationTiVoListUpdated object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(getMediaKeyFromUser:) name:kMTNotificationMediaKeyNeeded object:nil];
	tiVoGlobalManager = [MTTiVoManager sharedTiVoManager];
	mainWindowController = nil;
	[self showMainWindow:nil];
	[self updateTivoRefreshMenu];
	mediaKeyQueue = [NSMutableArray new];
	gettingMediaKey = NO;
}

#pragma mark - UI support

-(void)updateTivoRefreshMenu
{
	if (tiVoGlobalManager.tiVoList.count == 0) {
		[refreshTiVoMenuItem setEnabled:NO];
	} else if (tiVoGlobalManager.tiVoList.count ==1) {
		[refreshTiVoMenuItem setTarget:tiVoGlobalManager.tiVoList[0]];
		[refreshTiVoMenuItem setAction:@selector(updateShows:)];
		[refreshTiVoMenuItem setEnabled:YES];
	} else {
		NSSortDescriptor *sd = [NSSortDescriptor sortDescriptorWithKey:@"tiVo.name" ascending:YES];
		NSArray *sortedTiVos = [[NSArray arrayWithArray:tiVoGlobalManager.tiVoList] sortedArrayUsingDescriptors:[NSArray arrayWithObject:sd]];
		NSMenu *thisMenu = [[[NSMenu alloc] initWithTitle:@"Refresh Tivo"] autorelease];
		for (MTTiVo *tiVo in sortedTiVos) {
			NSMenuItem *thisMenuItem = [[[NSMenuItem alloc] initWithTitle:tiVo.tiVo.name action:NULL keyEquivalent:@""] autorelease];
			[thisMenuItem setTarget:tiVo];
			[thisMenuItem setAction:@selector(updateShows:)];
			[thisMenuItem setEnabled:YES];
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
	if ( tiVo.mediaKey.length == 0 && tiVoGlobalManager.tiVoList.count && tiVo != (MTTiVo *)[tiVoGlobalManager.tiVoList objectAtIndex:0]) {
		tiVo.mediaKey = ((MTTiVo *)[tiVoGlobalManager.tiVoList objectAtIndex:0]).mediaKey;
		[mediaKeyQueue removeObject:tiVo];
		NSLog(@"set key for tivo %@ to %@",tiVo.tiVo.name,tiVo.mediaKey);
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
    return [appSupportURL URLByAppendingPathComponent:@"com.cTiVo.cTivo"];
}

-(IBAction)closeMainWindow:(id)sender
{
    [mainWindowController close];
}

-(IBAction)showMainWindow:(id)sender
{
	if (!mainWindowController) {
		mainWindowController = [[MTMainWindowController alloc] initWithWindowNibName:@"MTMainWindowController"];
	}
	[mainWindowController showWindow:nil];
	
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender
{
    // Save changes in the application's user defaults before the application terminates.
    [[NSUserDefaults standardUserDefaults] synchronize];
	[mediaKeyQueue release];
    return NSTerminateNow;
}

@end
