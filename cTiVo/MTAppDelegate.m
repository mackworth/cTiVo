//
//  MTAppDelegate.m
//  myTivo
//
//  Created by Scott Buchanan on 12/6/12.
//  Copyright (c) 2012 Scott Buchanan. All rights reserved.
//

#import "MTAppDelegate.h"

@implementation MTAppDelegate

- (void)dealloc
{
	[tiVoGlobalManager release];
    [super dealloc];
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    // Insert code here to initialize your application
	tiVoGlobalManager = [MTTiVoManager sharedTiVoManager];
	mainWindowController = nil;
	[self showMainWindow:nil];
}

- (NSURL *)applicationFilesDirectory
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSURL *appSupportURL = [[fileManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask] lastObject];
    return [appSupportURL URLByAppendingPathComponent:@"com.fawkesconsulting.-.myTivo"];
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

    return NSTerminateNow;
}

@end
