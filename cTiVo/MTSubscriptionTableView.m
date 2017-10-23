//
//  MTSubscriptionTableView.m
//  myTivo
//
//  Created by Scott Buchanan on 12/7/12.
//  Copyright (c) 2012 Scott Buchanan. All rights reserved.
//

#import "MTSubscriptionTableView.h"
#import "MTMainWindowController.h"
#import "MTPopUpTableCellView.h"
#import "MTTiVoPopUpTableCellView.h"
#import "MTDownloadCheckTableCell.h"
#import "MTSubscriptionList.h"

@implementation MTSubscriptionTableView

@synthesize sortedSubscriptions = _sortedSubscriptions;

__DDLOGHERE__

//-(id)init
//{
//	self = [super init];
//	if (self) {
        //        [self setNotifications];
//	}
//	return self;
//}

-(id) initWithCoder:(NSCoder *)aDecoder
{
	self = [super initWithCoder:aDecoder];
	if (self) {
		[self setNotifications];
        self.dataSource  = self;
        self.delegate    = self;
        //    self.rowHeight = 20;
        self.allowsMultipleSelection = YES;
        self.columnAutoresizingStyle = NSTableViewUniformColumnAutoresizingStyle;
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

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reloadSubscription:) name:kMTNotificationSubscriptionChanged object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(tableViewSelectionDidChange:) name:kMTNotificationSubscriptionsUpdated object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reloadData) name:kMTNotificationSubscriptionsUpdated object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reloadData) name:kMTNotificationFormatListUpdated object:nil];
	[self registerForDraggedTypes:[NSArray arrayWithObjects:kMTTivoShowPasteBoardType, kMTDownloadPasteBoardType, NSPasteboardTypeString, nil]];
	[self  setDraggingSourceOperationMask:NSDragOperationDelete forLocal:NO];

}

-(NSArray *)sortedSubscriptions
{
	if (!_sortedSubscriptions) {
		DDLogVerbose(@"Resorting subscription table");
        self.sortedSubscriptions =[tiVoManager.subscribedShows sortedArrayUsingDescriptors:self.sortDescriptors];
    }
    return _sortedSubscriptions;
}

-(void) reloadData {
	//save selection to preserve after reloadData
	DDLogVerbose(@"Reloading subscription table");
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
	DDLogDetail(@"User Requested delete subscriptions");
    NSArray * itemsToRemove = [self.sortedSubscriptions objectsAtIndexes:self.selectedRowIndexes];
    [self deselectAll:nil];

	[tiVoManager.subscribedShows  deleteSubscriptions:itemsToRemove];
	[myController playTrashSound];
}

-(IBAction) reapplySelectedItems:(id) sender {
	DDLogDetail(@"User Requested reapply subscriptions");
    NSArray * itemsToApply = [self.sortedSubscriptions objectsAtIndexes:self.selectedRowIndexes];
	[tiVoManager.subscribedShows clearHistory:itemsToApply];
	[tiVoManager.subscribedShows checkSubscriptionsNew:itemsToApply];
}

-(void) changeSuggestions: (id) sender {
	MTCheckBox *checkbox = sender;
	//updating an individual show in download queue
	MTSubscription * subscription = (MTSubscription *)checkbox.owner;
	NSNumber *newVal = [NSNumber numberWithBool: checkbox.state == NSOnState];
	subscription.includeSuggestions = newVal;
}

-(IBAction)selectTivoPopUp:(id)sender
{
	MTTiVoPopUpButton *thisButton = (MTTiVoPopUpButton *)sender;
	if ([thisButton.owner class] == [MTSubscription class]) {
		MTSubscription * subscription = (MTSubscription *) thisButton.owner;
		
        subscription.preferredTiVo = [thisButton selectedItem].representedObject ?: @"";
	}
}

-(void) changeHDOnly: (id) sender {
	MTCheckBox *checkbox = sender;
	MTSubscription * subscription = (MTSubscription *)checkbox.owner;
	NSNumber *newVal = [NSNumber numberWithBool: checkbox.state == NSOnState];
	subscription.HDOnly = newVal;
	if (newVal.boolValue) {
		subscription.SDOnly = @NO;
	}
	[[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationSubscriptionChanged object:subscription];
}

-(void) changeSDOnly: (id) sender {
	MTCheckBox *checkbox = sender;
	MTSubscription * subscription = (MTSubscription *)checkbox.owner;
	NSNumber *newVal = [NSNumber numberWithBool: checkbox.state == NSOnState];
	subscription.SDOnly = newVal;
	if (newVal.boolValue) {
		subscription.HDOnly = @NO;
	}
	[[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationSubscriptionChanged object:subscription];
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

-(void)reloadSubscription:(NSNotification *)notification{
	MTSubscription *thisSubcription = notification.object;
	NSInteger row = [self.sortedSubscriptions indexOfObject:thisSubcription];
    if (row != NSNotFound) {
        NSRange columns = NSMakeRange(0,self.numberOfColumns);//[self columnWithIdentifier:@"Episode"];
        [self reloadDataForRowIndexes:[NSIndexSet indexSetWithIndex:row] columnIndexes:[NSIndexSet indexSetWithIndexesInRange:columns]];	
    }
}



#pragma mark - Table Data Source Protocol

- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView
{
    return self.sortedSubscriptions.count;
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
        result = [[NSTableCellView alloc] initWithFrame:CGRectMake(0, 0, tableView.frame.size.width, 20)];
        //        result.textField.font = [NSFont userFontOfSize:14];
        result.textField.editable = NO;
        
        // the identifier of the NSTextField instance is set to MyView. This
        // allows it to be re-used
        result.identifier = tableColumn.identifier;
    }
	
    // result is now guaranteed to be valid, either as a re-used cell
    // or as a new cell, so set the stringValue of the cell to the
    // nameArray value at row
	result.toolTip = nil;
	if ([tableColumn.identifier compare:@"series"] == NSOrderedSame) {
		result.textField.stringValue = thisSubscription.displayTitle ;
        result.toolTip = result.textField.stringValue;
	} else if ([tableColumn.identifier compare:@"date"] == NSOrderedSame) {
 
        if (!dateFormatter) {
            dateFormatter= [[NSDateFormatter alloc] init];
            [dateFormatter setDateStyle:NSDateFormatterShortStyle];
            [dateFormatter setTimeStyle:NSDateFormatterShortStyle];
            
        }
        NSDate * displayDate = thisSubscription.displayDate;
        if (!displayDate || [displayDate isEqualToDate: [NSDate dateWithTimeIntervalSince1970:0]]) {
            result.textField.stringValue = @"Never";
        } else {
            result.textField.stringValue = [dateFormatter stringFromDate: displayDate ];
        }
		[result.textField setAlignment:NSRightTextAlignment];
        result.toolTip = result.textField.stringValue;
	} else if ([tableColumn.identifier compare:@"FormatPopUp"] == NSOrderedSame) {
		MTFormatPopUpButton * popUp = ((MTPopUpTableCellView *)result).popUpButton;
		popUp.owner = thisSubscription;
		thisSubscription.encodeFormat = [popUp selectFormat:thisSubscription.encodeFormat];
        popUp.formatList = tiVoManager.formatList;
        popUp.target = myController;
        popUp.action = @selector(selectFormat:);
	} else if ([tableColumn.identifier compare:@"TiVoPopUp"] == NSOrderedSame) {
		MTTiVoPopUpButton * popUp = ((MTTiVoPopUpTableCellView *)result).popUpButton;
        popUp.target = self;
        popUp.action = @selector(selectTivoPopUp:);
		popUp.owner = thisSubscription;
		popUp.currentTivo = thisSubscription.preferredTiVo;
	} else if ([tableColumn.identifier compare:@"iTunes"] == NSOrderedSame) {
        MTCheckBox * checkBox = ((MTDownloadCheckTableCell *)result).checkBox;
        checkBox.target = myController;
        checkBox.action = @selector(changeiTunes:);
        [checkBox setEnabled: [thisSubscription canAddToiTunes]];
        [checkBox setOn:[thisSubscription shouldAddToiTunes] && [thisSubscription canAddToiTunes]];
        checkBox.owner = thisSubscription;
 	} else if ([tableColumn.identifier compare:@"Skip"] == NSOrderedSame) {
        MTCheckBox * checkBox = ((MTDownloadCheckTableCell *)result).checkBox;
        checkBox.target = myController;
        checkBox.action = @selector(changeSkip:);
        [checkBox setEnabled: [thisSubscription canSkipCommercials]] ;
        [checkBox setOn:[[ thisSubscription skipCommercials]boolValue]];
        checkBox.owner = thisSubscription;
 	} else if ([tableColumn.identifier compare:@"Mark"] == NSOrderedSame) {
        MTCheckBox * checkBox = ((MTDownloadCheckTableCell *)result).checkBox;
        checkBox.target = myController;
        checkBox.action = @selector(changeMark:);
        [checkBox setEnabled: [thisSubscription canMarkCommercials]] ;
        [checkBox setOn:[[ thisSubscription markCommercials]boolValue]];
        checkBox.owner = thisSubscription;
#ifndef deleteXML
	} else if ([tableColumn.identifier isEqualToString:@"XML"]) {
        MTCheckBox * checkBox = ((MTDownloadCheckTableCell *)result).checkBox;
        checkBox.target = myController;
        checkBox.action = @selector(changeXML:);
        [checkBox setOn: thisSubscription.genXMLMetaData.boolValue];
        checkBox.owner = thisSubscription;
		checkBox.enabled = YES;		
#endif
	} else if ([tableColumn.identifier isEqualToString:@"pyTiVo"]) {
        MTCheckBox * checkBox = ((MTDownloadCheckTableCell *)result).checkBox;
        checkBox.target = myController;
        checkBox.action = @selector(changepyTiVo:);
        [checkBox setOn: thisSubscription.genTextMetaData.boolValue];
        checkBox.owner = thisSubscription;
		checkBox.enabled = YES;
	} else if ([tableColumn.identifier isEqualToString:@"Subtitles"]) {
        MTCheckBox * checkBox = ((MTDownloadCheckTableCell *)result).checkBox;
        checkBox.target = myController;
        checkBox.action = @selector(changeSubtitle:);
        [checkBox setOn: thisSubscription.exportSubtitles.boolValue];
        checkBox.owner = thisSubscription;
		checkBox.enabled = YES;		
#ifndef deleteXML
	} else if ([tableColumn.identifier isEqualToString:@"Metadata"]) {
        MTCheckBox * checkBox = ((MTDownloadCheckTableCell *)result).checkBox;
        checkBox.target = myController;
        checkBox.action = @selector(changeMetadata:);
        [checkBox setOn: thisSubscription.includeAPMMetaData.boolValue && thisSubscription.encodeFormat.canAcceptMetaData];
        checkBox.owner = thisSubscription;
		checkBox.enabled = thisSubscription.encodeFormat.canAcceptMetaData;
#endif
	} else if([tableColumn.identifier isEqualToString: @"Suggestions"]) {
        MTCheckBox * checkBox = ((MTDownloadCheckTableCell *)result).checkBox;
        checkBox.target = self;
        checkBox.action = @selector(changeSuggestions:);
        [checkBox setOn: thisSubscription.includeSuggestions.boolValue];
        checkBox.owner = thisSubscription;
		checkBox.enabled = YES;
	}  else if([tableColumn.identifier isEqualToString: @"HDOnly"]) {
        MTCheckBox * checkBox = ((MTDownloadCheckTableCell *)result).checkBox;
        checkBox.target = self;
        checkBox.action = @selector(changeHDOnly:);
        [checkBox setOn: thisSubscription.HDOnly.boolValue];
        checkBox.owner = thisSubscription;
		checkBox.enabled = YES;
	}  else if([tableColumn.identifier isEqualToString: @"SDOnly"]) {
        MTCheckBox * checkBox = ((MTDownloadCheckTableCell *)result).checkBox;
        checkBox.target = self;
        checkBox.action = @selector(changeSDOnly:);
        [checkBox setOn: thisSubscription.SDOnly.boolValue];
        checkBox.owner = thisSubscription;
		checkBox.enabled = YES;
	}

    // return the result.
    return result;
    
}

#pragma mark drag and drop routines

//Drag&drop source (for now,just for delete)

 //should use this for 10.7 and after, but redundant with above
- (void)tableView:(NSTableView *)tableView draggingSession:(NSDraggingSession *)session endedAtPoint:(NSPoint)screenPoint operation:(NSDragOperation)operation {
	
	if (operation == NSDragOperationDelete) {
        DDLogDetail(@"User dragged subscriptions to trash");
		[self unsubscribeSelectedItems:nil];
    }
}

//- (id<NSPasteboardWriting>)tableView:(NSTableView *)tableView
//              pasteboardWriterForRow:(NSInteger)row {
//
//}

- (BOOL)tableView:(NSTableView *)tv writeRowsWithIndexes:(NSIndexSet *)rowIndexes toPasteboard:(NSPasteboard*)pboard {
	if (![[NSUserDefaults standardUserDefaults]boolForKey:kMTDisableDragSelect] ) {
        //if user wants drag-to-select, then check if we're selecting new rows or not
        //drag/drop if current row is  already selected OR we're over name of show
        //this is parallel to Finder behavior.
		NSPoint windowPoint = [self.window mouseLocationOutsideOfEventStream];
		NSPoint p = [tv convertPoint:windowPoint fromView:nil];
		NSInteger r = [tv rowAtPoint:p];
		NSInteger c = [tv columnAtPoint:p];
		if (c >= 0 && r >=0 ) {
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
	}
	[self selectRowIndexes:rowIndexes byExtendingSelection:NO ];
    [pboard writeObjects:[self.sortedSubscriptions objectsAtIndexes:rowIndexes]];
	return YES;
}

- (NSDragOperation)draggingSession:(NSDraggingSession *)session sourceOperationMaskForDraggingContext:(NSDraggingContext)context {
	
    switch(context) {
        case NSDraggingContextOutsideApplication:
			return NSDragOperationDelete | NSDragOperationCopy;
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
	} else if ([[info draggingPasteboard].types containsObject:NSPasteboardTypeString]){
        return NSDragOperationCopy;
    } else {
		return NSDragOperationNone;
	}
}

-(NSArray *)insertShowsFromPasteboard:(NSPasteboard *) pboard atRow:(NSUInteger) row {
    NSArray	*classes = [NSArray arrayWithObject:[MTTiVoShow class]];
    NSDictionary *options = [NSDictionary dictionary];
    //NSDictionary * pasteboard = [[info draggingPasteboard] propertyListForType:kMTTivoShowPasteBoardType] ;
    //NSLog(@"calling readObjects%@",pasteboard);
    NSArray	*draggedShows = [pboard readObjectsForClasses:classes options:options];
    if (draggedShows.count == 0) return nil;
    DDLogDetail(@"Dragging into Subscriptions: %@", draggedShows);

    //dragged shows are copies, so we need to find the real show objects
    NSMutableArray * realShows = [NSMutableArray arrayWithCapacity:draggedShows.count ];
    for (MTTiVoShow * show in draggedShows) {
        MTTiVoShow * realShow= [tiVoManager findRealShow:show];
        if (realShow) [realShows addObject:realShow];
    }
    DDLogVerbose(@"Dragging into Subscriptions: %@", realShows);

    return [tiVoManager.subscribedShows addSubscriptionsShows: realShows];
}

-(NSArray *)insertDownloadsFromPasteboard:(NSPasteboard *) pboard atRow:(NSUInteger) row {
    NSArray	*classes = [NSArray arrayWithObject:[MTDownload class]];
    NSDictionary *options = [NSDictionary dictionary];
    //NSDictionary * pasteboard = [[info draggingPasteboard] propertyListForType:kMTTivoShowPasteBoardType] ;
    //NSLog(@"calling readObjects%@",pasteboard);
    NSArray	*draggedDLs= [pboard readObjectsForClasses:classes options:options];
    if (draggedDLs.count == 0) return nil;
    DDLogDetail(@"Dragging into Subscriptions: %@", draggedDLs);

    //dragged downloads are copies, so we need to find the real show objects
    NSMutableArray * realDLs = [NSMutableArray arrayWithCapacity:draggedDLs.count ];
    for (MTDownload * draggedDL in draggedDLs) {
        MTDownload * realDL= [tiVoManager findRealDownload:draggedDL];
        if (realDL) [realDLs addObject:realDL];
    }
    DDLogVerbose(@"Dragging into Subscriptions: %@", realDLs);

    return  [tiVoManager.subscribedShows addSubscriptionsDL: realDLs];
}

-(NSArray *) insertStringsFromPasteboard:(NSPasteboard *) pboard atRow:(NSUInteger) row {
    NSArray	*classes = [NSArray arrayWithObject:[NSString class]];
    NSDictionary *options = [NSDictionary dictionary];
    //NSDictionary * pasteboard = [[info draggingPasteboard] propertyListForType:kMTTivoShowPasteBoardType] ;
    //NSLog(@"calling readObjects%@",pasteboard);
    NSArray	*draggedStrings= [pboard readObjectsForClasses:classes options:options];
    if (draggedStrings.count == 0)  return nil;

    DDLogDetail(@"Dragging into Subscriptions: %@", draggedStrings);
    return [tiVoManager.subscribedShows addSubscriptionsFormattedStrings: draggedStrings];

}
-(void) selectSubs: (NSArray *) subs  {
    self.sortedSubscriptions  = nil;  //reset sort with new subs
    NSIndexSet * subIndexes = [self.sortedSubscriptions indexesOfObjectsPassingTest:^BOOL(id obj, NSUInteger idx, BOOL *stop) {
        return [subs indexOfObject:obj] !=NSNotFound;
    }];
    if (subIndexes.count > 0) {
        [self selectRowIndexes:subIndexes byExtendingSelection:NO];
        [self scrollRowToVisible:[subIndexes firstIndex]];
    }
}

- (BOOL)tableView:(NSTableView *)aTableView acceptDrop:(id )info row:(NSInteger)row dropOperation:(NSTableViewDropOperation)operation {
    NSArray * newSubs = nil;
	if ( [info draggingSource] == myController.tiVoShowTable ){
        newSubs = [self insertShowsFromPasteboard:[info draggingPasteboard]  atRow:row];
	} else if([info draggingSource] == myController.downloadQueueTable) {
        newSubs = [self insertDownloadsFromPasteboard:[info draggingPasteboard]  atRow:row];
    } else if ([[info draggingPasteboard].types containsObject:NSPasteboardTypeString]){
        newSubs = [self insertStringsFromPasteboard:[info draggingPasteboard]  atRow:row];
      }
    if (newSubs.count == 0) return NO;
	DDLogVerbose(@"Created new subs: %@", newSubs);
	//now leave new subscriptions selected
    [self selectSubs: newSubs];
	return YES;
}

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem{
    if ([menuItem action]==@selector(copy:) ||
        [menuItem action]==@selector(cut:)  ||
        [menuItem action]==@selector(delete:)) {
        return (self.numberOfSelectedRows >0);
    } else  if ([menuItem action]==@selector(paste:)) {
        NSPasteboard * pboard = [NSPasteboard generalPasteboard];
        return  ([pboard.types containsObject:kMTTivoShowPasteBoardType] ||
                 [pboard.types containsObject:kMTDownloadPasteBoardType] ||
                  [pboard.types containsObject:NSPasteboardTypeString]);
    }
    return YES;
}

-(IBAction)copy: (id) sender {
    NSIndexSet *selectedRowIndexes = [self selectedRowIndexes];
    NSArray *selectedSubs = [self.sortedSubscriptions objectsAtIndexes:selectedRowIndexes];
    if (selectedSubs.count > 0) {
        MTSubscription * firstSub = selectedSubs[0];

        NSPasteboard * pboard = [NSPasteboard generalPasteboard];
        [pboard declareTypes:[firstSub writableTypesForPasteboard:pboard] owner:nil];
        [pboard writeObjects:selectedSubs];
    }
}

-(IBAction)cut: (id) sender {
    [self copy:sender];
    [self delete:sender];
}

-(IBAction)paste: (id) sender {
    NSUInteger row = [self selectedRowIndexes].firstIndex;
    NSPasteboard * pboard = [NSPasteboard generalPasteboard];
    if ([pboard.types containsObject:kMTDownloadPasteBoardType]) {
        [self insertDownloadsFromPasteboard:pboard atRow:row];
    } else if ([pboard.types containsObject:kMTTivoShowPasteBoardType]) {
        [self insertShowsFromPasteboard:pboard atRow:row];
    } else if ([pboard.types containsObject:NSPasteboardTypeString]) {
      [self insertStringsFromPasteboard:pboard atRow:row];
        }
}

-(IBAction)delete:(id)sender{
    DDLogMajor(@"user request to delete subscriptions");
    [self unsubscribeSelectedItems:sender];
}

-(void)dealloc
{
    DDLogDetail(@"deallocing subscriptionTable %@",self);
    [self unregisterDraggedTypes];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}


@end
