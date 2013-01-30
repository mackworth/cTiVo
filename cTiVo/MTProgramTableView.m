//
//  MTProgramList.m
//  myTivo
//
//  Created by Scott Buchanan on 12/7/12.
//  Copyright (c) 2012 Scott Buchanan. All rights reserved.
//

#import "MTProgramTableView.h"
#import "MTDownloadCheckTableCell.h"
#import "MTTiVoManager.h"
#import "MTMainWindowController.h"


@implementation MTProgramTableView
@synthesize  sortedShows= _sortedShows;

-(id) initWithCoder:(NSCoder *)aDecoder
{
	self = [super initWithCoder:aDecoder];
	if (self) {
		[self setNotifications];
	}
	return self;
}

-(void)setNotifications
{
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reloadEpisode:) name:kMTNotificationDetailsLoaded object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reloadData) name:kMTNotificationTiVoShowsUpdated  object:nil];
	[[NSUserDefaults standardUserDefaults] addObserver:self forKeyPath:kMTShowCopyProtected options:NSKeyValueChangeSetting context:nil];
	
	[self  setDraggingSourceOperationMask:NSDragOperationLink forLocal:NO];
	[self  setDraggingSourceOperationMask:NSDragOperationCopy forLocal:YES];

}

-(void)awakeFromNib
{
    self.dataSource = self;
    self.delegate    = self;
    self.allowsMultipleSelection = YES;
	self.columnAutoresizingStyle = NSTableViewUniformColumnAutoresizingStyle;
    self.selectedTiVo = [[NSUserDefaults standardUserDefaults] objectForKey:kMTSelectedTiVo];
}

-(void)reloadData
{
    //Configure Table Columns depending on how many TiVos
    //[tiVoColumnHolder setHidden:tiVoManager.tiVoList.count == 1]; //now let user decide
    
	//save selection to preserve after reloadData
	NSIndexSet * selectedRowIndexes = [self selectedRowIndexes];
    NSArray * selectedShows = [self.sortedShows objectsAtIndexes:selectedRowIndexes];
    
	self.sortedShows = nil;
    [super reloadData];
    
    if (self.sortedShows.count) {
        myController.showForDetail = self.sortedShows[0];
    }
	//now restore selection
	NSIndexSet * showIndexes = [self.sortedShows indexesOfObjectsPassingTest:^BOOL(id obj, NSUInteger idx, BOOL *stop) {
		return [selectedShows indexOfObject:obj] !=NSNotFound;
	}];
	

    [self selectRowIndexes:showIndexes byExtendingSelection:NO];
    
}

-(void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
	[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
	if ([keyPath compare:kMTShowCopyProtected] == NSOrderedSame) {
		[self reloadData];
	}
}

-(void)reloadEpisode:(NSNotification *)notification
{
	MTTiVoShow *thisShow = notification.object;
	NSInteger row = [self.sortedShows indexOfObject:thisShow];
    if (row != NSNotFound) {
        NSRange columns = NSMakeRange(0,self.numberOfColumns);//[self columnWithIdentifier:@"Episode"];
        [self reloadDataForRowIndexes:[NSIndexSet indexSetWithIndex:row] columnIndexes:[NSIndexSet indexSetWithIndexesInRange:columns]];

    }
}


-(void)dealloc
{
    [tiVoColumnHolder release];
    self.selectedTiVo = nil;
    self.sortedShows = nil;
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [super dealloc];
}

#pragma mark - Table Delegate Protocol

-(IBAction)selectTivo:(id)sender
{
    if (tiVoManager.tiVoList.count > 1) { //Nothing to change otherwise
        self.selectedTiVo = ((MTTiVo *)[(NSPopUpButton *)sender selectedItem].representedObject).tiVo.name;
        [[NSUserDefaults standardUserDefaults] setObject:self.selectedTiVo forKey:kMTSelectedTiVo];
        [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationTiVoListUpdated object:_selectedTiVo];
		[[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationTiVoShowsUpdated object:nil];
    }
    
}

-(NSInteger)numberOfSelectedRows
{
    NSIndexSet *currentSelectedRows = [self selectedRowIndexes];
    __block NSInteger numSelected = 0;
    NSArray *showsToCheck = self.sortedShows;
    [currentSelectedRows enumerateIndexesUsingBlock:^(NSUInteger row, BOOL *stop){
        MTTiVoShow *thisShow = [showsToCheck objectAtIndex:row];
       if (![thisShow.protectedShow boolValue]) {
            numSelected++;
        }

    }];
    return numSelected;
}

-(NSArray *)sortedShows
{
	if (!_sortedShows) {
		NSPredicate *protectedPredicate = [NSPredicate predicateWithFormat:@"protectedShow == %@",[NSNumber numberWithBool:NO]];
		if ([[[NSUserDefaults standardUserDefaults] objectForKey:kMTShowCopyProtected] boolValue]) {
			protectedPredicate = [NSPredicate predicateWithBlock:^BOOL(id evaluatedObject, NSDictionary *bindings) {
				return YES;
			}];
		}
		NSPredicate *tiVoPredicate = [NSPredicate predicateWithBlock:^BOOL(id evaluatedObject, NSDictionary *bindings) {
			return YES;
		}];
		if (self.selectedTiVo && [tiVoManager foundTiVoNamed:self.selectedTiVo] && [self.selectedTiVo compare:kMTAllTiVos] != NSOrderedSame) { //We need a predicate for filtering
			tiVoPredicate = [NSPredicate predicateWithFormat:@"tiVo.tiVo.name == %@",self.selectedTiVo];
		}
		self.sortedShows = [[[tiVoManager.tiVoShows filteredArrayUsingPredicate:tiVoPredicate] filteredArrayUsingPredicate:protectedPredicate] sortedArrayUsingDescriptors:self.sortDescriptors];
	}
	return _sortedShows;
}

-(void)tableViewSelectionDidChange:(NSNotification *)notification
{
    NSIndexSet *selectedRowIndexes = [self selectedRowIndexes];
    if (selectedRowIndexes.count == 1) {
        NSArray *selectedRows = [self.sortedShows objectsAtIndexes:selectedRowIndexes];
        [myController setValue:selectedRows[0] forKey:@"showForDetail"];
    }
}

-(void) tableViewColumnDidResize:(NSNotification *) notification {

	NSTableColumn * column = notification.userInfo[@"NSTableColumn"];
	if ([column.identifier compare:@"Date" ] ==NSOrderedSame) {
		NSInteger columnNum = [self columnWithIdentifier:@"Date"];
		[self reloadDataForRowIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0,self.sortedShows.count)]
							 columnIndexes:[NSIndexSet indexSetWithIndex:columnNum]];
	}

}

#pragma mark - Table Data Source Protocol

-(void)tableView:(NSTableView *)tableView sortDescriptorsDidChange:(NSArray *)oldDescriptors
{
    [self reloadData];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView
{
    return self.sortedShows.count;
}

- (void)tableView:(NSTableView *)tableView didAddRowView:(NSTableRowView *)rowView forRow:(NSInteger)row
{
    MTTiVoShow *thisShow = [self.sortedShows objectAtIndex:row];
    if ([thisShow.protectedShow boolValue]) {
        rowView.selectionHighlightStyle = NSTableViewSelectionHighlightStyleNone;
    } else {
        rowView.selectionHighlightStyle = NSTableViewSelectionHighlightStyleRegular;
    }
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
    // get an existing cell with the MyView identifier if it exists
    NSTableCellView *result = [tableView makeViewWithIdentifier:tableColumn.identifier owner:self];
//    NSLog(@"%@ ==> %@",tableColumn.identifier, result.textField);
	MTTiVoShow *thisShow = [self.sortedShows objectAtIndex:row];
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
	if ([tableColumn.identifier compare:@"Programs"] == NSOrderedSame) {
		result.textField.stringValue = thisShow.showTitle ;
        result.toolTip = result.textField.stringValue;
	} else if ([tableColumn.identifier compare:@"TiVo"] == NSOrderedSame) {
        result.textField.stringValue = thisShow.tiVo.tiVo.name;
        result.textField.textColor = [NSColor blackColor];
        if (!thisShow.tiVo.isReachable) {
            result.textField.textColor = [NSColor redColor];
        }
        result.toolTip = thisShow.tiVo.tiVo.name;
    } else if ([tableColumn.identifier compare:@"Date"] == NSOrderedSame) {
		if ([tableColumn width] > 135) {
			result.textField.stringValue = thisShow.showMediumDateString;
		} else {
			result.textField.stringValue = thisShow.showDateString;
		}
			result.toolTip = result.textField.stringValue;
	} else if ([tableColumn.identifier compare:@"Length"] == NSOrderedSame) {
		NSInteger length = (thisShow.showLength+30)/60; //round up to nearest minute;
		result.textField.stringValue = [NSString stringWithFormat:@"%ld:%0.2ld",length/60,length % 60];
        result.toolTip = result.textField.stringValue;
	} else if ([tableColumn.identifier compare:@"Episode"] == NSOrderedSame) {
		result.textField.stringValue = thisShow.seasonEpisode;
        result.toolTip = result.textField.stringValue;
	} else if ([tableColumn.identifier compare:@"Queued"] == NSOrderedSame) {
		result.textField.stringValue = thisShow.isQueued ? @"✔" : @"";
	} else if ([tableColumn.identifier compare:@"HD"] == NSOrderedSame) {
		result.textField.stringValue = [thisShow.isHD boolValue] ? @"✔" : @"";
		result.textField.alignment = NSCenterTextAlignment;
	} else if ([tableColumn.identifier compare:@"Channel"] == NSOrderedSame) {
		result.textField.stringValue = thisShow.channelString;
	} else if ([tableColumn.identifier compare:@"Size"] == NSOrderedSame) {
		if (thisShow.fileSize >= 1000000000) {
			result.textField.stringValue = [NSString stringWithFormat:@"%0.1fGB",thisShow.fileSize/1000000000.0];
		} else {
			result.textField.stringValue = [NSString stringWithFormat:@"%ldMB",((NSInteger)thisShow.fileSize)/1000000 ];
		};
	} else if ([tableColumn.identifier compare:@"TiVoID"] == NSOrderedSame) {
		result.textField.stringValue = [NSString stringWithFormat:@"%d", thisShow.showID ];
	} else if ([tableColumn.identifier compare:@"Series"] == NSOrderedSame) {
		result.textField.stringValue = thisShow.seriesTitle;
		result.toolTip = result.textField.stringValue;
	} else if ([tableColumn.identifier compare:@"Title"] == NSOrderedSame) {
		result.textField.stringValue = thisShow.episodeTitle;
		result.toolTip = result.textField.stringValue;
	} else if ([tableColumn.identifier compare:@"Station"] == NSOrderedSame) {
		result.textField.stringValue = thisShow.stationCallsign;
	} else if ([tableColumn.identifier compare:@"FirstAirDate"] == NSOrderedSame) {
		NSLog(@"airdate: %@",thisShow.originalAirDateNoTime);
		result.textField.stringValue = thisShow.originalAirDateNoTime ? thisShow.originalAirDateNoTime : @"";
	
	}
    if ([thisShow.protectedShow boolValue]) {
        result.textField.textColor = [NSColor grayColor];
    } else {
        result.textField.textColor = [NSColor blackColor];
    }

    // return the result.
    return result;
    
}

#pragma mark Drag N Drop support


- (NSDragOperation)draggingSession:(NSDraggingSession *)session sourceOperationMaskForDraggingContext:(NSDraggingContext)context {
	
    switch(context) {
        case NSDraggingContextOutsideApplication:
            return NO;  //could theoretically allow, as completed shows are also here.
            break;
			
        case NSDraggingContextWithinApplication:
        default:
            return NSDragOperationGeneric | NSDragOperationCopy |NSDragOperationLink;
            break;
	}
}


- (BOOL)tableView:(NSTableView *)tv writeRowsWithIndexes:(NSIndexSet *)rowIndexes toPasteboard:(NSPasteboard*)pboard {
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
		if ([selectedColumn.identifier caseInsensitiveCompare:@"Programs"] == NSOrderedSame) { //Check if over text
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
	// Drag and drop support
	[self selectRowIndexes:rowIndexes byExtendingSelection:NO ];
	NSArray	*selectedObjects = [self.sortedShows objectsAtIndexes:rowIndexes ];
	[pboard writeObjects:selectedObjects];
   return YES;
}


@end
