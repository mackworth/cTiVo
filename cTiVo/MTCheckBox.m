//
//  MTCheckBox.m
//  cTiVo
//
//  Created by Scott Buchanan on 12/26/12.
//  Copyright (c) 2012 Scott Buchanan. All rights reserved.
//

#import "MTCheckBox.h"

@implementation MTCheckBox

-(void)setOn: (BOOL) shouldTurnOn {
    if (shouldTurnOn) {
        self.state = NSControlStateValueOn;
    } else {
        self.state = NSControlStateValueOff;
    }
}

@end
