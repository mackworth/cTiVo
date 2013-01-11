//
//  MTSubscriptionTableView.m
//  myTivo
//
//  Created by Scott Buchanan on 12/7/12.
//  Copyright (c) 2012 Scott Buchanan. All rights reserved.
//

#import "MTSubscriptionTableView.h"

@implementation MTSubscriptionTableView

@synthesize sortedSubscriptions = _sortedSubscriptions;

//-(id)init
//{
//	self = [super init];
//	if (self) {
//		[self setNotifications];
//	}
//	return self;
//}

-(id) initWithCoder:(NSCoder *)aDecoder
{
	self = [super initWithCoder:aDecoder];
	if (self) {
		[self setNotifications];
	}
	return self;
}

//-(id)initWithFrame:(NSRect)frameRect
//{
//	self = [super initWithFrame:frameRect];
//	if (self) {
//		[self setNotifications];
//	}
//	return self;
//}
//
-(void)setNotifications
{
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reloadData) name:kMTNotificationSubscriptionsUpdated object:nil];
}

-(void)awakeFromNib
{
	self.dataSource  = self;
    self.delegate    = self;
//    self.rowHeight = 20;
    self.allowsMultipleSelection = YES;
	self.columnAutoresizingStyle = NSTableViewUniformColumnAutoresizingStyle;
    _sortedSubscriptions = nil;
}

-(NSArray *)sortedSubscriptions
{
	if (!_sortedSubscriptions) {
        self.sortedSubscriptions =[tiVoManager.subscribedShows sortedArrayUsingDescriptors:self.sortDescriptors];
    }
    return _sortedSubscriptions;
}

-(void) reloadData {
    self.sortedSubscriptions = nil;
    [super reloadData];
}

-(void)tableView:(NSTableView *)tableView sortDescriptorsDidChange:(NSArray *)oldDescriptors
{
    self.sortedSubscriptions = nil;
    [self reloadData];
}

-(IBAction) unsubscribeSelectedItems:(id) sender {
	
    NSArray * itemsToRemove = [self.sortedSubscriptions objectsAtIndexes:self.selectedRowIndexes];

	[tiVoManager.subscribedShows  removeObjectsInArray:itemsToRemove];
    
	[tiVoManager.subscribedShows saveSubscriptions];
     
    [self deselectAll:nil];
}

-(IBAction)delete:(id)sender{
    [self unsubscribeSelectedItems:sender];
}

-(void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    self.sortedSubscriptions = nil;
    [super dealloc];
}

#pragma mark - Table Delegate Protocol

-(void)tableViewSelectionDidChange:(NSNotification *)notification
{
    [_unsubscribeButton setEnabled:([self numberOfSelectedRows] !=0)];
    
}

-(CGFloat)tableView:(NSTableView *)tableView heightOfRow:(NSInteger)row
{
    return 18.0;
}


#pragma mark - Table Data Source Protocol

- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView
{
    return self.sortedSubscriptions.count;
}

-(id)makeViewWithIdentifier:(NSString *)identifier owner:(id)owner
{
    id result;
	NSTableColumn *thisColumn = [self tableColumnWithIdentifier:identifier];
    if([identifier compare: @"iTunes"] == NSOrderedSame) {
        MTDownloadCheckTableCell *thisCell = [[[MTDownloadCheckTableCell alloc] initWithFrame:CGRectMake(thisColumn.width/2.0-10, 0, 20, 20) withTarget:myController withAction:@selector(changeiTunes:)] autorelease];
        thisCell.identifier = identifier;
        result = (id)thisCell;
    } else if([identifier compare: @"Simu"] == NSOrderedSame) {
        MTDownloadCheckTableCell *thisCell = [[[MTDownloadCheckTableCell alloc] initWithFrame:CGRectMake(thisColumn.width/2.0-10, 0, 20, 20) withTarget:myController withAction:@selector(changeSimultaneous:)] autorelease];
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

static NSDateFormatter *dateFormatter;


- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
    // get an existing cell with the MyView identifier if it exists
	NSTableCellView *result = [tableView makeViewWithIdentifier:tableColumn.identifier owner:self];
	MTSubscription *thisSubscription = [self.sortedSubscriptions objectAtIndex:row];
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
	
	if ([tableColumn.identifier compare:@"series"] == NSOrderedSame) {
		result.textField.stringValue = thisSubscription.seriesTitle ;
        result.toolTip = result.textField.stringValue;
	} else if ([tableColumn.identifier compare:@"date"] == NSOrderedSame) {
 
        if (!dateFormatter) {
            dateFormatter= [[NSDateFormatter alloc] init];
            [dateFormatter setDateStyle:NSDateFormatterShortStyle];
            [dateFormatter setTimeStyle:NSDateFormatterShortStyle];
            
        }
        NSDate * lastDate = [thisSubscription.lastRecordedTime dateByAddingTimeInterval:1]; //display one second later to avoid second we stole above.

		result.textField.stringValue = [dateFormatter stringFromDate: lastDate ];
		[result.textField setAlignment:NSRightTextAlignment];
        result.toolTip = result.textField.stringValue;
	} else if ([tableColumn.identifier compare:@"FormatPopUp"] == NSOrderedSame) {
//		result.textField.stringValue = [thisSubscription objectForKey:kMTSubscribedSeriesFormat] ;
//        result.toolTip = result.textField.stringValue;
		((MTPopUpTableCellView *)result).popUpButton.owner = thisSubscription;
        [((MTPopUpTableCellView *)result).popUpButton selectItemWithTitle:thisSubscription.encodeFormat[@"name"]];
        result.toolTip = [NSString stringWithFormat:@"%@: %@", thisSubscription.encodeFormat[@"name"], thisSubscription.encodeFormat[@"formatDescription"]];
 
	} else if ([tableColumn.identifier compare:@"iTunes"] == NSOrderedSame) {
        MTCheckBox * checkBox = ((MTDownloadCheckTableCell *)result).checkBox;
        [checkBox setEnabled: [thisSubscription canAddToiTunes]];
        [checkBox setOn:[thisSubscription shouldAddToiTunes] && [thisSubscription canAddToiTunes]];
        checkBox.owner = thisSubscription;
 	} else if ([tableColumn.identifier compare:@"Simu"] == NSOrderedSame) {
        MTCheckBox * checkBox = ((MTDownloadCheckTableCell *)result).checkBox;
        [checkBox setEnabled: [thisSubscription canSimulEncode]] ;
        [checkBox setOn:[ thisSubscription shouldSimulEncode]];
        checkBox.owner = thisSubscription;
        
    }
	
    // return the result.
    return result;
    
}


@end
