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
		NSInteger textIndent = 9;
		CGRect subFramePopUp = NSMakeRect(4, 0, frame.size.width-8, frame.size.height-4);
		CGRect subFrameText = NSMakeRect(4+textIndent, -6, frame.size.width-8-textIndent, frame.size.height);
		NSFont * cellFont = [NSFont systemFontOfSize:[NSFont systemFontSizeForControlSize:NSMiniControlSize]];
		
		_popUpButton = [[[MTFormatPopUpButton alloc] initWithFrame:subFramePopUp pullsDown:NO] autorelease];
 		[_popUpButton setFont: cellFont];
        [_popUpButton.cell setControlSize:NSMiniControlSize];
        [_popUpButton setAutoresizesSubviews:YES];
        [_popUpButton setAutoresizingMask:NSViewWidthSizable];
        [_popUpButton setTarget:target];
        [_popUpButton setAction:selector];
		[self addSubview:_popUpButton];
		
		
		NSTextField * tempTextField = [[[NSTextField alloc] initWithFrame:subFrameText]  autorelease];
		tempTextField.hidden = YES;
		[tempTextField setEditable:NO];

		[tempTextField setBezeled:NO];
		[[tempTextField cell] setLineBreakMode:NSLineBreakByTruncatingTail];
		[tempTextField setAutoresizingMask:NSViewWidthSizable ];
		tempTextField.font = cellFont;
		tempTextField.backgroundColor = [NSColor clearColor];
		[self addSubview:tempTextField ];
		self.textField = tempTextField;
		
		
    }
    
    return self;
}

- (void)setBackgroundStyle:(NSBackgroundStyle)style
{
    [super setBackgroundStyle:style];
	
    // If the cell's text color is black, this sets it to white
	//    [((NSCell *)self.progressIndicator.leftText.cell) setBackgroundStyle:style];
	
    // Otherwise you need to change the color manually
	NSColor *fontColor;
    switch (style) {
        case NSBackgroundStyleLight:
			fontColor = [NSColor colorWithCalibratedWhite:0.0 alpha:1.0];
            break;
			
        case NSBackgroundStyleDark:
        default:
			fontColor = [NSColor colorWithCalibratedWhite:1.0 alpha:1.0];
            break;
    }
	self.textField.textColor = fontColor;
}



- (void)drawRect:(NSRect)dirtyRect
{
    // Drawing code here.
}

@end
