//
//  MTFormatEditorController.h
//  cTiVo
//
//  Created by Scott Buchanan on 1/12/13.
//  Copyright (c) 2013 Scott Buchanan. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "MTFormat.h"


@interface MTFormatEditorController : NSWindowController <NSWindowDelegate> {
	IBOutlet NSPopUpButton *formatPopUpButton;
	NSAlert *deleteAlert, *saveOrCancelAlert, *cancelAlert;
    IBOutlet NSButton *cancelButton, *saveButton;
}

@property (nonatomic, retain) MTFormat *currentFormat;
@property (nonatomic, retain) NSMutableArray *formatList;
@property (nonatomic, retain) NSNumber *shouldSave;

@end
