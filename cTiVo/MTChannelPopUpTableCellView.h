//
//  MTFormatPopUpTableCellView.h
//  cTiVo
//
//  Created by Scott Buchanan on 1/4/13.
//  Copyright (c) 2013 Scott Buchanan. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "MTChannelPopUpButton.h"

@interface MTChannelPopUpTableCellView : NSTableCellView

@property (strong, nonatomic, readonly) MTChannelPopUpButton *popUpButton;

- (id)initWithFrame:(NSRect)frame withTarget:(id)target withAction:(SEL)selector;

@end
