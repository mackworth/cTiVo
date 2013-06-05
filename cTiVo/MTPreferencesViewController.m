//
//  MTPreferencesViewController.m
//  cTiVo
//
//  Created by Scott Buchanan on 1/27/13.
//  Copyright (c) 2013 Scott Buchanan. All rights reserved.
//

#import "MTPreferencesViewController.h"
#import "MTTiVoManager.h"

#define tiVoManager [MTTiVoManager sharedTiVoManager]

@interface MTPreferencesViewController ()

@end

@implementation MTPreferencesViewController

-(IBAction)setDebugLevel:(id)sender {
	[DDLog setAllClassesLogLevelFromUserDefaults: kMTDebugLevel];
}

-(IBAction)emptyCaches:(id)sender
{
    NSAlert *cacheAlert = [NSAlert alertWithMessageText:@"Emptying the Caches will force a reload of all Details from the TiVos and from TheTVDB./nDo you want to continue?" defaultButton:@"Yes" alternateButton:@"No" otherButton:nil informativeTextWithFormat:@""];
    NSInteger returnButton = [cacheAlert runModal];
    if (returnButton != 1) {
        return;
    }
    //Remove TVDB Cache
    [[NSUserDefaults standardUserDefaults] setObject:@{} forKey:kMTTheTVDBCache];
    
    //Remove TiVo Detail Cache
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *files = [fm contentsOfDirectoryAtPath:kMTTmpDetailsDir error:nil];
    for (NSString *file in files) {
        NSString *filePath = [NSString stringWithFormat:@"%@/%@",kMTTmpDetailsDir,file];
        [fm removeItemAtPath:filePath error:nil];
    }
    [tiVoManager resetAllDetails];
    [tiVoManager refreshAllTiVos];
}

@end
