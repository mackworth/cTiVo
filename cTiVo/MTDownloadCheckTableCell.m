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
    [_checkBox setButtonType:NSButtonTypeSwitch];
    _checkBox.title = @"";
    _checkBox.translatesAutoresizingMaskIntoConstraints = NO;

    [_checkBox setEnabled:NO];
    [self addSubview:_checkBox];
    [self.textField removeFromSuperview];
     self.textField = nil;

    [_checkBox.heightAnchor constraintEqualToConstant:17].active = YES;
    [_checkBox.centerXAnchor constraintEqualToAnchor: self.centerXAnchor].active = YES;
    [_checkBox.centerYAnchor constraintEqualToAnchor: self.centerYAnchor].active = YES;
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
