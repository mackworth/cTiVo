//
//  MTPreferencesControllerWindowController.h
//  cTiVo
//
//  Created by Scott Buchanan on 1/26/13.
//  Copyright (c) 2013 Scott Buchanan. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "MTManualTiVoEditorController.h"
#import "MTFormatEditorController.h"
#import "MTTabViewItem.h"
#import "MTAdvPreferencesViewController.h"


@interface MTPreferencesWindowController : NSWindowController <NSTabViewDelegate> {
	IBOutlet MTManualTiVoEditorController *manualTiVoEditorController;
	IBOutlet MTFormatEditorController *formatEditorController;
}

@property (nonatomic, strong) NSString *startingTabIdentifier;
@property (nonatomic, strong) IBOutlet NSTabView *myTabView;
@property BOOL ignoreTabItemSelection;
@property (nonatomic, strong) IBOutlet MTAdvPreferencesViewController * advPreferencesViewController;
-(NSRect)getNewWindowRect:(MTTabViewItem *)tabViewItem;


@end
