//
//  MTChannelEditorController.h
//  cTiVo
//
//  Created by Hugh Mackworth on 2/27/16.
//  Copyright (c) 2016 Hugh Mackworth. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "MTTabViewItem.h"

@interface MTChannelEditorController : NSViewController <MTTabViewItemControllerDelegate> {
	IBOutlet NSArrayController *channelEditorController;
}


@end
