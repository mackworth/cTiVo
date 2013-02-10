//
//  MTFormatEditorController.h
//  cTiVo
//
//  Created by Scott Buchanan on 1/12/13.
//  Copyright (c) 2013 Scott Buchanan. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "MTFormat.h"
#import "MTHelpViewController.h"
#import "MTTiVoShow.h"
#import "MTTabViewItem.h"

@class MTFormatPopUpButton;

@interface MTFormatEditorController : NSViewController <NSPopoverDelegate, MTTabViewItemControllerDelegate> {
	IBOutlet MTFormatPopUpButton *formatPopUpButton;
	NSAlert *deleteAlert, *saveOrCancelAlert, *cancelAlert;
    IBOutlet NSButton *cancelButton, *saveButton, *encodeHelpButton, *comSkipHelpButton;
	NSPopover *myPopover;
	IBOutlet NSWindow *popoverDetachWindow;
	IBOutlet MTHelpViewController *popoverDetachController, *helpContoller;
}

@property (nonatomic, retain) MTFormat *currentFormat;
@property (nonatomic, retain) NSMutableArray *formatList;
@property (nonatomic, retain) NSNumber *shouldSave;
@property (nonatomic, retain) NSColor *validExecutableColor;
@property (nonatomic, retain) NSNumber *validExecutable;
@property (nonatomic, retain) NSString *validExecutableString;


@end
