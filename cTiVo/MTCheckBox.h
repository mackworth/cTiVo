//
//  MTCheckBox.h
//  cTiVo
//
//  Created by Scott Buchanan on 12/26/12.
//  Copyright (c) 2012 Scott Buchanan. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface MTCheckBox : NSButton

@property (nonatomic, weak) id owner;

-(void)setOn: (BOOL) shouldTurnOn;
@end
