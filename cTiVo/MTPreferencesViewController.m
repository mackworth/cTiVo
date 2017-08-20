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

-(IBAction) changeTVDBPreference:(NSButton *) mySwitch {
    NSAlert *cacheAlert = [NSAlert alertWithMessageText:@"Changing this preference will reload all information from the TiVos and from TheTVDB.\nDo you want to continue?" defaultButton:@"Yes" alternateButton:@"No" otherButton:nil informativeTextWithFormat:@""];
    NSInteger returnButton = [cacheAlert runModal];
    if (returnButton != 1) {
        mySwitch.state = !mySwitch.state ;
        return;
    } else {
        [tiVoManager resetAllDetails];
    }
}

@end
