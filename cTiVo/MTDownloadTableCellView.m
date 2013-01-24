//
//  MTDownloadListCellView.m
//  cTiVo
//
//  Created by Scott Buchanan on 12/11/12.
//  Copyright (c) 2012 Scott Buchanan. All rights reserved.
//

#import "MTDownloadTableCellView.h"

@implementation MTDownloadTableCellView

- (id)initWithFrame:(NSRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        // Initialization code here.
        _progressIndicator = [[MTProgressindicator alloc] initWithFrame:frame];
        [self addSubview:_progressIndicator];
    }
    
    return self;
}

- (void)setBackgroundStyle:(NSBackgroundStyle)style
{
    [super setBackgroundStyle:style];
	
    // If the cell's text color is black, this sets it to white
//    [((NSCell *)self.progressIndicator.leftText.cell) setBackgroundStyle:style];
	
    // Otherwise you need to change the color manually
    switch (style) {
        case NSBackgroundStyleLight:
            [self.progressIndicator.leftText setTextColor:[NSColor colorWithCalibratedWhite:0.0 alpha:1.0]];
            [self.progressIndicator.rightText setTextColor:[NSColor colorWithCalibratedWhite:0.0 alpha:1.0]];
            break;
			
        case NSBackgroundStyleDark:
        default:
            [self.progressIndicator.leftText setTextColor:[NSColor colorWithCalibratedWhite:1.0 alpha:1.0]];
            [self.progressIndicator.rightText setTextColor:[NSColor colorWithCalibratedWhite:1.0 alpha:1.0]];
            break;
    }
}



- (void)drawRect:(NSRect)dirtyRect
{
    // Drawing code here.
}

-(void)dealloc
{
    [_downloadStage release];
    [super dealloc];
}

@end
