//
//  MTAdvPreferencesViewController.h
//  cTiVo
//
//  Created by Hugh Mackworth on 2/7/13.
//  Copyright (c) 2013 Scott Buchanan. All rights reserved.
//

#import "MTPreferencesViewController.h"
#import "MTHelpViewController.h"

@interface MTAdvPreferencesViewController : MTPreferencesViewController <NSPopoverDelegate>{
	IBOutlet NSPopover *myPopover;
	IBOutlet NSTextView *myTextView;
	IBOutlet NSWindow *popoverDetachWindow;
	IBOutlet MTHelpViewController *popoverDetachController, *tvdbController;
}

@property (weak) IBOutlet NSView *debugLevelView;
@property (weak) IBOutlet NSPopUpButton *masterDebugLevel;
-(IBAction) newMasterValue:(id) sender;
-(IBAction)selectTmpDir:(id)sender;
-(IBAction)TVDBStatistics:(id)sender;

@end
