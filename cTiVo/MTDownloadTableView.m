//
//  MTDownloadList.m
//  myTivo
//
//  Created by Scott Buchanan on 12/8/12.
//  Copyright (c) 2012 Scott Buchanan. All rights reserved.
//

#import "MTDownloadTableView.h"
#import "MTPopUpTableCellView.h"

@implementation MTDownloadTableView
@synthesize  sortedShows= _sortedShows;

-(id) initWithCoder:(NSCoder *)aDecoder
{
	self = [super initWithCoder:aDecoder];
	if (self) {
		[self setNotifications];
	}
	return self;
}

-(IBAction) delete:(id)sender {
    [myController removeFromDownloadQueue:sender];
}


-(void)setNotifications
{
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reloadDataDownload) name:kMTNotificationDownloadStatusChanged object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reloadDataFormat) name:kMTNotificationFormatListUpdated object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reloadDataTiVos) name:kMTNotificationTiVoListUpdated object:nil];
	[self registerForDraggedTypes:[NSArray arrayWithObjects:kMTTivoShowPasteBoardType, nil]];
	[self  setDraggingSourceOperationMask:NSDragOperationLink forLocal:NO];
	[self  setDraggingSourceOperationMask:NSDragOperationCopy forLocal:YES];


}

-(void) reloadDataTiVos {
	//NSLog(@"QQQReloading from Tivos changed");
	[self reloadData];
	
}
-(void) reloadDataDownload {
	//	NSLog(@"QQQReloading from Download status changed");
	[self reloadData];
	
}
-(void) reloadDataFormat{
//	NSLog(@"QQQReloading from Format status changed");
	[self reloadData];
	
}
-(void)awakeFromNib
{  //remember: called multiple times for each new cell loaded
    self.dataSource = self;
    self.delegate    = self;
    self.allowsMultipleSelection = YES;
	self.columnAutoresizingStyle = NSTableViewUniformColumnAutoresizingStyle;
    if (!tiVoColumnHolder) tiVoColumnHolder = [[self tableColumnWithIdentifier:@"TiVo"] retain];
}

-(void) reloadData {
    //Configure Table Columns depending on how many TiVos
    
	//save selection to restore after reload
	NSArray * selectedShows = [self.sortedShows objectsAtIndexes: self.selectedRowIndexes];
	
	NSTableColumn *tiVoColumn = [self tableColumnWithIdentifier:@"TiVo"];
    if (tiVoManager.tiVoList.count == 1) {
        if (tiVoColumn) {
			[self removeTableColumn:tiVoColumn];
        }
    } else {
        if (!tiVoColumn && tiVoColumnHolder) {
            [self addTableColumn: tiVoColumnHolder];
            NSInteger colPos = [self columnWithIdentifier:@"TiVo"];
            [self moveColumn:colPos toColumn:1];
        }
    }
	[self sizeToFit];
    self.sortedShows =nil;
    [super reloadData];
	
	//now restore selection
	NSIndexSet * showIndexes = [self.sortedShows indexesOfObjectsPassingTest:^BOOL(id obj, NSUInteger idx, BOOL *stop) {
		return [selectedShows indexOfObject:obj] !=NSNotFound;
	}];
	
	[self selectRowIndexes:showIndexes byExtendingSelection:NO];
}

-(NSArray *)sortedShows
{
	if (!_sortedShows) {
        self.sortedShows = [tiVoManager.downloadQueue sortedArrayUsingDescriptors:self.sortDescriptors];
    }
    return _sortedShows;
}

-(void)tableView:(NSTableView *)tableView sortDescriptorsDidChange:(NSArray *)oldDescriptors
{
	[self reloadData];
}

-(void)updateProgress
{
    NSInteger programColumnIndex = [self columnWithIdentifier:@"Programs"];
	NSArray *displayedShows = self.sortedShows;
	for (int i=0; i< displayedShows.count; i++) {
		MTDownloadTableCellView *thisCell = [self viewAtColumn:programColumnIndex row:i makeIfNecessary:NO];
		if (thisCell) {
			MTTiVoShow *thisShow = [displayedShows objectAtIndex:i];
			thisCell.progressIndicator.doubleValue = thisShow.processProgress;
			thisCell.progressIndicator.rightText.stringValue = thisShow.showStatus;
			[thisCell setNeedsDisplay:YES];
		}
	}
}

-(void)dealloc
{
	[self  unregisterDraggedTypes];
	[tiVoColumnHolder release]; tiVoColumnHolder=nil;
    self.sortedShows= nil;
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [super dealloc];
}

#pragma mark - Table Delegate Protocol

-(void)tableViewSelectionDidChange:(NSNotification *)notification
{
    NSIndexSet *selectedRowIndexes = [self selectedRowIndexes];
    if (selectedRowIndexes.count == 1) {
        NSArray *selectedRows = [self.sortedShows objectsAtIndexes:selectedRowIndexes];
        [myController setValue:selectedRows[0] forKey:@"showForDetail"];
    }
}

#pragma mark - Table Data Source Protocol

- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView
{
    return self.sortedShows.count;
}

-(id)makeViewWithIdentifier:(NSString *)identifier owner:(id)owner
{
    id result;
	NSTableColumn *thisColumn = [self tableColumnWithIdentifier:identifier];
    if([identifier compare: @"Programs"] == NSOrderedSame) {
        MTDownloadTableCellView *thisCell = [[[MTDownloadTableCellView alloc] initWithFrame:CGRectMake(0, 0, thisColumn.width, 20)] autorelease];
        //        result.textField.font = [NSFont userFontOfSize:14];
        thisCell.textField.editable = NO;
        
        // the identifier of the NSTextField instance is set to MyView. This
        // allows it to be re-used
        thisCell.identifier = identifier;
        result = (id)thisCell;
    } else if([identifier compare: @"iTunes"] == NSOrderedSame) {
        MTDownloadCheckTableCell *thisCell = [[[MTDownloadCheckTableCell alloc] initWithFrame:CGRectMake(thisColumn.width/2.0-10, 0, 20, 20) withTarget:myController withAction:@selector(changeiTunes:)] autorelease];
        thisCell.identifier = identifier;
        result = (id)thisCell;
    } else if([identifier compare: @"Simu"] == NSOrderedSame) {
        MTDownloadCheckTableCell *thisCell = [[[MTDownloadCheckTableCell alloc] initWithFrame:CGRectMake(thisColumn.width/2.0-10, 0, 20, 20) withTarget:myController withAction:@selector(changeSimultaneous:)] autorelease];
        thisCell.identifier = identifier;
        result = (id)thisCell;
   } else if([identifier compare: @"Format"] == NSOrderedSame) {
		MTPopUpTableCellView *thisCell = [[[MTPopUpTableCellView alloc] initWithFrame:NSMakeRect(0, 0, thisColumn.width, 20) withTarget:myController withAction:@selector(selectFormat:)] autorelease];
	    thisCell.popUpButton.showHidden = NO;
		thisCell.identifier = identifier;
       result = thisCell;
    } else {
        result =[super makeViewWithIdentifier:identifier owner:owner];
    }
    return result;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
	MTTiVoShow *thisShow = [self.sortedShows objectAtIndex:row];
//	NSDictionary *idMapping = [NSDictionary dictionaryWithObjectsAndKeys:@"Title",@"Programs",kMTSelectedTiVo,@"TiVo",kMTSelectedFormat,@"Format", nil];
	
    // get an existing cell with the MyView identifier if it exists
	
    MTDownloadTableCellView *result = [tableView makeViewWithIdentifier:tableColumn.identifier owner:self];
    
    // There is no existing cell to reuse so we will create a new one
    if (result == nil) {
        
        // create the new NSTextField with a frame of the {0,0} with the width of the table
        // note that the height of the frame is not really relevant, the row-height will modify the height
        // the new text field is then returned as an autoreleased object
        result = [[[MTDownloadTableCellView alloc] initWithFrame:CGRectMake(0, 0, tableColumn.width, 20)] autorelease];
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
		result.progressIndicator.rightText.stringValue = thisShow.showStatus;
 		result.progressIndicator.leftText.stringValue = thisShow.showTitle ;
        result.progressIndicator.doubleValue = thisShow.processProgress;
        result.toolTip = thisShow.showTitle;
			
    } else if ([tableColumn.identifier compare:@"TiVo"] == NSOrderedSame) {
        result.textField.stringValue = thisShow.tiVo.tiVo.name ;
        result.toolTip = result.textField.stringValue;
        result.textField.textColor = [NSColor blackColor];
        if (!thisShow.tiVo.isReachable && [thisShow.downloadStatus intValue] == kMTStatusDownloading) {
            result.textField.textColor = [NSColor redColor];
        }
        
    } else if ([tableColumn.identifier compare:@"Order"] == NSOrderedSame) {
        result.textField.stringValue = [NSString stringWithFormat:@"%@",thisShow.downloadIndex] ;
        result.toolTip = result.textField.stringValue;
        
    } else if ([tableColumn.identifier compare:@"Format"] == NSOrderedSame) {
		MTPopUpTableCellView * cell = (MTPopUpTableCellView *)result;
		MTFormatPopUpButton *popUpButton = cell.popUpButton;
		popUpButton.owner = thisShow;
       if (([thisShow.downloadStatus intValue] == kMTStatusNew)) {
		    popUpButton.owner = thisShow;
			popUpButton.formatList = tiVoManager.formatList;
			//ensure this format is still "available"
			thisShow.encodeFormat = [popUpButton selectFormatNamed:thisShow.encodeFormat.name];
			popUpButton.hidden = NO;
			cell.textField.hidden= YES;
	   } else {
			//can't change now; just let them know what it is/was
		   cell.textField.stringValue = thisShow.encodeFormat.name;
		   popUpButton.hidden = YES;
		   cell.textField.hidden= NO;
		}
    } else if ([tableColumn.identifier compare:@"iTunes"] == NSOrderedSame) {
        MTCheckBox * checkBox = ((MTDownloadCheckTableCell *)result).checkBox;
        [checkBox setOn: thisShow.addToiTunesWhenEncoded];
        [checkBox setEnabled: [thisShow.downloadStatus intValue] != kMTStatusDone &&
                              thisShow.encodeFormat.canAddToiTunes ];
         checkBox.owner = thisShow;

 	} else if ([tableColumn.identifier compare:@"Simu"] == NSOrderedSame) {
        MTCheckBox * checkBox = ((MTDownloadCheckTableCell *)result).checkBox;
        [checkBox setOn: thisShow.simultaneousEncode];
         checkBox.owner = thisShow;
        [checkBox setEnabled: [thisShow.downloadStatus intValue] == kMTStatusNew &&
                              thisShow.encodeFormat.canSimulEncode];

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
	} else if ([tableColumn.identifier compare:@"Series"] == NSOrderedSame) {
		result.textField.stringValue = thisShow.seriesTitle;
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
	} else if ([tableColumn.identifier compare:@"Title"] == NSOrderedSame) {
		result.textField.stringValue = thisShow.episodeTitle;
		result.toolTip = result.textField.stringValue;
	} else if ([tableColumn.identifier compare:@"Station"] == NSOrderedSame) {
		result.textField.stringValue = thisShow.stationCallsign;
	} else if ([tableColumn.identifier compare:@"Genre"] == NSOrderedSame) {
		result.textField.stringValue = thisShow.episodeGenre;
        result.toolTip = result.textField.stringValue;
	} else if ([tableColumn.identifier compare:@"FirstAirDate"] == NSOrderedSame) {
		NSLog(@"airdate: %@",thisShow.originalAirDateNoTime);
		result.textField.stringValue = thisShow.originalAirDateNoTime ? thisShow.originalAirDateNoTime : @"";
	}
    
    // return the result.
    return result;
    
}
  
#pragma mark Drag N Drop support

//Drag&Drop Source:

- (NSDragOperation)draggingSession:(NSDraggingSession *)session sourceOperationMaskForDraggingContext:(NSDraggingContext)context {
	
    switch(context) {
        case NSDraggingContextOutsideApplication:
            return NSDragOperationCopy | NSDragOperationDelete;
            break;
			
        case NSDraggingContextWithinApplication:
        default:
            return NSDragOperationGeneric | NSDragOperationCopy  | NSDragOperationMove ;
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
			MTDownloadTableCellView *showCellView = [tv viewAtColumn:c row:r makeIfNecessary:NO];
			NSTextField *showField = showCellView.progressIndicator.leftText;
			NSPoint clickInText = [showField convertPoint:windowPoint fromView:nil];
			NSSize stringSize = [showField.stringValue sizeWithAttributes:@{NSFontAttributeName : showField.font}];
			if (clickInText.x < stringSize.width && clickInText.x < showField.bounds.size.width) {
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
	//NSLog (@"QQQproperty list: (Files:) %@ (shows): %@", [pboard propertyListForType:(NSString *)kUTTypeFileURL],[pboard propertyListForType:kMTTivoShowPasteBoardType]);
	return YES;
}

-(void) draggedImage:(NSImage *)image endedAt:(NSPoint)screenPoint operation:(NSDragOperation)operation {
	//pre 10.7
	if (operation == NSDragOperationDelete) {
		[myController removeFromDownloadQueue:nil];
	}

}
/* post 10.7,but redundant with above
- (void)tableView:(NSTableView *)tableView draggingSession:(NSDraggingSession *)session endedAtPoint:(NSPoint)screenPoint operation:(NSDragOperation)operation {
	//post 10.7
	if (operation == NSDragOperationDelete) {
		[myController removeFromDownloadQueue:nil];
	}
}
*/

//Drag and drop Receiver
- (NSDragOperation)tableView:(NSTableView *)aTableView validateDrop:(id < NSDraggingInfo >)info proposedRow:(NSInteger)row proposedDropOperation:(NSTableViewDropOperation)operation {
	if ([info draggingSource] == aTableView) {
		return NSDragOperationMove;
	} else if ([info draggingSource] == myController.tiVoShowTable) {
		return NSDragOperationCopy;
	} else {
		return NSDragOperationNone;
	}
}


- (BOOL)tableView:(NSTableView *)aTableView acceptDrop:(id )info row:(NSInteger)row dropOperation:(NSTableViewDropOperation)operation
{
	if (row < 0) row = 0;
	//although displayed in sorted order, need to work in actual download order
	NSUInteger insertRow;
	if (row < _sortedShows.count) {
		insertRow = [tiVoManager.downloadQueue indexOfObject: _sortedShows[row]];
	} else {
		insertRow = tiVoManager.downloadQueue.count; //just beyond end of
	}
	//move to after the completed/inprogress ones
	while (insertRow < [tiVoManager downloadQueue].count && [((MTTiVoShow *)tiVoManager.downloadQueue[insertRow]).downloadStatus intValue] != kMTStatusNew) {
		insertRow ++;
	}
	
	NSArray	*classes = [NSArray arrayWithObject:[MTTiVoShow class]];
	NSDictionary *options = [NSDictionary dictionary];
	//NSDictionary * pasteboard = [[info draggingPasteboard] propertyListForType:kMTTivoShowPasteBoardType] ;
	//NSLog(@"calling readObjects%@",pasteboard);
	NSArray	*draggedShows = [[info draggingPasteboard] readObjectsForClasses:classes options:options];
//	NSLog(@"dragging: %@", draggedShows);
	
	//dragged shows are copies, so we need to find the real show objects
	NSMutableArray * realShows = [NSMutableArray arrayWithCapacity:draggedShows.count ];
	for (MTTiVoShow * show in draggedShows) {
		MTTiVoShow * realShow= [tiVoManager findRealShow:show];
		if (realShow) [realShows addObject:realShow];
	}
	
	if( [info draggingSource] == aTableView ) {
		//reordering self (download table)
		NSIndexSet * destinationIndexes = [tiVoManager moveShowsInDownloadQueue:realShows toIndex:insertRow];
		[self selectRowIndexes:destinationIndexes byExtendingSelection:NO];
		[[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationDownloadQueueUpdated object:nil];
		return  YES;

    } else if ([info draggingSource] == myController.tiVoShowTable) {
		MTTiVoShow * insertShow = nil;
		if (insertRow < [tiVoManager downloadQueue].count) {
			insertShow = [tiVoManager.downloadQueue objectAtIndex:insertRow];
//			NSLog(@"QQQ inserting before %@",insertShow.showTitle);
		}
		[tiVoManager downloadShowsWithCurrentOptions:realShows beforeShow:insertShow];
		
		//now leave new shows selected
		NSIndexSet * showIndexes = [self.sortedShows indexesOfObjectsPassingTest:^BOOL(id obj, NSUInteger idx, BOOL *stop) {
			return [realShows indexOfObject:obj] !=NSNotFound;
		}];
		if (showIndexes.count > 0)[self selectRowIndexes:showIndexes byExtendingSelection:NO];
									
		return YES;
	} else {
		return NO;
	}
}


@end
