//
//  MTProgressindicator.m
//  cTiVo
//
//  Created by Scott Buchanan on 12/12/12.
//  Copyright (c) 2012 Scott Buchanan. All rights reserved.
//

#import "MTProgressindicator.h"


@implementation MTProgressindicator

- (id)initWithFrame:(NSRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        // Initialization code here.
        _displayProgress = NO;
        self.leftText = [[NSTextField alloc ] initWithFrame:frame];
        self.rightText =  [[NSTextField alloc ] initWithFrame:CGRectZero] ;
        [self setItemPropertiesToDefault:self ];
    }
    
    return self;
}
-(void) awakeFromNib {
	[super awakeFromNib];
    [self setItemPropertiesToDefault:self];
}


- (void)setItemPropertiesToDefault:sender
{
    self.displayProgress = YES;

    _foregroundTextColor = [NSColor blackColor];
 
    _doubleValue = 0.0;
    _barColor = [NSColor colorWithCalibratedRed:1.0 green:.61 blue:.45 alpha:0.60];
    [self setAutoresizingMask:NSViewWidthSizable  ];
    [self.leftText setAutoresizingMask:NSViewWidthSizable] ;
    [self.rightText setAutoresizingMask:NSViewMinXMargin] ;


}

- (void)drawRect:(NSRect)dirtyRect
{
    if (self.displayProgress) {
        NSBezierPath *thisPath = [NSBezierPath bezierPathWithRect:CGRectMake(0, 0, self.frame.size.width * _doubleValue, self.frame.size.height)];
        [_barColor set];
        [thisPath fill];
    }
}

-(void)setDoubleValue:(double)doubleValue
{
	_doubleValue = doubleValue;
	[self setNeedsDisplay:YES];
}

- (void)setBackgroundStyle:(NSBackgroundStyle)style
{
    [super setBackgroundStyle:style];

    // If the cell's text color is black, this sets it to white
    //    [((NSCell *)self.progressIndicator.leftText.cell) setBackgroundStyle:style];

    // Otherwise you need to change the color manually
    switch (style) {
        case NSBackgroundStyleLight:
            [self.leftText setTextColor:self.foregroundTextColor];
            [self.rightText setTextColor:self.foregroundTextColor];
            break;

        case NSBackgroundStyleDark:
        default:
            [self.leftText setTextColor:[NSColor colorWithCalibratedWhite:1.0 alpha:1.0]];
            [self.rightText setTextColor:[NSColor colorWithCalibratedWhite:1.0 alpha:1.0]];
            break;
    }
}


-(void) setDisplayProgress: (BOOL) displayProgress {
    if (displayProgress != _displayProgress) {
        _displayProgress = displayProgress;
        if (displayProgress) {
			 int widthStatusField  = 70;
			if (_leftText.stringValue.length == 0) {
				widthStatusField = self.frame.size.width;
			}
            _leftText.frame = CGRectMake(0, 0, self.frame.size.width - widthStatusField, self.frame.size.height);
            _rightText.frame = CGRectMake(self.frame.size.width - widthStatusField, 0, widthStatusField, self.frame.size.height);
            _rightText.hidden = NO;
        } else {
            _leftText.frame = CGRectMake(0, 0, self.bounds.size.width, self.frame.size.height);
            _rightText.hidden = YES;
        }
        [self setNeedsDisplay:YES];
    }
}

@end
