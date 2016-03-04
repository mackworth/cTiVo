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
-(IBAction) testAllChannels:(id) sender;
-(IBAction) removeAllTests:(id) sender;


@end

@implementation MTChannelEditorController

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
@end
