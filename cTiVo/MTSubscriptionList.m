//
//  MTSubscriptionList.m
//  myTivo
//
//  Created by Scott Buchanan on 12/7/12.
//  Copyright (c) 2012 Scott Buchanan. All rights reserved.
//

#import "MTSubscriptionList.h"

@implementation MTSubscriptionList


-(void)awakeFromNib
{
	self.dataSource  = self;
    self.delegate    = self;
//    self.rowHeight = 20;
    self.allowsMultipleSelection = YES;
	self.columnAutoresizingStyle = NSTableViewUniformColumnAutoresizingStyle;
	tiVoManager = [MTTiVoManager sharedTiVoManager];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reloadData) name:kMTNotificationSubscriptionsUpdated object:nil];
}

-(NSArray *)sortedShows
{
	return [tiVoManager.subscribedShows sortedArrayUsingDescriptors:self.sortDescriptors];
}



-(IBAction) unsubscribeSelectedItems:(id) sender {
	
	NSMutableSet *itemsToRemove = [NSMutableSet setWithCapacity: self.sortedShows.count];
	for (NSUInteger i = 0; i <  self.numberOfRows; i++) {
		if ([self isRowSelected:i]) {
			MTTiVoShow *programToRemove = [self.sortedShows objectAtIndex:i];
			[itemsToRemove addObject:programToRemove];
		}
	}
	for (NSDictionary * subscription in itemsToRemove) {
		[tiVoManager.subscribedShows removeObject:subscription];
	}
	
	[[NSUserDefaults standardUserDefaults] setObject:tiVoManager.subscribedShows	forKey:kMTSubscriptionList];
	[self deselectAll:nil];
	[self reloadData];
	//No need to notify...
	//[[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationSubscriptionListUpdated object:nil];
}

-(void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [super dealloc];
}

#pragma mark - Table Delegate Protocol

-(void)tableViewSelectionDidChange:(NSNotification *)notification
{
    [_unsubscribeButton setEnabled:([self numberOfSelectedRows] !=0)];
    
}

-(CGFloat)tableView:(NSTableView *)tableView heightOfRow:(NSInteger)row
{
    return 24.0;
}


#pragma mark - Table Data Source Protocol

- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView
{
	return self.sortedShows.count;
}

static NSDateFormatter *dateFormatter;

-(id)makeViewWithIdentifier:(NSString *)identifier owner:(id)owner
{
    id result;
	NSTableColumn *thisColumn = [self tableColumnWithIdentifier:identifier];
    if([identifier compare: @"iTunes"] == NSOrderedSame) {
        MTDownloadListCheckCell *thisCell = [[[MTDownloadListCheckCell alloc] initWithFrame:CGRectMake(thisColumn.width/2.0-10, 0, 20, 20) withTarget:myController withAction:@selector(changeiTunes:)] autorelease];
        thisCell.identifier = identifier;
        result = (id)thisCell;
    } else if([identifier compare: @"Simu"] == NSOrderedSame) {
        MTDownloadListCheckCell *thisCell = [[[MTDownloadListCheckCell alloc] initWithFrame:CGRectMake(thisColumn.width/2.0-10, 0, 20, 20) withTarget:myController withAction:@selector(changeSimultaneous:)] autorelease];
        thisCell.identifier = identifier;
        result = (id)thisCell;
    } else if([identifier compare: @"FormatPopUp"] == NSOrderedSame) {
		MTPopUpTableCellView *thisCell = [[[MTPopUpTableCellView alloc] initWithFrame:NSMakeRect(0, 0, thisColumn.width, 20) withTarget:myController withAction:@selector(selectFormat:)] autorelease];
		thisCell.identifier = identifier;
        NSArray *formatList = [MTTiVoManager sharedTiVoManager].formatList;
        [thisCell.popUpButton removeAllItems];
        //    if (_selectedFormat) {
        //        mediaKeyLabel.stringValue = [[NSUserDefaults standardUserDefaults] stringForKey:[_selectedFormat objectForKey:@"name"]];
        //    }
        for (NSDictionary *fl in formatList) {
            [thisCell.popUpButton addItemWithTitle:[fl objectForKey:@"name"]];
            [[thisCell.popUpButton lastItem] setRepresentedObject:fl];
            //            if (_selectedFormat && [[fl objectForKey:@"name"] compare:[_selectedFormat objectForKey:@"name"]] == NSOrderedSame) {
            //                [self selectItem:[self lastItem]];
            //            }
            //            
        }
		result = (id)thisCell;
	} else {
        result =[super makeViewWithIdentifier:identifier owner:owner];
    }
    return result;
}


- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
    // get an existing cell with the MyView identifier if it exists
	NSTableCellView *result = [tableView makeViewWithIdentifier:tableColumn.identifier owner:self];
	NSDictionary *thisSubscription = [self.sortedShows objectAtIndex:row];
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
	} else if ([tableColumn.identifier compare:@"FormatPopUp"] == NSOrderedSame) {
//		result.textField.stringValue = [thisSubscription objectForKey:kMTSubscribedSeriesFormat] ;
//        result.toolTip = result.textField.stringValue;
		((MTPopUpTableCellView *)result).popUpButton.owner = thisSubscription;
        [((MTPopUpTableCellView *)result).popUpButton selectItemWithTitle:thisSubscription[kMTSubscribedSeriesFormat]];
		
	} else if ([tableColumn.identifier compare:@"iTunes"] == NSOrderedSame) {
        NSInteger c = NSOffState;
        if ([[thisSubscription objectForKey:kMTiTunesEncode] boolValue]) {
            c = NSOnState;
        }
        [((MTDownloadListCheckCell *)result).checkBox setState:c] ;
        [((MTDownloadListCheckCell *)result).checkBox setEnabled:YES] ;
		((MTDownloadListCheckCell *)result).checkBox.owner = thisSubscription;
 	} else if ([tableColumn.identifier compare:@"Simu"] == NSOrderedSame) {
        NSInteger c = NSOffState;
        if ([[thisSubscription objectForKey:kMTSimultaneousEncode] boolValue]) {
            c = NSOnState;
        }
        [((MTDownloadListCheckCell *)result).checkBox setState:c] ;
        [((MTDownloadListCheckCell *)result).checkBox setEnabled:YES] ;
		((MTDownloadListCheckCell *)result).checkBox.owner = thisSubscription;
        //Make sure that this format can simu  encode
        for (NSDictionary *fd in tiVoManager.formatList) {
            if ([(NSString *)(thisSubscription[kMTSubscribedSeriesFormat]) compare:fd[@"name"]] == NSOrderedSame) {
                BOOL canSimu = ![fd[@"mustDownloadFirst"] boolValue];
                if (!canSimu) {
                    [((MTDownloadListCheckCell *)result).checkBox setEnabled:NO];
                }
            }
        }
    }
	
    // return the result.
    return result;
    
}


@end
