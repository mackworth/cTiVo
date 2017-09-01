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

//XXX Keep TVDB episode Info, but default to TiVo now
//XXXRemove cTiVo artwork option
//XXX Artwork Primary Source:
/*
 None
 TiVo Series
 TVDB Episode
 TVDB Season
 TVDB Series
 */
//implement Season level and prioritization as above
//handle delta changes to showlist
///Test unplugged drive. Pause queue if Tmp not available
// New executables
@end
