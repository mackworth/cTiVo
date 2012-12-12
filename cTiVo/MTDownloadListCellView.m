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
        _progressIndicator = [[MTProgressindicator alloc] initWithFrame:frame];
//        _progressIndicator.style = NSProgressIndicatorBarStyle;
//		_progressIndicator.usesThreadedAnimation = NO;
//        [_progressIndicator setIndeterminate:NO];
//        [_progressIndicator setMinValue:0];
//        [_progressIndicator setMaxValue:1.0];
        [self addSubview:_progressIndicator];
//		_progressIndicator.alphaValue  = 0.5;
//        NSTextField *textField = [[[NSTextField alloc] initWithFrame:CGRectMake(0, 0, frame.size.width-80, frame.size.height)] autorelease];
//        self.textField = textField;
//        [self.textField setBackgroundColor:[NSColor clearColor]];
//        [textField setEditable:NO];
//        [textField setBezeled:NO];
//        [self addSubview:textField];
//        _downloadStage = [[NSTextField alloc] initWithFrame:CGRectMake(frame.size.width - 80, -3, 80, frame.size.height)];
//        [_downloadStage setAlignment:NSRightTextAlignment];
//        [_downloadStage setEditable:NO];
//        [_downloadStage setBezeled:NO];
//        [_downloadStage setBackgroundColor:[NSColor clearColor]];
//		[_downloadStage setFont:[NSFont userFontOfSize:10]];
//        [self addSubview:_downloadStage];
        
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
