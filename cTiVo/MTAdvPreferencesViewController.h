//
//  MTAdvPreferencesViewController.h
//  cTiVo
//
//  Created by Hugh Mackworth on 2/7/13.
//  Copyright (c) 2013 Scott Buchanan. All rights reserved.
//

#import "MTPreferencesViewController.h"

@interface MTAdvPreferencesViewController : MTPreferencesViewController
@property (weak) IBOutlet NSView *debugLevelView;
@property (weak) IBOutlet NSPopUpButton *masterDebugLevel;

-(IBAction) newMasterValue:(id) sender;

@end
