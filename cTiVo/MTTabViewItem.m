//
//  MTTabViewItem.m
//  cTiVo
//
//  Created by Scott Buchanan on 1/27/13.
//  Copyright (c) 2013 Scott Buchanan. All rights reserved.
//

#import "MTTabViewItem.h"

@implementation MTTabViewItem

-(id)initWithCoder:(NSCoder *)aDecoder
{
	self = [super initWithCoder:aDecoder];
	if (self) {
		self.windowWidth = [NSNumber numberWithFloat:500];
		self.windowHeight = [NSNumber numberWithFloat:500];
	}
	return self;
}


@end
