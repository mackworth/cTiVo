//
//  MTSubscriptionList.m
//  myTivo
//
//  Created by Scott Buchanan on 12/7/12.
//  Copyright (c) 2012 Scott Buchanan. All rights reserved.
//

#import "MTSubscriptionList.h"

@implementation MTSubscriptionList

@synthesize subscribedShows;

-(void)awakeFromNib
{
	self.dataSource  = self;
    self.delegate    = self;
//    self.rowHeight = 24;
    self.allowsMultipleSelection = YES;
	self.columnAutoresizingStyle = NSTableViewUniformColumnAutoresizingStyle;
}


-(NSString *) seriesFromProgram:(NSString *) name {
	NSArray * nameParts = [name componentsSeparatedByString: @":"];
	if (nameParts.count == 0) return name;
	return [nameParts objectAtIndex:0];
}

- (NSUInteger) findShow: (MTTiVoShow *) show {
	if (!show.seriesTitle) {
		show.seriesTitle = [self seriesFromProgram:show.showTitle];
	}
	NSString * seriesSearchString = show.seriesTitle;
	if (!seriesSearchString) return NSNotFound;
	return [self.subscribedShows indexOfObjectPassingTest:
		^BOOL(NSDictionary *showItem, NSUInteger index, BOOL *stop) {
			NSString * possMatch =	(NSString *)[showItem objectForKey:kMTSubscribedSeries];
			return [possMatch localizedCaseInsensitiveCompare:seriesSearchString] == NSOrderedSame;
	}];
}

-(BOOL) isSubscribed:(MTTiVoShow *) tivoShow {
	NSUInteger index = [self findShow:tivoShow];
	if (index == NSNotFound) return NO;
	NSDate * prevRecording = (NSDate *)[[self.subscribedShows objectAtIndex:index] objectForKey:kMTSubscribedSeriesDate];
	BOOL before = [prevRecording compare: tivoShow.showDate] == NSOrderedAscending;
	return before;
} 

-(void)updateSubscriptionWithDate: (NSNotification *) notification
{
	MTTiVoShow * tivoShow = (MTTiVoShow *)notification.object;
	NSUInteger index = [self findShow:tivoShow];
	if (index != NSNotFound) {
		[[self.subscribedShows objectAtIndex:index] setObject:tivoShow.showDate forKey:kMTSubscribedSeriesDate];
		[[NSUserDefaults standardUserDefaults] setValue:self.subscribedShows forKey:kMTSubscriptionList];

	}
}
-(IBAction) unsubscribeSelectedItems:(id) sender {
	
	NSMutableSet *itemsToRemove = [NSMutableSet setWithCapacity: subscribedShows.count];
	for (NSUInteger i = 0; i <  self.numberOfRows; i++) {
		if ([self isRowSelected:i]) {
			MTTiVoShow *programToRemove = [subscribedShows objectAtIndex:i];
			[itemsToRemove addObject:programToRemove];
		}
	}
	for (NSDictionary * subscription in itemsToRemove) {
		[subscribedShows removeObject:subscription];
	}
	
	[[NSUserDefaults standardUserDefaults] setValue:self.subscribedShows forKey:kMTSubscriptionList];
	[self deselectAll:nil];
	[self reloadData];
	//No need to notify...
	//[[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationSubscriptionListUpdated object:nil];
}

-(void) addSubscription:(MTTiVoShow *) tivoShow {
	//set the "lastrecording" time for one second before this show, to include this show.
	if ([self findShow:tivoShow] == NSNotFound) {
        NSDate * earlierTime = [tivoShow.showDate  dateByAddingTimeInterval:-1];
        [self.subscribedShows addObject:[NSMutableDictionary dictionaryWithObjectsAndKeys:
					tivoShow.seriesTitle,kMTSubscribedSeries,
					earlierTime, kMTSubscribedSeriesDate,
											nil]];
		[[NSUserDefaults standardUserDefaults] setValue:self.subscribedShows forKey:kMTSubscriptionList];
		[self reloadData];
	}
}

//-(void) removeSubscription:(NSString *) seriesName {
//	NSUInteger index = [self findShow:seriesName];
//	if (index != NSNotFound) {
//		[self.subscribedShows removeObjectAtIndex:index];
//	}
//}

#

-(void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [super dealloc];
}

#pragma mark - Table Delegate Protocol

-(void)tableViewSelectionDidChange:(NSNotification *)notification
{
    [_unsubscribeButton setEnabled:([self numberOfSelectedRows] !=0)];
//    NSTableView *viewChanged = (NSTableView *)notification.object;
//    for (int i = 0; i <  _myTivos.recordings.count; i++) {
//        NSTextField *thisRow = [viewChanged viewAtColumn:0 row:i makeIfNecessary:NO];
//        if ([viewChanged isRowSelected:i]) {
//            thisRow.backgroundColor = [NSColor colorWithCalibratedRed:.4 green:.4 blue:1 alpha:.5];
//        } else {
//            thisRow.backgroundColor = [NSColor colorWithCalibratedRed:0 green:0 blue:0 alpha:0];
//        }
//    }
    
}


#pragma mark - Table Data Source Protocol

- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView
{
	return self.subscribedShows.count;
}

static NSDateFormatter *dateFormatter;

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
    // get an existing cell with the MyView identifier if it exists
	NSTableCellView *result = [tableView makeViewWithIdentifier:tableColumn.identifier owner:self];
	NSDictionary *thisSubscription = [self.subscribedShows objectAtIndex:row];
    // There is no existing cell to reuse so we will create a new one
	if (result == nil) {
        
        // create the new NSTextField with a frame of the {0,0} with the width of the table
        // note that the height of the frame is not really relevant, the row-height will modify the height
        // the new text field is then returned as an autoreleased object
        result = [[[NSTableCellView alloc] initWithFrame:CGRectMake(0, 0, tableView.frame.size.width, 20)] autorelease];
        //        result.textField.font = [NSFont userFontOfSize:14];
        result.textField.editable = NO;
        
        // the identifier of the NSTextField instance is set to MyView. This
        // allows it to be re-used
        result.identifier = tableColumn.identifier;
    }
	
    // result is now guaranteed to be valid, either as a re-used cell
    // or as a new cell, so set the stringValue of the cell to the
    // nameArray value at row
	
	if (!dateFormatter) {
		dateFormatter= [[NSDateFormatter alloc] init];
		[dateFormatter setDateStyle:NSDateFormatterShortStyle];
		[dateFormatter setTimeStyle:NSDateFormatterShortStyle];

	}
	if ([tableColumn.identifier compare:@"series"] == NSOrderedSame) {
		result.textField.stringValue = [thisSubscription objectForKey:kMTSubscribedSeries] ;
        result.toolTip = result.textField.stringValue;
	} else if ([tableColumn.identifier compare:@"date"] == NSOrderedSame) {
		NSDate * lastDate = [(NSDate *)[thisSubscription objectForKey:kMTSubscribedSeriesDate] dateByAddingTimeInterval:1]; //display one second later to avoid second we stole above.

		result.textField.stringValue = [dateFormatter stringFromDate: lastDate ];
		[result.textField setAlignment:NSRightTextAlignment];
        result.toolTip = result.textField.stringValue;
	}
	
    // return the result.
    return result;
    
}


@end
