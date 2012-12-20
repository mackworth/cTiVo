//
//  MTDownloadListCheckCell.m
//  cTiVo
//
//  Created by Scott Buchanan on 12/20/12.
//  Copyright (c) 2012 Scott Buchanan. All rights reserved.
//

#import "MTDownloadListCheckCell.h"

@implementation MTDownloadListCheckCell

- (id)initWithFrame:(NSRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        // Initialization code here.
        _checkBox = [[[NSButton alloc] initWithFrame:frame] autorelease];
        [_checkBox setButtonType:NSSwitchButton];
        [self addSubview:_checkBox];
    }
    
    return self;
}

- (void)drawRect:(NSRect)dirtyRect
{
    // Drawing code here.
}

@end
