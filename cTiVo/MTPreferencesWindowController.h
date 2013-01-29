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



@interface MTPreferencesWindowController : NSWindowController <NSTabViewDelegate> {
	IBOutlet MTManualTiVoEditorController *manualTiVoEditorController;
	IBOutlet MTFormatEditorController *formatEditorController;
}

@property (nonatomic, retain) NSString *startingTabIdentifier;
@property (nonatomic, retain) IBOutlet NSTabView *myTabView;
@property BOOL ignoreTabItemSelection;


@end
