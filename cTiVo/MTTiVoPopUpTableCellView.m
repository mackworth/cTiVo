//
//  MTTiVoPopUpTableCellView
//  cTiVo
//
//  Created by Hugh Mackworth on 5/22/13.
//  Copyright (c) 2013 Hugh Mackworth. All rights reserved.
//

#import "MTTiVoPopUpTableCellView.h"

@implementation MTTiVoPopUpTableCellView

- (id)initWithFrame:(NSRect)frame withTarget:(id)target withAction:(SEL)selector
{
    self = [super initWithFrame:frame];
    if (self) {
        [self initialSetup];
        [_popUpButton setTarget:target];
        [_popUpButton setAction:selector];

    }
    return self;
}

-(void) awakeFromNib {
	[super awakeFromNib];
    [self initialSetup];
}


-(void) initialSetup {
    NSInteger textIndent = 9;
    CGRect subFramePopUp = NSMakeRect(4, 2, self.frame.size.width-8, self.frame.size.height-4);
    CGRect subFrameText = NSMakeRect(4+textIndent, -6, self.frame.size.width-8-textIndent, self.frame.size.height);
    NSFont * cellFont = [NSFont systemFontOfSize:[NSFont systemFontSizeForControlSize:NSMiniControlSize]];

    _popUpButton = [[MTTiVoPopUpButton alloc] initWithFrame:subFramePopUp pullsDown:NO];
    [_popUpButton setFont: cellFont];
    [_popUpButton.cell setControlSize:NSMiniControlSize];
    [_popUpButton setAutoresizesSubviews:YES];
    [_popUpButton setAutoresizingMask:NSViewWidthSizable ];
    [self addSubview:_popUpButton];


    NSTextField * tempTextField = self.textField;
    if (!tempTextField) {
        tempTextField = [[NSTextField alloc] initWithFrame:subFrameText];
        [self addSubview:tempTextField];
        self.textField = tempTextField;
    } else {
        tempTextField.frame = subFrameText;
    }
    tempTextField.hidden = YES;
    [tempTextField setEditable:NO];

    [tempTextField setBezeled:NO];
    [[tempTextField cell] setLineBreakMode:NSLineBreakByTruncatingTail];
    [tempTextField setAutoresizingMask:NSViewWidthSizable ];
    tempTextField.font = cellFont;
    tempTextField.backgroundColor = [NSColor clearColor];
}

@end
