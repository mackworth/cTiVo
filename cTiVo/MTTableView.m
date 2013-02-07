//
//  MTTableView.m
//  cTiVo
//
//  Created by Hugh Mackworth on 2/6/13.
//  Copyright (c) 2013 Scott Buchanan. All rights reserved.
//

#import "MTTableView.h"

@implementation MTTableView
@synthesize  sortedShows= _sortedShows;

-(id) initWithCoder:(NSCoder *)aDecoder
{
	self = [super initWithCoder:aDecoder];
	if (self) {
		[self setNotifications];
	}
	return self;
}

-(void) setNotifications {
	[self  setDraggingSourceOperationMask:NSDragOperationMove forLocal:NO];
	[self  setDraggingSourceOperationMask:NSDragOperationCopy forLocal:YES];
	
}

-(void) awakeFromNib {
	self.dataSource = self;
	self.delegate    = self;
	self.allowsMultipleSelection = YES;
	self.columnAutoresizingStyle = NSTableViewUniformColumnAutoresizingStyle;
	self.selectedTiVo = [[NSUserDefaults standardUserDefaults] objectForKey:kMTSelectedTiVo];
	if (!tiVoColumnHolder) tiVoColumnHolder = [[self tableColumnWithIdentifier:@"TiVo"] retain];
}

@end
