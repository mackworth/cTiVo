//
//  MTFormatEditorController.h
//  cTiVo
//
//  Created by Scott Buchanan on 1/12/13.
//  Copyright (c) 2013 Scott Buchanan. All rights reserved.
//

#import "MTTabViewItem.h"

@interface MTFormatEditorController : NSViewController <NSPopoverDelegate, MTTabViewItemControllerDelegate> 

@property (nonatomic, readonly) BOOL allowImportExport;
@end
