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
		_popUpButton = [[[MTPopUpButton alloc] initWithFrame:NSMakeRect(4, 4, frame.size.width-8, 20) pullsDown:NO] autorelease];
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
