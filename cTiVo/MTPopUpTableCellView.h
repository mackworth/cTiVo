//
//  MTPopUpTableCellView.h
//  cTiVo
//
//  Created by Scott Buchanan on 1/4/13.
//  Copyright (c) 2013 Scott Buchanan. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "MTFormatPopUpButton.h"

@interface MTPopUpTableCellView : NSTableCellView

@property (strong, nonatomic, readonly) MTFormatPopUpButton *popUpButton;

- (id)initWithFrame:(NSRect)frame withTarget:(id)target withAction:(SEL)selector;

@end
