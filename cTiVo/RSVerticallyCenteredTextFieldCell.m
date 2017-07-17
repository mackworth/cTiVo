//
//  RSVerticallyCenteredTextField.m
//  RSCommon
//
//  Created by Daniel Jalkut on 6/17/06.
//  Copyright 2006 Red Sweater Software. All rights reserved.
//

#import "RSVerticallyCenteredTextFieldCell.h"

@implementation RSVerticallyCenteredTextFieldCell

- (NSRect)titleRectForBounds:(NSRect)theRect {
    NSRect titleFrame = [super titleRectForBounds:theRect];
    NSSize titleSize = [[self attributedStringValue] size];
    titleFrame.origin.y = theRect.origin.y - .5 + (theRect.size.height - titleSize.height) / 2.0;
    return titleFrame;
}

- (void)drawInteriorWithFrame:(NSRect)cellFrame inView:(NSView *)controlView {
    NSRect titleRect = [self titleRectForBounds:cellFrame];
    [[self attributedStringValue] drawInRect:titleRect];
}


@end
