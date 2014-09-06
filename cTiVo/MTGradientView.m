//
//  MTGradientView.m
//  cTiVo
//
//  Created by Hugh Mackworth on 9/4/14.
//  Copyright (c) 2014 cTiVo. All rights reserved.
//

#import "MTGradientView.h"

@implementation MTGradientView

- (id)initWithFrame:(NSRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        // Initialization code here.
        [self setStartingColor:[NSColor colorWithCalibratedWhite:1.0 alpha:1.0]];
        [self setEndingColor:nil];
        [self setAngle:270];
    }
    return self;
}

- (void)drawRect:(NSRect)dirtyRect
{
    [super drawRect:dirtyRect];
    if (_endingColor == nil || [_startingColor isEqual:_endingColor]) {
        // Fill view with a standard background color
        [_startingColor set];
        NSRectFill(dirtyRect);
    } else {
          // Fill view with a top-down gradient
        // from startingColor to endingColor
        NSLog(@"dirtyRect: %@",NSStringFromRect(dirtyRect));
        NSGradient* aGradient = [[NSGradient alloc]
                                 initWithStartingColor:_startingColor
                                 endingColor:_endingColor];
        [aGradient drawInRect:[self bounds] angle:_angle];
        
    }
}

@end
