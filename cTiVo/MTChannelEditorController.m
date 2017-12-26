//
//  MTChannelEditorController.h
//  cTiVo
//
//  Created by Hugh Mackworth on 2/27/16.
//  Copyright (c) 2016 Hugh Mackworth. All rights reserved.
//


#import "MTChannelEditorController.h"
#import "MTTiVoManager.h"

@interface MTChannelEditorController ()
@property (strong) IBOutlet NSButton *testButton;

-(IBAction) testAllChannels:(id) sender;
-(IBAction) removeAllTests:(id) sender;


@end

@implementation MTChannelEditorController

-(void) viewWillAppear {
    //note: only called in 10.10; older OS will not change button name from Selected
    if ( tiVoManager.allShowsSelected ) {
        self.testButton.title = @"Test All Channels";
    } else {
        self.testButton.title = @"Test Selected Channels";
    }

}

-(BOOL)windowShouldClose:(id)sender {
	[self.view.window makeFirstResponder:self.view]; //This closes out handling editing.
    [tiVoManager removeAllChannelsStartingWith:@"???"];//clean up any extra channels
    [tiVoManager sortChannelsAndMakeUnique];
    return YES;
}

-(IBAction) addChannel:(id)sender {
    NSDictionary * newChannel = @{kMTChannelInfoName: @"???",
                                  kMTChannelInfoCommercials: @(NSOnState),
                                  kMTChannelInfoPSFailed: @(NSMixedState),
                                   kMTChannelInfoUseTS: @(NSMixedState)};

    [tiVoManager createChannel:newChannel];
}

-(void) testAllChannels:(id)sender {
    [tiVoManager testAllChannelsForPS];
}

-(IBAction) removeAllTests:(id) sender {
    [tiVoManager removeAllPSTests];

}

-(IBAction) help:(id)sender {
	[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString: @"https://github.com/dscottbuch/cTiVo/wiki/Advanced-Topics#edit-channels"]];
}


@end
