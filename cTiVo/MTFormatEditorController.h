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

@property (nonatomic, strong) MTFormat *currentFormat;
@property (nonatomic, strong) NSMutableArray *formatList;
@property (nonatomic, strong) NSNumber *shouldSave;
@property (nonatomic, strong) NSColor *validExecutableColor;
@property (nonatomic, strong) NSNumber *validExecutable;
@property (nonatomic, strong) NSString *validExecutableString;


@end
