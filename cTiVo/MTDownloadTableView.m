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
@synthesize  sortedDownloads= _sortedDownloads;

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
	[self registerForDraggedTypes:[NSArray arrayWithObjects:kMTTivoShowPasteBoardType, kMTDownloadPasteBoardType, nil]];
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
	NSArray * selectedShows = [self.sortedDownloads objectsAtIndexes: self.selectedRowIndexes];
	
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
    self.sortedDownloads =nil;
    [super reloadData];
	
	//now restore selection
	NSIndexSet * showIndexes = [self.sortedDownloads indexesOfObjectsPassingTest:^BOOL(id obj, NSUInteger idx, BOOL *stop) {
		return [selectedShows indexOfObject:obj] !=NSNotFound;
	}];
	
	[self selectRowIndexes:showIndexes byExtendingSelection:NO];
}

-(NSArray *)sortedDownloads
{
	if (!_sortedDownloads) {
        self.sortedDownloads = [tiVoManager currentDownloadQueueSortedBy: self.sortDescriptors];
    }
    return _sortedDownloads;
}

-(void)tableView:(NSTableView *)tableView sortDescriptorsDidChange:(NSArray *)oldDescriptors
{
	DDLogDetail(@"Reloading DL table from SortingChanged");
	[self reloadData];
}

-(void) updateProgressInCell:(MTDownloadTableCellView *) cell forDL:(MTDownload *) download {
	cell.progressIndicator.doubleValue = download.processProgress;
	cell.progressIndicator.rightText.stringValue = download.showStatus;
	[cell setNeedsDisplay:YES];

}
-(void)updateProgress
{
    NSInteger programColumnIndex = [self columnWithIdentifier:@"Programs"];
    NSInteger seriesColumnIndex = [self columnWithIdentifier:@"Series"];
	NSArray *displayedShows = self.sortedDownloads;
	for (int i=0; i< displayedShows.count; i++) {
		MTDownload *thisDownload = [displayedShows objectAtIndex:i];
		MTDownloadTableCellView *programCell = [self viewAtColumn:programColumnIndex row:i makeIfNecessary:NO];
		[self updateProgressInCell: programCell forDL: thisDownload];
		MTDownloadTableCellView *seriesCell = [self viewAtColumn:seriesColumnIndex row:i makeIfNecessary:NO];
		[self updateProgressInCell: seriesCell forDL: thisDownload];
	}
		
}

-(void)dealloc
{
	[self  unregisterDraggedTypes];
	[tiVoColumnHolder release]; tiVoColumnHolder=nil;
    self.sortedDownloads= nil;
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [super dealloc];
}

#pragma mark - Table Delegate Protocol

-(void)tableViewSelectionDidChange:(NSNotification *)notification
{
    NSIndexSet *selectedRowIndexes = [self selectedRowIndexes];
    if (selectedRowIndexes.count == 1) {
        NSArray *selectedRows = [self.sortedDownloads objectsAtIndexes:selectedRowIndexes];
		MTTiVoShow * show = ((MTDownload *) selectedRows[0]).show;
		if (!show.protectedShow.boolValue) {
			[myController setValue:show forKey:@"showForDetail"];
		}
    }
}

#pragma mark - Table Data Source Protocol

- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView
{
    return self.sortedDownloads.count;
}

- (void)tableView:(NSTableView *)tableView didAddRowView:(NSTableRowView *)rowView forRow:(NSInteger)row
{
    MTDownload *download = [self.sortedDownloads objectAtIndex:row];
    if ([download.show.protectedShow boolValue]) {
        rowView.selectionHighlightStyle = NSTableViewSelectionHighlightStyleNone;
    } else {
        rowView.selectionHighlightStyle = NSTableViewSelectionHighlightStyleRegular;
    }
}

-(NSTableCellView *)makeViewWithIdentifier:(NSString *)identifier owner:(id)owner
{
    NSTableCellView * result;
	NSTableColumn *thisColumn = [self tableColumnWithIdentifier:identifier];
    if([identifier isEqualToString: @"Programs"] ||
	   [identifier isEqualToString: @"Series" ]) {
        MTDownloadTableCellView *thisCell = [[[MTDownloadTableCellView alloc] initWithFrame:CGRectMake(0, 0, thisColumn.width, 20)] autorelease];
        //        result.textField.font = [NSFont userFontOfSize:14];
        thisCell.textField.editable = NO;
        
        // the identifier of the NSTextField instance is set to MyView. This
        // allows it to be re-used
        thisCell.identifier = identifier;
        result = thisCell;
    } else if([identifier isEqualToString: @"iTunes"]) {
        MTDownloadCheckTableCell *thisCell = [[[MTDownloadCheckTableCell alloc] initWithFrame:CGRectMake(thisColumn.width/2.0-10, 0, 20, 20) withTarget:myController withAction:@selector(changeiTunes:)] autorelease];
        thisCell.identifier = identifier;
        result = thisCell;
    } else if([identifier isEqualToString: @"Simu"]) {
        MTDownloadCheckTableCell *thisCell = [[[MTDownloadCheckTableCell alloc] initWithFrame:CGRectMake(thisColumn.width/2.0-10, 0, 20, 20) withTarget:myController withAction:@selector(changeSimultaneous:)] autorelease];
        thisCell.identifier = identifier;
        result = thisCell;
    } else if([identifier isEqualToString: @"Skip"]) {
        MTDownloadCheckTableCell *thisCell = [[[MTDownloadCheckTableCell alloc] initWithFrame:CGRectMake(thisColumn.width/2.0-10, 0, 20, 20) withTarget:myController withAction:@selector(changeSkip:)] autorelease];
        thisCell.identifier = identifier;
        result = thisCell;
    } else if([identifier isEqualToString: @"XML"]) {
        MTDownloadCheckTableCell *thisCell = [[[MTDownloadCheckTableCell alloc] initWithFrame:CGRectMake(thisColumn.width/2.0-10, 0, 20, 20) withTarget:myController withAction:@selector(changeXML:)] autorelease];
        thisCell.identifier = identifier;
        result = thisCell;
    } else if([identifier isEqualToString: @"pyTiVo"]) {
        MTDownloadCheckTableCell *thisCell = [[[MTDownloadCheckTableCell alloc] initWithFrame:CGRectMake(thisColumn.width/2.0-10, 0, 20, 20) withTarget:myController withAction:@selector(changepyTiVo:)] autorelease];
        thisCell.identifier = identifier;
        result = thisCell;
    } else if([identifier isEqualToString: @"Metadata"]) {
        MTDownloadCheckTableCell *thisCell = [[[MTDownloadCheckTableCell alloc] initWithFrame:CGRectMake(thisColumn.width/2.0-10, 0, 20, 20) withTarget:myController withAction:@selector(changeMetadata:)] autorelease];
        thisCell.identifier = identifier;
        result = thisCell;
    } else if([identifier isEqualToString: @"Subtitles"]) {
        MTDownloadCheckTableCell *thisCell = [[[MTDownloadCheckTableCell alloc] initWithFrame:CGRectMake(thisColumn.width/2.0-10, 0, 20, 20) withTarget:myController withAction:@selector(changeSubtitle:)] autorelease];
        thisCell.identifier = identifier;
        result = thisCell;
   } else if([identifier isEqualToString: @"Format"]) {
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
	MTDownload *download = [self.sortedDownloads objectAtIndex:row];
	MTTiVoShow * thisShow = download.show;
	BOOL protected = thisShow.protectedShow.boolValue;
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
	NSString *textVal = nil;
	result.toolTip = nil;
	if ([tableColumn.identifier isEqualToString:@"Programs"] ||
		[tableColumn.identifier isEqualToString:@"Series"]) {
		NSString * cellVal;
		if ([tableColumn.identifier isEqualToString:@"Programs"]) {
			cellVal = thisShow.showTitle ;
		 } else {
			 cellVal = thisShow.seriesTitle ;
		 }
		MTDownloadTableCellView *	cell = (MTDownloadTableCellView *) result;
		cell.progressIndicator.leftText.stringValue = cellVal;
		cell.toolTip = cellVal;
		[self updateProgressInCell:cell forDL:download];
		if ([thisShow.protectedShow boolValue]) {
			cell.progressIndicator.foregroundTextColor = [NSColor grayColor];
		} else {
			cell.progressIndicator.foregroundTextColor = [NSColor blackColor];
		}
   } else if ([tableColumn.identifier isEqualToString:@"TiVo"]) {
        textVal = thisShow.tiVoName ;
        result.textField.textColor = [NSColor blackColor];
        if (!thisShow.tiVo.isReachable && download.isDownloading) {
            result.textField.textColor = [NSColor redColor];
        }
        
    } else if ([tableColumn.identifier isEqualToString:@"Order"]) {
        textVal = [NSString stringWithFormat:@"%@",download.downloadIndex] ;
        
    } else if ([tableColumn.identifier isEqualToString:@"Format"]) {
		MTPopUpTableCellView * cell = (MTPopUpTableCellView *)result;
		MTFormatPopUpButton *popUpButton = cell.popUpButton;
		popUpButton.owner = download;
       if (download.isNew) {
		    popUpButton.owner = download;
			popUpButton.formatList = tiVoManager.formatList;
			//ensure this format is still "available"
			download.encodeFormat = [popUpButton selectFormatNamed:download.encodeFormat.name];
			popUpButton.hidden = NO;
			cell.textField.hidden= YES;
	   } else {
			//can't change now; just let them know what it is/was
		   textVal = download.encodeFormat.name;
		   popUpButton.hidden = YES;
		   cell.textField.hidden= NO;
		}
    } else if ([tableColumn.identifier isEqualToString:@"iTunes"]) {
        MTCheckBox * checkBox = ((MTDownloadCheckTableCell *)result).checkBox;
        [checkBox setOn: download.addToiTunesWhenEncoded];
        [checkBox setEnabled: !download.isDone && !protected &&
                              download.encodeFormat.canAddToiTunes ];
         checkBox.owner = download;

 	} else if ([tableColumn.identifier isEqualToString:@"Simu"]) {
        MTCheckBox * checkBox = ((MTDownloadCheckTableCell *)result).checkBox;
        [checkBox setOn: download.simultaneousEncode];
        checkBox.owner = download;
        [checkBox setEnabled: download.isNew && !protected && download.encodeFormat.canSimulEncode];
        
 	} else if ([tableColumn.identifier isEqualToString:@"Skip"]) {
        MTCheckBox * checkBox = ((MTDownloadCheckTableCell *)result).checkBox;
        [checkBox setOn: download.skipCommercials];
        checkBox.owner = download;
        [checkBox setEnabled: download.isNew && !protected && download.encodeFormat.canSkip];
        
 	} else if ([tableColumn.identifier isEqualToString:@"XML"]) {
        MTCheckBox * checkBox = ((MTDownloadCheckTableCell *)result).checkBox;
        [checkBox setOn: download.genXMLMetaData.boolValue];
        checkBox.owner = download;
		checkBox.enabled = !download.isDone && !protected;
	} else if ([tableColumn.identifier isEqualToString:@"pyTiVo"]) {
        MTCheckBox * checkBox = ((MTDownloadCheckTableCell *)result).checkBox;
        [checkBox setOn: download.genTextMetaData.boolValue];
        checkBox.owner = download;
		checkBox.enabled = !download.isDone && !protected;
	} else if ([tableColumn.identifier isEqualToString:@"Subtitles"]) {
        MTCheckBox * checkBox = ((MTDownloadCheckTableCell *)result).checkBox;
        [checkBox setOn: download.exportSubtitles.boolValue];
        checkBox.owner = download;
		checkBox.enabled = download.isNew && !protected;
	} else if ([tableColumn.identifier isEqualToString:@"Metadata"]) {
        MTCheckBox * checkBox = ((MTDownloadCheckTableCell *)result).checkBox;
        [checkBox setOn: download.includeAPMMetaData.boolValue && download.encodeFormat.canAtomicParsley];
        checkBox.owner = download;
		checkBox.enabled = download.encodeFormat.canAtomicParsley && !download.isDone && !protected;
  	} else if ([tableColumn.identifier isEqualToString:@"Date"]) {
		if ([tableColumn width] > 135) {
			textVal = thisShow.showMediumDateString;
		} else {
			textVal = thisShow.showDateString;
		}
	} else if ([tableColumn.identifier isEqualToString:@"Length"]) {
		textVal = thisShow.lengthString;
 	} else if ([tableColumn.identifier isEqualToString:@"Episode"]) {
		textVal = thisShow.seasonEpisode;
	} else if ([tableColumn.identifier isEqualToString:@"Queued"]) {
		textVal = thisShow.isQueuedString;
		result.textField.toolTip =@"Is program in queue to download?";
	} else if ([tableColumn.identifier isEqualToString:@"HD"]) {
		textVal = thisShow.isHDString;
		result.textField.alignment = NSCenterTextAlignment;
		result.textField.toolTip =@"Is program recorded in HD?";
	} else if ([tableColumn.identifier isEqualToString:@"Channel"]) {
		textVal = thisShow.channelString;
	} else if ([tableColumn.identifier isEqualToString:@"Size"]) {
		textVal = thisShow.sizeString;
	} else if ([tableColumn.identifier isEqualToString:@"TiVoID"]) {
		textVal = thisShow.idString;
	} else if ([tableColumn.identifier isEqualToString:@"Title"]) {
		textVal = thisShow.episodeTitle;
	} else if ([tableColumn.identifier isEqualToString:@"Station"]) {
		textVal = thisShow.stationCallsign;
	} else if ([tableColumn.identifier isEqualToString:@"Genre"]) {
		textVal = thisShow.episodeGenre;
	} else if ([tableColumn.identifier isEqualToString:@"FirstAirDate"]) {
		textVal = thisShow.originalAirDateNoTime;
	} else {
		DDLogReport(@"Unknown Column: %@ ",tableColumn.identifier);
	}
	result.textField.stringValue = textVal ? textVal: @"";
	if (!result.toolTip) result.toolTip = textVal;
    // return the result.
	if ([thisShow.protectedShow boolValue]) {
        result.textField.textColor = [NSColor grayColor];
    } else {
        result.textField.textColor = [NSColor blackColor];
    }
	
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
		if (c < 0) 	c = 0;
		if (c > tv.numberOfColumns) c = tv.numberOfColumns;
		if (r < 0) r = 0;
		if (r > tv.numberOfRows) r = tv.numberOfRows;
		NSTableColumn *selectedColumn = tv.tableColumns[c];
		BOOL isSelectedRow = [tv isRowSelected:r];
		BOOL isOverText = NO;
		if ([selectedColumn.identifier isEqualToString:@"Programs"]) { //Check if over text
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
 	NSArray	*selectedObjects = [self.sortedDownloads objectsAtIndexes:rowIndexes ];
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

-(BOOL)downloads:(NSArray *)downloads contain:(MTTiVo *)tiVo
{
	for (MTDownload * download in downloads) {
		if (download.show.tiVo  == tiVo) {
			return  YES;
		}
	}
	return NO;
}

-(BOOL)selectionContainsCompletedShows
{
    NSIndexSet *selectedRowIndexes = [self selectedRowIndexes];
	NSArray *selectedShows = [self.sortedDownloads objectsAtIndexes:selectedRowIndexes];
	for (MTDownload *show in selectedShows) {
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
	NSArray *selectedShows = [self.sortedDownloads objectsAtIndexes:selectedRowIndexes];
	for (MTDownload *show in selectedShows) {
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
	NSArray *selectedShows = [self.sortedDownloads objectsAtIndexes:selectedRowIndexes];
	NSMutableArray * showURLs = [NSMutableArray arrayWithCapacity:selectedShows.count];
	for (MTDownload *show in selectedShows) {
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



-(BOOL) askReschedule: (MTDownload *) download {
	//ask user if they'd like to reschedule a show that's being demoted
	NSString *message = [NSString stringWithFormat:@"Do you want to reschedule %@?",download.show.showTitle];
	NSAlert *insertDownloadAlert = [NSAlert alertWithMessageText:message defaultButton:@"Reschedule" alternateButton:@"No" otherButton:nil informativeTextWithFormat:@""];
	NSInteger returnValue = [insertDownloadAlert runModal];
	if (returnValue == 1) {
		DDLogDetail(@"User did reschedule active show %@",download);
		[download prepareForDownload: YES];
		return YES;
	} else {
		return NO;
	}
}

-(BOOL) askRestarting: (NSArray *) restartShows {
	//ask user if they'd like to reschedule a show that's being demoted
	if (restartShows.count ==0) return NO;
	NSString * exampleShow = ((MTDownload *)restartShows[0]).show.showTitle;
	NSString * message;
	if (restartShows.count ==1) {
		message =  [NSString stringWithFormat:@"Do you want to re-download %@?",exampleShow];
	} else {
		message = [NSString stringWithFormat:@"Do you want to re-download %@ and other completed shows?",exampleShow];
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
	if (row < 0) row = 0;
	//although displayed in sorted order, need to work in actual download order
	MTDownload * insertTarget = nil;
	NSUInteger insertRow = [tiVoManager downloadQueue].count;
	
	if (row < _sortedDownloads.count) {
		insertTarget = _sortedDownloads[row];
		insertRow = [[tiVoManager downloadQueue] indexOfObject:insertTarget];
	}

	if ([info draggingSource] == myController.tiVoShowTable) {
		NSArray	*classes = @[[MTTiVoShow class]];
		NSDictionary *options = [NSDictionary dictionary];
		NSArray	*draggedShows = [[info draggingPasteboard] readObjectsForClasses:classes options:options];
		DDLogDetail(@"Accepting drop: %@", draggedShows);
	
		//dragged shows are proxies, so we need to find the real show objects
		NSMutableArray * realShows = [NSMutableArray arrayWithCapacity:draggedShows.count ];

		for (MTTiVoShow * show in draggedShows) {
			MTTiVoShow * realShow= [tiVoManager findRealShow:show];
			if (realShow) [realShows addObject:realShow];
		}
		DDLogVerbose(@"Scheduling shows before %@", insertTarget);
		//need to move insertTarget below
		
		for (MTTiVoShow *realShow in realShows) {
			
			for (NSUInteger activeRow = insertRow; activeRow < tiVoManager.downloadQueue.count ; activeRow++ ) {
				MTDownload * activeDL = tiVoManager.downloadQueue[activeRow];
				if (activeDL.isNew) continue;  
				if (activeDL.isDone) continue;
				if (activeDL.show.tiVo == realShow.tiVo) {
					if (![self askReschedule:activeDL]) {
						return NO;
					};
				}
			}
		}

		
		[tiVoManager downloadShowsWithCurrentOptions:realShows beforeDownload:insertTarget];
		
		self.sortedDownloads = nil;
		[tiVoManager sortDownloadQueue];
		DDLogVerbose(@"afterSort: %@", self.sortedDownloads);
		
		NSIndexSet * selectionIndexes = [self.sortedDownloads indexesOfObjectsPassingTest:^BOOL(id obj, NSUInteger idx, BOOL *stop) {
			MTDownload * download = (MTDownload *) obj;
			return [realShows indexOfObject:download.show] !=NSNotFound;
		}];
		
		//now leave new shows selected
		DDLogVerbose(@"moved to %@",selectionIndexes );
		[self selectRowIndexes:selectionIndexes byExtendingSelection:NO];
		//note that dragged copies will now be dealloc'ed
	
	} else if( [info draggingSource] == aTableView ) {
		NSArray	*classes = @[[MTDownload class]];
		NSDictionary *options = [NSDictionary dictionary];
		NSArray	*draggedDLs = [[info draggingPasteboard] readObjectsForClasses:classes options:options];
		DDLogDetail(@"Accepting drop: %@", draggedDLs);
				
		//dragged downloads are proxies, so we need to find the real download objects
		NSMutableArray * realDLs = [NSMutableArray arrayWithCapacity:draggedDLs.count ];
		NSMutableArray * completedDownloadsBeingMoved =[NSMutableArray array];
		for (MTDownload * download in draggedDLs) {
			MTDownload * realDownload= [tiVoManager findRealDownload:download];
			if (realDownload) [realDLs addObject:realDownload];
			if (realDownload.isDone) [completedDownloadsBeingMoved addObject:download];
		}
		
		//Now look for reschedulings. Group could either be moving up over an active show, or moving an active show down...

		for (MTDownload * activeDL in [tiVoManager downloadQueue]) {
			if (activeDL.isNew) break;  //we're through any active ones
			if (activeDL.isDone) continue;
			NSUInteger activeRow = [[tiVoManager downloadQueue] indexOfObject:activeDL];

			if ([draggedDLs containsObject: activeDL]) {
				//I'm in group being moved 
				if (insertRow > activeRow+1) {   //moving downwards
					for (NSUInteger i = activeRow+1; i<insertRow; i++) { //check shows we're skipping over
						MTDownload * promotedDL = [[tiVoManager downloadQueue] objectAtIndex:i];
						if (![realDLs containsObject:promotedDL]) {//but if it's coming with me, no need
							if (activeDL.show.tiVo == promotedDL.show.tiVo) {
								[self askReschedule:activeDL];
								break;  // no need to ask again
							}
						}
					}
				}
			} else {
				//I'm not being moved
				if ((insertRow <= activeRow) &&   //shows being moved above me
					([self downloads:realDLs  contain:activeDL.show.tiVo]))  {//and one of them is on same TiVo as me
					[self askReschedule: activeDL];
				}
			}
		}
		DDLogVerbose(@"Real downloads being dragged: %@",realDLs);
		
		//see if we have any completed shows being re-downloaded
		if (completedDownloadsBeingMoved.count>0 &&
			(!insertTarget || !insertTarget.isDone)) {
			//we're moving at least some completedshows below the activeline
			if([self askRestarting:completedDownloadsBeingMoved]) {
				for (MTDownload * download in completedDownloadsBeingMoved) {
					[download prepareForDownload: YES];
				}
			};
		}
		//reordering self (download table)
		[tiVoManager moveShowsInDownloadQueue:realDLs toIndex:insertRow];
		
		
		self.sortedDownloads = nil;
		[tiVoManager sortDownloadQueue];
		DDLogVerbose(@"afterSort: %@", self.sortedDownloads);
		
		NSIndexSet * selectionIndexes = [self.sortedDownloads indexesOfObjectsPassingTest:^BOOL(id obj, NSUInteger idx, BOOL *stop) {
			return [realDLs indexOfObject:obj] !=NSNotFound;
		}];
		
		//now leave new shows selected
		DDLogVerbose(@"moved to %@",selectionIndexes );
		[self selectRowIndexes:selectionIndexes byExtendingSelection:NO];
		
	} else {
		return NO;
	}
	

	[self reloadData];
	return YES;
}


@end
