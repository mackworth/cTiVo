//
//  MTDownloadListCheckCell.h
//  cTiVo
//
//  Created by Scott Buchanan on 12/20/12.
//  Copyright (c) 2012 Scott Buchanan. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "MTCheckBox.h"

@interface MTDownloadCheckTableCell : NSTableCellView

@property (strong, nonatomic, readonly) MTCheckBox *checkBox;

- (id)initWithFrame:(NSRect)frame withTarget:(id)target withAction:(SEL)selector;


@end
