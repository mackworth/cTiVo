//
//  MTPopUpTableCellView.m
//  cTiVo
//
//  Created by Scott Buchanan on 1/4/13.
//  Copyright (c) 2013 Scott Buchanan. All rights reserved.
//

#import "MTPopUpTableCellView.h"

@implementation MTPopUpTableCellView

- (id)initWithFrame:(NSRect)frame withTarget:(id)target withAction:(SEL)selector
{
    self = [super initWithFrame:frame];
    if (self) {
        // Initialization code here.
		_popUpButton = [[[MTFormatPopUpButton alloc] initWithFrame:NSMakeRect(4, 2, frame.size.width-8, frame.size.height-4) pullsDown:NO] autorelease];
        [_popUpButton setFont:[NSFont systemFontOfSize:12]];
        [_popUpButton.cell setControlSize:NSMiniControlSize];
        [_popUpButton setAutoresizesSubviews:YES];
        [_popUpButton setAutoresizingMask:NSViewWidthSizable];
        [_popUpButton setTarget:target];
        [_popUpButton setAction:selector];
		[self addSubview:_popUpButton];
    }
    
    return self;
}

- (void)drawRect:(NSRect)dirtyRect
{
    // Drawing code here.
}

@end
