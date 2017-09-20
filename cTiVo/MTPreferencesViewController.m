//
//  MTPreferencesViewController.m
//  cTiVo
//
//  Created by Scott Buchanan on 1/27/13.
//  Copyright (c) 2013 Scott Buchanan. All rights reserved.
//

#import "MTPreferencesViewController.h"
#import "MTTiVoManager.h"

@interface MTPreferencesViewController ()

@end

@implementation MTPreferencesViewController

-(IBAction)setDebugLevel:(id)sender {
	[DDLog setAllClassesLogLevelFromUserDefaults: kMTDebugLevel];
}

-(BOOL) validateMenuItem:(NSMenuItem *)menuItem {
    if ([menuItem.title isEqualToString: @"TiVo"]) {
        for (MTTiVo *tiVo in tiVoManager.tiVoList) {
            if (tiVo.supportsRPC) return YES;
        }
        return NO;
    }
    return YES;
}

@end
