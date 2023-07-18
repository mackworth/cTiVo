//
//  MTCenterButton.m
//  cTiVo
//
//  Created by Hugh Mackworth on 7/17/23.
//  Copyright © 2023 cTiVo. All rights reserved.
//

#import "MTCenterButtonCell.h"

@implementation MTCenterButtonCell

- (NSRect)titleRectForBounds:(NSRect)rect {
    NSRect titleFrame = [super titleRectForBounds:rect];
//    NSSize titleSize = [[self attributedStringValue] size];
    
    titleFrame.origin.y = -1;  //no idea why; set by experimentation
    return titleFrame;
}


@end
