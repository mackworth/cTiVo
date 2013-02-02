//
//  MTHelpViewController.h
//  cTiVo
//
//  Created by Scott Buchanan on 1/14/13.
//  Copyright (c) 2013 Scott Buchanan. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "MTTabViewItem.h"

@interface MTHelpViewController : NSViewController <MTTabViewItemControllerDelegate>

@property (nonatomic, retain) IBOutlet NSTextView *displayMessage;

@end
