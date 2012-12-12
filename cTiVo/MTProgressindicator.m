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
        _leftText = [[NSTextField alloc] initWithFrame:CGRectMake(0, 0, frame.size.width * 0.8, frame.size.height)];
        [_leftText setBackgroundColor:[NSColor clearColor]];
        [_leftText setEditable:NO];
        [_leftText setBezeled:NO];
        _rightText = [[NSTextField alloc] initWithFrame:CGRectMake(frame.size.width * 0.8, -4, frame.size.width * 0.2, frame.size.height)];
        [_rightText setFont:[NSFont userFontOfSize:10]];
        [_rightText setAlignment:NSRightTextAlignment];
        [_rightText setBackgroundColor:[NSColor clearColor]];
        [_rightText setEditable:NO];
        [_rightText setBezeled:NO];
        [self addSubview:_leftText];
        [self addSubview:_rightText];
        [_leftText release];
        [_rightText release];
        _doubleValue = 0.0;
        _barColor = [[NSColor colorWithCalibratedRed:.7 green:.7 blue:1.0 alpha:1.0] retain];
    }
    
    return self;
}

- (void)drawRect:(NSRect)dirtyRect
{
    NSBezierPath *thisPath = [NSBezierPath bezierPathWithRect:(NSRect)CGRectMake(0, 0, self.frame.size.width * _doubleValue, self.frame.size.height)];
    [_barColor set];
    [thisPath fill];
}

-(void)dealloc
{
    [_barColor release];
    [super dealloc];
}

@end
