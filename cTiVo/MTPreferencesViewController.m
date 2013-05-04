//
//  MTPreferencesViewController.m
//  cTiVo
//
//  Created by Scott Buchanan on 1/27/13.
//  Copyright (c) 2013 Scott Buchanan. All rights reserved.
//

#import "MTPreferencesViewController.h"

@interface MTPreferencesViewController ()

@end

@implementation MTPreferencesViewController

-(IBAction)setDebugLevel:(id)sender {
	[DDLog setAllClassesLogLevelFromUserDefaults: kMTDebugLevel];
}

-(IBAction)selectTmpDir:(id)sender
{
	NSOpenPanel *myOpenPanel = [[NSOpenPanel alloc] init];
	myOpenPanel.canChooseFiles = NO;
	myOpenPanel.canChooseDirectories = YES;
	myOpenPanel.canCreateDirectories = YES;
	myOpenPanel.prompt = @"Choose";
	[myOpenPanel setTitle:@"Select Temp Directory for Files"];
	[myOpenPanel beginSheetModalForWindow:self.view.window completionHandler:^(NSInteger ret){
		if (ret == NSFileHandlingPanelOKButton) {
			NSString *directoryName = myOpenPanel.URL.path;
			[[NSUserDefaults standardUserDefaults] setObject:directoryName forKey:kMTTmpFilesDirectory];
		}
		[myOpenPanel close];
	}];
	
}

@end
