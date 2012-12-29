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
        const int widthStatusField = 70;
        _leftText = [[NSTextField alloc] initWithFrame:CGRectMake(0, 0, frame.size.width -widthStatusField, frame.size.height)];
        [_leftText setBackgroundColor:[NSColor clearColor]];
        [_leftText setEditable:NO];
        [_leftText setBezeled:NO];
        [_leftText setAutoresizingMask:NSViewWidthSizable ];
        [_leftText setFont: [NSFont systemFontOfSize:13.0f]];
        [_leftText.cell setWraps:NO];
        [[_leftText cell] setLineBreakMode:NSLineBreakByTruncatingTail];
        
        _rightText = [[NSTextField alloc] initWithFrame:CGRectMake(frame.size.width -widthStatusField, 0, widthStatusField, frame.size.height-6)];
        [_rightText setFont:[NSFont userFontOfSize:10]];
        [_rightText setAlignment:NSRightTextAlignment];
        [_rightText setBackgroundColor:[NSColor clearColor]];
        [_rightText setEditable:NO];
        [_rightText setBezeled:NO];
        [_rightText setAutoresizingMask:NSViewMinXMargin ];
        
        [self addSubview:_rightText];
        [self addSubview:_leftText];
        [_leftText release];
        [_rightText release];
        _doubleValue = 0.0;
        _barColor = [[NSColor colorWithCalibratedRed:.7 green:.7 blue:1.0 alpha:1.0] retain];
        [self setAutoresizingMask:NSViewWidthSizable ];

    }
    
    return self;
}

- (void)drawRect:(NSRect)dirtyRect
{
    NSBezierPath *thisPath = [NSBezierPath bezierPathWithRect:CGRectMake(0, 0, self.frame.size.width * _doubleValue, self.frame.size.height)];
    [_barColor set];
    [thisPath fill];
}

-(void)setDoubleValue:(double)doubleValue
{
	_doubleValue = doubleValue;
	[self setNeedsDisplay:YES];
}

-(void)dealloc
{
    [_barColor release];
    [super dealloc];
}

@end
