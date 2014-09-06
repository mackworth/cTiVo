//
//  MTGradientView.h
//  cTiVo
//
//  Created by Hugh Mackworth on 9/4/14.
//  Copyright (c) 2014 cTiVo. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface MTGradientView : NSView

// Define the variables as properties
@property(nonatomic, retain) NSColor *startingColor;
@property(nonatomic, retain) NSColor *endingColor;
@property(assign) int angle;

@end

