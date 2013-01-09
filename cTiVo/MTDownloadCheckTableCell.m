//
//  MTDownloadListCheckCell.m
//  cTiVo
//
//  Created by Scott Buchanan on 12/20/12.
//  Copyright (c) 2012 Scott Buchanan. All rights reserved.
//

#import "MTDownloadCheckTableCell.h"

@implementation MTDownloadCheckTableCell

-(id)initWithFrame:(NSRect)frameRect
{
    return [self initWithFrame:frameRect withTarget:nil withAction:nil];
}

- (id)initWithFrame:(NSRect)frame withTarget:(id)target withAction:(SEL)selector
{
    self = [super initWithFrame:frame];
    if (self) {
        // Initialization code here.
        _checkBox = [[[MTCheckBox alloc] initWithFrame:frame] autorelease];
        [_checkBox setButtonType:NSSwitchButton];
        [self addSubview:_checkBox];
        [_checkBox setTarget:target];
        [_checkBox setAction:selector];
        [_checkBox setEnabled:NO];
    }
    
    return self;
}

- (void)drawRect:(NSRect)dirtyRect
{
    // Drawing code here.
}

@end
