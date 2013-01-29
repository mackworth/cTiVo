//
//  MTTabViewItem.m
//  cTiVo
//
//  Created by Scott Buchanan on 1/27/13.
//  Copyright (c) 2013 Scott Buchanan. All rights reserved.
//

#import "MTTabViewItem.h"

@implementation MTTabViewItem


-(void)dealloc
{
	self.windowController = nil;
	[super dealloc];
}
@end
