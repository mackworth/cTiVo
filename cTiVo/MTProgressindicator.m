//
//  MTProgressindicator.m
//  cTiVo
//
//  Created by Scott Buchanan on 12/12/12.
//  Copyright (c) 2012 Scott Buchanan. All rights reserved.
//

#import "MTProgressindicator.h"


@implementation MTProgressindicator

- (id)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        // Initialization code here.
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

-(void) setFrame: (NSRect) frame {
	[super setFrame:frame];
	if (_rightText.hidden) {
		_leftText.frame = CGRectMake(0, 0, self.bounds.size.width, self.frame.size.height);
	} else {
		int widthStatusField  = 100;
		if (_leftText.stringValue.length == 0) {
			widthStatusField = self.frame.size.width;
		}
		_leftText.frame = CGRectMake(0, 0, self.frame.size.width - widthStatusField, self.frame.size.height);
		_rightText.frame = CGRectMake(self.frame.size.width - widthStatusField, 0, widthStatusField, self.frame.size.height);
	}
}

- (void)setItemPropertiesToDefault:sender {
    self.displayProgress = YES;

	_foregroundTextColor = [NSColor textColor];
	self.leftText.backgroundColor = [NSColor clearColor];
	self.rightText.backgroundColor = [NSColor clearColor];

    _doubleValue = 0.0;
    _barColor = [NSColor colorWithCalibratedRed:1.0 green:.61 blue:.45 alpha:0.60];
    [self setAutoresizingMask:NSViewWidthSizable  ];
}

- (void)drawRect:(NSRect)dirtyRect {
    if (self.displayProgress) {
        NSBezierPath *thisPath = [NSBezierPath bezierPathWithRect:CGRectMake(0, 0, self.frame.size.width * _doubleValue, self.frame.size.height)];
        [_barColor set];
        [thisPath fill];
    }
}

-(void)setDoubleValue:(double)doubleValue {
	_doubleValue = doubleValue;
	[self setNeedsDisplay:YES];
}


-(void) setDisplayProgress: (BOOL) displayProgress {
    if (displayProgress != _displayProgress) {
        _displayProgress = displayProgress;
		_rightText.hidden = !displayProgress;
		[self setFrame:self.frame];
        [self setNeedsDisplay:YES];
    }
}

@end
