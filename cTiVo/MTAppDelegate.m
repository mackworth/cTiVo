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
	[myTiVos release];
    [super dealloc];
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    // Insert code here to initialize your application
	myTiVos = [[MTNetworkTivos alloc] init];
	mainWindowController = nil;
	[self showMainWindow:nil];
}

// Returns the directory the application uses to store the Core Data store file. This code uses a directory named "com.fawkesconsulting.-.myTivo" in the user's Application Support directory.
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
		mainWindowController = [[MTMainWindowController alloc] initWithWindowNibName:@"MTMainWindowController" withNetworkTivos:myTiVos];
	}
	[mainWindowController showWindow:nil];
	
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender
{
    // Save changes in the application's managed object context before the application terminates.

    return NSTerminateNow;
}

@end
