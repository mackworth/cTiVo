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

__DDLOGHERE__

-(id) initWithCoder:(NSCoder *)aDecoder
{
	self = [super initWithCoder:aDecoder];
	if (self) {
		[self setNotifications];
	}
	return self;
}

-(IBAction) delete:(id)sender {
	DDLogDetail(@"user request to delete shows");
	[myController removeFromDownloadQueue:sender];
}


-(void)setNotifications
{
	DDLogDetail(@"Setting up notifications");
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reloadDataDownload) name:kMTNotificationDownloadStatusChanged object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reloadDataFormat) name:kMTNotificationFormatListUpdated object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reloadDataTiVos) name:kMTNotificationTiVoListUpdated object:nil];
	[self registerForDraggedTypes:[NSArray arrayWithObjects:kMTTivoShowPasteBoardType, nil]];
	[self  setDraggingSourceOperationMask:NSDragOperationLink forLocal:NO];
	[self  setDraggingSourceOperationMask:NSDragOperationCopy forLocal:YES];


}

-(void) reloadDataTiVos {
	DDLogDetail(@"Reloading DL table from TivoListUpdated");
	[self reloadData];
	
}
-(void) reloadDataDownload {
	DDLogDetail(@"Reloading DL table from DownloadStatusChanged");
	[self reloadData];
	
}
-(void) reloadDataFormat{
	DDLogDetail(@"Reloading DL table from FormatStatusChanged");
	[self reloadData];
	
}
-(void)awakeFromNib
{  //remember: called multiple times for each new cell loaded
 	DDLogDetail(@"DL Table awakeFromNib");
   self.dataSource = self;
    self.delegate    = self;
    self.allowsMultipleSelection = YES;
	self.columnAutoresizingStyle = NSTableViewUniformColumnAutoresizingStyle;
    if (!tiVoColumnHolder) tiVoColumnHolder = [[self tableColumnWithIdentifier:@"TiVo"] retain];
}

-(void) reloadData {
    //Configure Table Columns depending on how many TiVos
    
	//save selection to restore after reload
	DDLogVerbose(@"Reloading DL table");
	NSArray * selectedShows = [self.sortedShows objectsAtIndexes: self.selectedRowIndexes];
	
	NSTableColumn *tiVoColumn = [self tableColumnWithIdentifier:@"TiVo"];
    if (tiVoManager.tiVoList.count == 1) {
        [tiVoColumn setHidden:YES];
    } else {
        [tiVoColumn setHidden:NO];
        if ([[NSUserDefaults standardUserDefaults] boolForKey:kMTHideTiVoColumnDownloads]) {
            [tiVoColumn setHidden:YES];
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
	DDLogDetail(@"Reloading DL table from SortingChanged");
	[self reloadData];
}

-(void) updateProgressInCell:(MTDownloadTableCellView *) cell forShow:(MTTiVoShow *) show {
	cell.progressIndicator.doubleValue = show.processProgress;
	cell.progressIndicator.rightText.stringValue = show.showStatus;
	[cell setNeedsDisplay:YES];

}
-(void)updateProgress
{
    NSInteger programColumnIndex = [self columnWithIdentifier:@"Programs"];
    NSInteger seriesColumnIndex = [self columnWithIdentifier:@"Series"];
	NSArray *displayedShows = self.sortedShows;
	for (int i=0; i< displayedShows.count; i++) {
		MTTiVoShow *thisShow = [displayedShows objectAtIndex:i];
		MTDownloadTableCellView *programCell = [self viewAtColumn:programColumnIndex row:i makeIfNecessary:NO];
		[self updateProgressInCell: programCell forShow: thisShow];
		MTDownloadTableCellView *seriesCell = [self viewAtColumn:seriesColumnIndex row:i makeIfNecessary:NO];
		[self updateProgressInCell: seriesCell forShow: thisShow];
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

-(NSTableCellView *)makeViewWithIdentifier:(NSString *)identifier owner:(id)owner
{
    NSTableCellView * result;
	NSTableColumn *thisColumn = [self tableColumnWithIdentifier:identifier];
    if([identifier compare: @"Programs"] == NSOrderedSame ||
	   [identifier compare: @"Series" ] == NSOrderedSame) {
        MTDownloadTableCellView *thisCell = [[[MTDownloadTableCellView alloc] initWithFrame:CGRectMake(0, 0, thisColumn.width, 20)] autorelease];
        //        result.textField.font = [NSFont userFontOfSize:14];
        thisCell.textField.editable = NO;
        
        // the identifier of the NSTextField instance is set to MyView. This
        // allows it to be re-used
        thisCell.identifier = identifier;
        result = thisCell;
    } else if([identifier compare: @"iTunes"] == NSOrderedSame) {
        MTDownloadCheckTableCell *thisCell = [[[MTDownloadCheckTableCell alloc] initWithFrame:CGRectMake(thisColumn.width/2.0-10, 0, 20, 20) withTarget:myController withAction:@selector(changeiTunes:)] autorelease];
        thisCell.identifier = identifier;
        result = thisCell;
    } else if([identifier compare: @"Simu"] == NSOrderedSame) {
        MTDownloadCheckTableCell *thisCell = [[[MTDownloadCheckTableCell alloc] initWithFrame:CGRectMake(thisColumn.width/2.0-10, 0, 20, 20) withTarget:myController withAction:@selector(changeSimultaneous:)] autorelease];
        thisCell.identifier = identifier;
        result = thisCell;
    } else if([identifier compare: @"Skip"] == NSOrderedSame) {
        MTDownloadCheckTableCell *thisCell = [[[MTDownloadCheckTableCell alloc] initWithFrame:CGRectMake(thisColumn.width/2.0-10, 0, 20, 20) withTarget:myController withAction:@selector(changeSkip:)] autorelease];
        thisCell.identifier = identifier;
        result = thisCell;
   } else if([identifier compare: @"Format"] == NSOrderedSame) {
		MTPopUpTableCellView *thisCell = [[[MTPopUpTableCellView alloc] initWithFrame:NSMakeRect(0, 0, thisColumn.width, 20) withTarget:myController withAction:@selector(selectFormat:)] autorelease];
	    thisCell.popUpButton.showHidden = NO;
		thisCell.identifier = identifier;
       result = thisCell;
    } else {
        result = (NSTableCellView*)[super makeViewWithIdentifier:identifier owner:owner];
    }
    return result;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
	MTTiVoShow *thisShow = [self.sortedShows objectAtIndex:row];
//	NSDictionary *idMapping = [NSDictionary dictionaryWithObjectsAndKeys:@"Title",@"Programs",kMTSelectedTiVo,@"TiVo",kMTSelectedFormat,@"Format", nil];
	
    // get an existing cell with the MyView identifier if it exists
	
    NSTableCellView *result = [tableView makeViewWithIdentifier:tableColumn.identifier owner:self];
    
    // There is no existing cell to reuse so we will create a new one
//    if (result == nil) {
//	This isn't getting called in 10.8, and as it always returns a MTDownload, that's a problem in anyone where it is called.
//
//        // create the new NSTextField with a frame of the {0,0} with the width of the table
//        // note that the height of the frame is not really relevant, the row-height will modify the height
//        // the new text field is then returned as an autoreleased object
//        result = [[[MTDownloadTableCellView alloc] initWithFrame:CGRectMake(0, 0, tableColumn.width, 20)] autorelease];
////        result.textField.font = [NSFont userFontOfSize:14];
//        result.editable = NO;
//        
//        // the identifier of the NSTextField instance is set to MyView. This
//        // allows it to be re-used
//        result.identifier = tableColumn.identifier;
//    }
    
    // result is now guaranteed to be valid, either as a re-used cell
    // or as a new cell, so set the stringValue of the cell to the
    // nameArray value at row
	if ([tableColumn.identifier compare:@"Programs"] == NSOrderedSame) {
		MTDownloadTableCellView *	programCell = (MTDownloadTableCellView *) result;
		programCell.progressIndicator.leftText.stringValue = thisShow.showTitle ;
        programCell.toolTip = thisShow.showTitle;
		[self updateProgressInCell:programCell forShow:thisShow];
			
	} else if ([tableColumn.identifier compare:@"Series"] == NSOrderedSame) {
		MTDownloadTableCellView *	seriesCell = (MTDownloadTableCellView *) result;
		seriesCell.progressIndicator.leftText.stringValue = thisShow.seriesTitle;
		seriesCell.toolTip = thisShow.seriesTitle;
		[self updateProgressInCell:seriesCell forShow:thisShow];
    } else if ([tableColumn.identifier compare:@"TiVo"] == NSOrderedSame) {
        result.textField.stringValue = thisShow.tiVo.tiVo.name ;
        result.toolTip = result.textField.stringValue;
        result.textField.textColor = [NSColor blackColor];
        if (!thisShow.tiVo.isReachable && thisShow.isDownloading) {
            result.textField.textColor = [NSColor redColor];
        }
        
    } else if ([tableColumn.identifier compare:@"Order"] == NSOrderedSame) {
        result.textField.stringValue = [NSString stringWithFormat:@"%@",thisShow.downloadIndex] ;
        result.toolTip = result.textField.stringValue;
        
    } else if ([tableColumn.identifier compare:@"Format"] == NSOrderedSame) {
		MTPopUpTableCellView * cell = (MTPopUpTableCellView *)result;
		MTFormatPopUpButton *popUpButton = cell.popUpButton;
		popUpButton.owner = thisShow;
       if (thisShow.isNew) {
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
        [checkBox setEnabled: !thisShow.isDone &&
                              thisShow.encodeFormat.canAddToiTunes ];
         checkBox.owner = thisShow;

 	} else if ([tableColumn.identifier compare:@"Simu"] == NSOrderedSame) {
        MTCheckBox * checkBox = ((MTDownloadCheckTableCell *)result).checkBox;
        [checkBox setOn: thisShow.simultaneousEncode];
        checkBox.owner = thisShow;
        [checkBox setEnabled: thisShow.isNew && thisShow.encodeFormat.canSimulEncode];
        
 	} else if ([tableColumn.identifier compare:@"Skip"] == NSOrderedSame) {
        MTCheckBox * checkBox = ((MTDownloadCheckTableCell *)result).checkBox;
        [checkBox setOn: thisShow.skipCommercials];
        checkBox.owner = thisShow;
        [checkBox setEnabled: thisShow.isNew && thisShow.encodeFormat.canSkip];
        
	} else if ([tableColumn.identifier compare:@"Date"] == NSOrderedSame) {
		if ([tableColumn width] > 135) {
			result.textField.stringValue = thisShow.showMediumDateString;
		} else {
			result.textField.stringValue = thisShow.showDateString;
		}
		result.toolTip = result.textField.stringValue;
	} else if ([tableColumn.identifier compare:@"Length"] == NSOrderedSame) {
		result.textField.stringValue = thisShow.lengthString;
       result.toolTip = result.textField.stringValue;
	} else if ([tableColumn.identifier compare:@"Episode"] == NSOrderedSame) {
		result.textField.stringValue = thisShow.seasonEpisode;
        result.toolTip = result.textField.stringValue;
	} else if ([tableColumn.identifier compare:@"Queued"] == NSOrderedSame) {
		result.textField.stringValue = thisShow.isQueuedString;
	} else if ([tableColumn.identifier compare:@"HD"] == NSOrderedSame) {
		result.textField.stringValue = thisShow.isHDString;
		result.textField.alignment = NSCenterTextAlignment;
	} else if ([tableColumn.identifier compare:@"Channel"] == NSOrderedSame) {
		result.textField.stringValue = thisShow.channelString;
	} else if ([tableColumn.identifier compare:@"Size"] == NSOrderedSame) {
		result.textField.stringValue = thisShow.sizeString;
	} else if ([tableColumn.identifier compare:@"TiVoID"] == NSOrderedSame) {
		result.textField.stringValue = thisShow.idString;
	} else if ([tableColumn.identifier compare:@"Title"] == NSOrderedSame) {
		result.textField.stringValue = thisShow.episodeTitle;
		result.toolTip = result.textField.stringValue;
	} else if ([tableColumn.identifier compare:@"Station"] == NSOrderedSame) {
		result.textField.stringValue = thisShow.stationCallsign;
	} else if ([tableColumn.identifier compare:@"Genre"] == NSOrderedSame) {
		result.textField.stringValue = thisShow.episodeGenre;
        result.toolTip = result.textField.stringValue;
	} else if ([tableColumn.identifier compare:@"FirstAirDate"] == NSOrderedSame) {
		result.textField.stringValue = thisShow.originalAirDateNoTime ? thisShow.originalAirDateNoTime : @"";
	} else {
		DDLogReport(@"Unknown Column: %@ ",tableColumn.identifier);
	}
    
    // return the result.
    return result;
    
}
  
#pragma mark Drag N Drop support

//Drag&Drop Source:

- (NSDragOperation)draggingSession:(NSDraggingSession *)session sourceOperationMaskForDraggingContext:(NSDraggingContext)context {
	
    switch(context) {
        case NSDraggingContextOutsideApplication:
            return NSDragOperationGeneric | NSDragOperationCopy | NSDragOperationMove | NSDragOperationDelete;
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
	NSLog(@"copying objects:%@",selectedObjects );
	[pboard clearContents];
	[pboard writeObjects:selectedObjects];
	DDLogVerbose (@"DraggingObjects: %@",selectedObjects);
	NSLog(@"property Types available: %@",[pboard types]);
	NSLog(@"Property list: URLS: %@", [pboard
	 readObjectsForClasses:[NSArray arrayWithObject:[NSURL class]]
	 options:[NSDictionary dictionaryWithObject:[NSNumber
												 numberWithBool:YES]
										 forKey:NSPasteboardURLReadingFileURLsOnlyKey]]);
	return YES;
}

-(void) draggedImage:(NSImage *)image endedAt:(NSPoint)screenPoint operation:(NSDragOperation)operation {
	//pre 10.7
	if (operation == NSDragOperationDelete) {
		DDLogDetail(@"User dragged to trash");
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
		DDLogDetail(@"User dragged within DL Table");
		return NSDragOperationMove;
	} else if ([info draggingSource] == myController.tiVoShowTable) {
		DDLogDetail(@"User dragged from TivoShow Table");
		return NSDragOperationCopy;
	} else {
		return NSDragOperationNone;
	}
}

-(BOOL)shows:(NSArray *)shows contain:(MTTiVo *)tiVo
{
	for (MTTiVoShow * show in shows) {
		if (show.tiVo  == tiVo) {
			return  YES;
		}
	}
	return NO;
}

-(BOOL)selectionContainsCompletedShows
{
    NSIndexSet *selectedRowIndexes = [self selectedRowIndexes];
	NSArray *selectedShows = [self.sortedShows objectsAtIndexes:selectedRowIndexes];
	for (MTTiVoShow *show in selectedShows) {
		if ([show videoFileURLWithEncrypted:YES]) {
			//minor bug: we enable play video even though you can't play encrypted
			return  YES;
		}
	}
	return NO;
	
}

-(BOOL)playVideo
{
	NSIndexSet *selectedRowIndexes = [self selectedRowIndexes];
	NSArray *selectedShows = [self.sortedShows objectsAtIndexes:selectedRowIndexes];
	for (MTTiVoShow *show in selectedShows) {
		if (show.isDone) {
			if ([show playVideo])  {
				return YES;		}
		}
	}
	return NO;
}

-(BOOL)revealInFinder
{
	NSIndexSet *selectedRowIndexes = [self selectedRowIndexes];
	NSArray *selectedShows = [self.sortedShows objectsAtIndexes:selectedRowIndexes];
	NSMutableArray * showURLs = [NSMutableArray arrayWithCapacity:selectedShows.count];
	for (MTTiVoShow *show in selectedShows) {
		NSURL * showURL = [show videoFileURLWithEncrypted:YES];
		if (showURL) {
			[showURLs addObject:showURL];
		}
	}
	if (showURLs.count > 0) {
		[[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:showURLs];
		return YES;
	} else{
		return NO;
	}
}



-(void) askReschedule: (MTTiVoShow *) show {
	//ask user if they'd like to reschedule a show that's being demoted
	NSString *message = [NSString stringWithFormat:@"Do you want to reschedule %@?",show.showTitle];
	NSAlert *insertDownloadAlert = [NSAlert alertWithMessageText:message defaultButton:@"Reschedule" alternateButton:@"No" otherButton:nil informativeTextWithFormat:@""];
	NSInteger returnValue = [insertDownloadAlert runModal];
	if (returnValue == 1) {
		DDLogDetail(@"User did reschedule active show %@",show);
		[show rescheduleShowWithDecrementRetries:@(NO)];
	}
}

-(BOOL) askRestarting: (NSArray *) restartShows {
	//ask user if they'd like to reschedule a show that's being demoted
	if (restartShows.count ==0) return NO;
	MTTiVoShow * exampleShow = restartShows[0];
	NSString * message;
	if (restartShows.count ==1) {
		message =  [NSString stringWithFormat:@"Do you want to re-download %@?",exampleShow.showTitle];
	} else {
		message = [NSString stringWithFormat:@"Do you want to re-download %@ and other completed shows?",exampleShow.showTitle];
	}
	NSAlert *insertDownloadAlert = [NSAlert alertWithMessageText:message defaultButton:@"Re-download" alternateButton:@"No" otherButton:nil informativeTextWithFormat:@""];
	NSInteger returnValue = [insertDownloadAlert runModal];
	if (returnValue == 1) {
		return YES;
	} else {
		return NO;
	}
}

- (BOOL)tableView:(NSTableView *)aTableView acceptDrop:(id )info row:(NSInteger)row dropOperation:(NSTableViewDropOperation)operation
{
	NSArray	*classes = [NSArray arrayWithObject:[MTTiVoShow class]];
	NSDictionary *options = [NSDictionary dictionary];
	//NSDictionary * pasteboard = [[info draggingPasteboard] propertyListForType:kMTTivoShowPasteBoardType] ;
	//NSLog(@"calling readObjects%@",pasteboard);
	NSArray	*draggedShows = [[info draggingPasteboard] readObjectsForClasses:classes options:options];
	DDLogDetail(@"Accepting drop: %@", draggedShows);

	if (row < 0) row = 0;
	//although displayed in sorted order, need to work in actual download order
	NSUInteger insertRow;
	MTTiVoShow * insertTarget = nil;
	
	if (row < _sortedShows.count) {
		insertTarget = _sortedShows[row];
		insertRow = [tiVoManager.downloadQueue indexOfObject: insertTarget];
	} else {
		insertRow = tiVoManager.downloadQueue.count; //just beyond end of array
	}
	
	//dragged shows are copies, so we need to find the real show objects
	NSMutableArray * realShows = [NSMutableArray arrayWithCapacity:draggedShows.count ];
	NSMutableArray * completedShowsBeingMoved =[NSMutableArray array];
	for (MTTiVoShow * show in draggedShows) {
		MTTiVoShow * realShow= [tiVoManager findRealShow:show];
		if (realShow) [realShows addObject:realShow];
		if (realShow.isDone) [completedShowsBeingMoved addObject:realShow];
			
	}
	DDLogVerbose(@"Real Shows being dragged: %@",realShows);
	
	//see if we have any completed shows being re-downloaded
	if (completedShowsBeingMoved.count>0 &&
		(!insertTarget || insertTarget.isNew)) {
		//we're moving at least some completedshows below the activeline
		if([self askRestarting:completedShowsBeingMoved]) {
			for (MTTiVoShow * show in completedShowsBeingMoved) {
				[show prepForResubmit];
			}
		};
	}
	
	//Now look for reschedulings. Group ould be moving up or down, with or without an active show...
	for (MTTiVoShow * activeShow in [tiVoManager downloadQueue]) {
		if (activeShow.isNew) break;  //we're through any active ones
		if (activeShow.isDone) continue;
		NSUInteger activeRow = [[tiVoManager downloadQueue] indexOfObject:activeShow];
		//first check if a show is being moved before activeShow
		if ([realShows containsObject: activeShow]) {
			//I'm in group being moved ( so group is from in DL queue
			if (insertRow > activeRow+1) {   //moving downwards
				for (NSUInteger i = activeRow+1; i<insertRow; i++) { //check shows we're skipping over
					MTTiVoShow * promotedShow = [[tiVoManager downloadQueue] objectAtIndex:i];
					if (![realShows containsObject:promotedShow]) {//but if it's coming with me, no need
						if (activeShow.tiVo == promotedShow.tiVo) {
							[self askReschedule:activeShow];
							break;  // no need to ask again
						}
					}
				}
			}
	} else {
			//I'm not being moved
			if ((insertRow <= activeRow) &&   //shows being moved above me
				([self shows:realShows  contain:activeShow.tiVo]))  {//and one of them is on same TiVo as me
				[self askReschedule: activeShow];
			}
		}
	}
	
	//	NSLog(@"dragging: %@", draggedShows);
	
	if( [info draggingSource] == aTableView ) {
		//reordering self (download table)
		DDLogVerbose(@"moving shows to %ld: %@", insertRow, [tiVoManager downloadQueue]);
		[tiVoManager moveShowsInDownloadQueue:realShows toIndex:insertRow];
		DDLogVerbose(@"moved shows to %ld: %@", insertRow, [tiVoManager downloadQueue]);

    } else if ([info draggingSource] == myController.tiVoShowTable) {
		DDLogVerbose(@"Scheduling shows at %ld",(unsigned long)insertRow );
		MTTiVoShow * insertShow = nil;
		if (insertRow < [tiVoManager downloadQueue].count) {
			insertShow = [tiVoManager.downloadQueue objectAtIndex:insertRow];
			DDLogVerbose(@"Inserting before %@",insertShow.showTitle);
		}
		[tiVoManager downloadShowsWithCurrentOptions:realShows beforeShow:insertShow];
		
		//note that dragged copies will now be dealloc'ed 								
	} else {
		return NO;
	}
	
	self.sortedShows = nil;
	[tiVoManager sortDownloadQueue];
	DDLogVerbose(@"afterSort: %@", [tiVoManager downloadQueue]);
	
	NSIndexSet * selectionIndexes = [self.sortedShows indexesOfObjectsPassingTest:^BOOL(id obj, NSUInteger idx, BOOL *stop) {
			return [realShows indexOfObject:obj] !=NSNotFound;
		}];

	//now leave new shows selected
	DDLogVerbose(@"moved to %@",selectionIndexes );
	[self selectRowIndexes:selectionIndexes byExtendingSelection:NO];
	[self reloadData];
	return YES;
}


@end
