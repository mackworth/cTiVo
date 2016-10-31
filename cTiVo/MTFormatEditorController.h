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

@interface MTFormatEditorController : NSViewController <NSPopoverDelegate, MTTabViewItemControllerDelegate> 

@end
