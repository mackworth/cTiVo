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
