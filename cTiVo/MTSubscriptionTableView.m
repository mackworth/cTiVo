//
//  MTSubscriptionTableView.m
//  myTivo
//
//  Created by Scott Buchanan on 12/7/12.
//  Copyright (c) 2012 Scott Buchanan. All rights reserved.
//

#import "MTSubscriptionTableView.h"
#import "MTMainWindowController.h"

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
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reloadData) name:kMTNotificationFormatListUpdated object:nil];
	[self registerForDraggedTypes:[NSArray arrayWithObjects:kMTTivoShowPasteBoardType, nil]];
	[self  setDraggingSourceOperationMask:NSDragOperationDelete forLocal:NO];

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
	//save selection to preserve after reloadData
	NSIndexSet * selectedRowIndexes = [self selectedRowIndexes];
    NSArray * selectedSubs = [self.sortedSubscriptions objectsAtIndexes:selectedRowIndexes];
    
	self.sortedSubscriptions = nil;
    [super reloadData];
    
	
	//now restore selection
	NSIndexSet * subIndexes = [self.sortedSubscriptions indexesOfObjectsPassingTest:^BOOL(id obj, NSUInteger idx, BOOL *stop) {
		return [selectedSubs indexOfObject:obj] !=NSNotFound;
	}];
    [self selectRowIndexes:subIndexes byExtendingSelection:NO];
	
}

-(void)tableView:(NSTableView *)tableView sortDescriptorsDidChange:(NSArray *)oldDescriptors
{
    self.sortedSubscriptions = nil;
    [self reloadData];
}

-(IBAction) unsubscribeSelectedItems:(id) sender {
	NSLog(@"unsubscribing");
    NSArray * itemsToRemove = [self.sortedSubscriptions objectsAtIndexes:self.selectedRowIndexes];

	[tiVoManager.subscribedShows  deleteSubscriptions:itemsToRemove];
    
    [self deselectAll:nil];
}

-(IBAction)delete:(id)sender{
    [self unsubscribeSelectedItems:sender];
}

-(void)dealloc
{
	[self unregisterDraggedTypes];
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
	    thisCell.popUpButton.showHidden = NO;
		thisCell.identifier = identifier;
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
		MTFormatPopUpButton * popUp = ((MTPopUpTableCellView *)result).popUpButton;
		popUp.owner = thisSubscription;
		popUp.formatList = tiVoManager.formatList;
//		NSString * tempQQQQ = thisSubscription.encodeFormat.name;
		thisSubscription.encodeFormat = [popUp selectFormatNamed:thisSubscription.encodeFormat.name];
// 		if([tempQQQQ compare: thisSubscription.encodeFormat.name] != NSOrderedSame)
//			NSLog(@"QQQSB popup at %@ changed from %@ to %@", thisSubscription.seriesTitle, tempQQQQ, thisSubscription.encodeFormat.name);

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

#pragma mark drag and drop routines

//Drag&drop source (for now,just for delete)
-(void) draggedImage:(NSImage *)image endedAt:(NSPoint)screenPoint operation:(NSDragOperation)operation {
	//pre 10.7
	if (operation == NSDragOperationDelete) {
		[self unsubscribeSelectedItems:nil];
	}
}
/* //should use this for 10.7 and after, but redundant with above
- (void)tableView:(NSTableView *)tableView draggingSession:(NSDraggingSession *)session endedAtPoint:(NSPoint)screenPoint operation:(NSDragOperation)operation {
	
	if (operation == NSDragOperationDelete) {
		[self unsubscribeSelectedItems:nil];
	}
}
*/

- (BOOL)tableView:(NSTableView *)tv writeRowsWithIndexes:(NSIndexSet *)rowIndexes toPasteboard:(NSPasteboard*)pboard {
    // Drag and drop support:  nothing to do here, as we're only a "source" to drag to trash
	// 	NSArray	*selectedObjects = [self.sortedSubscriptions objectsAtIndexes:rowIndexes ];
	//	[pboard declareTypes:[NSArray arrayWithObjects:kMTTivoShowPasteBoardType,nil] owner:self];
	//[pboard writeObjects:selectedObjects];
	//	NSLog (@"QQQQproperty list: %@",[pboard propertyListForType:kMTTivoShowPasteBoardType]);
	if (![[NSUserDefaults standardUserDefaults]boolForKey:kMTDisableDragSelect] ) {
		NSPoint windowPoint = [self.window mouseLocationOutsideOfEventStream];
		NSPoint p = [tv convertPoint:windowPoint fromView:nil];
		NSInteger r = [tv rowAtPoint:p];
		NSInteger c = [tv columnAtPoint:p];
		if (c < 0) {
			c = 0;
		}
		NSTableColumn *selectedColumn = tv.tableColumns[c];
		BOOL isSelectedRow = [tv isRowSelected:r];
		BOOL isOverText = NO;
		if ([selectedColumn.identifier caseInsensitiveCompare:@"series"] == NSOrderedSame) { //Check if over text
			NSTableCellView *showCellView = [tv viewAtColumn:c row:r makeIfNecessary:NO];
			NSTextField *showField = showCellView.textField;
			NSPoint clickInText = [showField convertPoint:windowPoint fromView:nil];
			NSSize stringSize = [showField.stringValue sizeWithAttributes:@{NSFontAttributeName : showField.font}];
			if (clickInText.x < stringSize.width) {
				isOverText = YES;
			}
		}
		if (!isSelectedRow && !isOverText) {
			return NO;
		}
	}
	[self selectRowIndexes:rowIndexes byExtendingSelection:NO ];
	return YES;
}

- (NSDragOperation)draggingSession:(NSDraggingSession *)session sourceOperationMaskForDraggingContext:(NSDraggingContext)context {
	
    switch(context) {
        case NSDraggingContextOutsideApplication:
            return NSDragOperationDelete;
            break;
			
        case NSDraggingContextWithinApplication:
        default:
            return NO ;
            break;
	}
}

//Drag and drop receiver methods

- (NSDragOperation)tableView:(NSTableView *)aTableView validateDrop:(id < NSDraggingInfo >)info proposedRow:(NSInteger)row proposedDropOperation:(NSTableViewDropOperation)operation {
	if ([info draggingSource] == aTableView) {
		return NSDragOperationMove;
	} else if ([info draggingSource] == myController.tiVoShowTable ||
			   [info draggingSource] == myController.downloadQueueTable) {
		return NSDragOperationCopy;
	} else {
		return NSDragOperationNone;
	}
}


- (BOOL)tableView:(NSTableView *)aTableView acceptDrop:(id )info row:(NSInteger)row dropOperation:(NSTableViewDropOperation)operation {
	NSArray	*classes = [NSArray arrayWithObject:[MTTiVoShow class]];
	NSDictionary *options = [NSDictionary dictionary];
	//NSDictionary * pasteboard = [[info draggingPasteboard] propertyListForType:kMTTivoShowPasteBoardType] ;
	//NSLog(@"calling readObjects%@",pasteboard);
	NSArray	*draggedShows = [[info draggingPasteboard] readObjectsForClasses:classes options:options];
//	NSLog(@"QQQdragging: %@", draggedShows);
	
	//dragged shows are copies, so we need to find the real show objects
	NSMutableArray * realShows = [NSMutableArray arrayWithCapacity:draggedShows.count ];
	for (MTTiVoShow * show in draggedShows) {
		MTTiVoShow * realShow= [tiVoManager findRealShow:show];
		if (realShow) [realShows addObject:realShow];
	}
	
	if( [info draggingSource] == myController.tiVoShowTable  ||
	    [info draggingSource] == myController.downloadQueueTable) {
		NSArray * newSubs = [tiVoManager.subscribedShows addSubscriptions: realShows];
		
		//now leave new subscriptions selected
		self.sortedSubscriptions  = nil;  //reset sort with new subs
		NSIndexSet * subIndexes = [self.sortedSubscriptions indexesOfObjectsPassingTest:^BOOL(id obj, NSUInteger idx, BOOL *stop) {
			return [newSubs indexOfObject:obj] !=NSNotFound;
		}];
		if (subIndexes.count > 0) [self selectRowIndexes:subIndexes byExtendingSelection:NO];
		return YES;
	} else {
		return NO;
	}
}


@end
