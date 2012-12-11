//
//  MTDownloadListCellView.m
//  cTiVo
//
//  Created by Scott Buchanan on 12/11/12.
//  Copyright (c) 2012 Scott Buchanan. All rights reserved.
//

#import "MTDownloadListCellView.h"

@implementation MTDownloadListCellView

- (id)initWithFrame:(NSRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        // Initialization code here.
        _progressIndicator = [[NSProgressIndicator alloc] initWithFrame:frame];
        _progressIndicator.style = NSProgressIndicatorBarStyle;
        [_progressIndicator setIndeterminate:NO];
        [_progressIndicator setMinValue:0];
        [_progressIndicator setMaxValue:1.0];
        [self addSubview:_progressIndicator];
        NSTextField *textField = [[[NSTextField alloc] initWithFrame:CGRectMake(0, 0, frame.size.width-80, frame.size.height)] autorelease];
        self.textField = textField;
        [self.textField setBackgroundColor:[NSColor clearColor]];
        [textField setEditable:NO];
        [textField setBezeled:NO];
        [self addSubview:textField];
        _downloadStage = [[NSTextField alloc] initWithFrame:CGRectMake(frame.size.width - 80, 0, 80, frame.size.height)];
        [_downloadStage setEditable:NO];
        [_downloadStage setBezeled:NO];
        [_downloadStage setBackgroundColor:[NSColor clearColor]];
        [self addSubview:_downloadStage];
        
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
