//
//  MTPreferencesViewController.h
//  cTiVo
//
//  Created by Scott Buchanan on 1/27/13.
//  Copyright (c) 2013 Scott Buchanan. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "MTTabViewItem.h"

@interface MTPreferencesViewController : NSViewController<MTTabViewItemControllerDelegate>

-(IBAction)setDebugLevel:(id)sender;
-(IBAction)selectTmpDir:(id)sender;

@end
