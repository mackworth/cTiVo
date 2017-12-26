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
        [self initialSetup];
        [_checkBox setTarget:target];
        [_checkBox setAction:selector];
    }

    return self;
}

-(void) awakeFromNib {
	[super awakeFromNib];
    [self initialSetup];
}

-(void) initialSetup {
    // Initialization code here.
    _checkBox = [[MTCheckBox alloc] initWithFrame:CGRectMake((self.bounds.size.width-17)/2, self.bounds.origin.y, 17, self.bounds.size.height)];
    [_checkBox setButtonType:NSSwitchButton];
    _checkBox.title = @"";
    [_checkBox setAutoresizingMask:NSViewMinXMargin | NSViewMaxXMargin ];
    [_checkBox setEnabled:NO];
    [self addSubview:_checkBox];
    [self.textField removeFromSuperview];
     self.textField = nil;
}

-(void) setTarget:(id)target {
    self.checkBox.target = target;
}
-(void) setAction:(SEL)action {
    self.checkBox.action = action;
}

-(SEL) action {
    return self.checkBox.action;
}

-(id) target {
    return self.checkBox.target;
}


@end
