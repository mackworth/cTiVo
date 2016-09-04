//
//  MTDownloadList.m
//  myTivo
//
//  Created by Scott Buchanan on 12/8/12.
//  Copyright (c) 2012 Scott Buchanan. All rights reserved.
//

#import "MTDownloadTableView.h"
#import "MTPopUpTableCellView.h"
#import "NSString+Helpers.h"

@interface MTDownloadTableView ()

@property (nonatomic, readonly) BOOL showingProgramsColumn;
@property (nonatomic, strong) NSTimer *updateTimer;
@end

@implementation MTDownloadTableView
@synthesize  sortedDownloads= _sortedDownloads;

__DDLOGHERE__

-(id) initWithCoder:(NSCoder *)aDecoder
{
	self = [super initWithCoder:aDecoder];
	if (self) {
		[self setNotifications];
        self.dataSource = self;
        self.delegate    = self;
        self.allowsMultipleSelection = YES;
        self.columnAutoresizingStyle = NSTableViewUniformColumnAutoresizingStyle;
        if (!tiVoColumnHolder) tiVoColumnHolder = [self tableColumnWithIdentifier:@"TiVo"];
        NSTableColumn *tiVoColumn = [self tableColumnWithIdentifier:@"TiVo"];
        if (![[NSUserDefaults standardUserDefaults] boolForKey:kMTHasMultipleTivos]) {
            [tiVoColumn setHidden:YES];
        }
	}
	return self;
}


-(void)setNotifications
{
	DDLogDetail(@"Setting up notifications");
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reloadData) name:kMTNotificationDownloadQueueUpdated object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(tableViewSelectionDidChange:) name:kMTNotificationDownloadQueueUpdated object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateProgress:) name:kMTNotificationProgressUpdated object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reloadEpisode:) name:kMTNotificationDownloadStatusChanged object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reloadDataFormat) name:kMTNotificationFormatListUpdated object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reloadDataTiVos) name:kMTNotificationTiVoListUpdated object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reloadEpisode:) name:kMTNotificationDownloadRowChanged object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reloadEpisodeShow:) name:kMTNotificationDetailsLoaded	object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(showTiVoColumn:) name:kMTNotificationFoundMultipleTiVos object:nil];
    [self registerForDraggedTypes:[NSArray arrayWithObjects:kMTTivoShowPasteBoardType, kMTDownloadPasteBoardType, nil]];
	[self  setDraggingSourceOperationMask:NSDragOperationLink forLocal:NO];
	[self  setDraggingSourceOperationMask:NSDragOperationCopy forLocal:YES];


}


-(void)showTiVoColumn:(NSNotification *)notification
{
    NSTableColumn *tiVoColumn = [self tableColumnWithIdentifier:@"TiVo"];
	[tiVoColumn setHidden:NO];
	
}


-(void) reloadDataTiVos {
	DDLogDetail(@"Reloading DL table from TivoListUpdated");
	[self reloadData];
	
}


-(void) reloadDataFormat{
	DDLogDetail(@"Reloading DL table from FormatStatusChanged");
	[self reloadData];
	
}

-(void)reloadEpisodeShow:(NSNotification *)notification
{
	MTTiVoShow *thisShow = (MTTiVoShow *)notification.object;
	NSArray *downloads = [NSArray arrayWithArray:self.sortedDownloads];
	for (MTDownload *download in downloads) {
		if ([download.show isEqual:thisShow]) {
			NSNotification *tmpNotification = [NSNotification notificationWithName:kMTNotificationDownloadRowChanged object:download];
			[self reloadEpisode:tmpNotification];
		}
	}
}

-(void)reloadEpisode:(NSNotification *)notification
{
	MTDownload *thisDownload = notification.object;
    if (!thisDownload) {
        DDLogDetail(@"Reloading DL table from DownloadStatusChanged");
        [self reloadData];
    } else {
        NSUInteger row = [self.sortedDownloads indexOfObject:thisDownload];
        if (row != NSNotFound) {
            NSRange columns = NSMakeRange(0,self.numberOfColumns);//[self columnWithIdentifier:@"Episode"];
            [self reloadDataForRowIndexes:[NSIndexSet indexSetWithIndex:row] columnIndexes:[NSIndexSet indexSetWithIndexesInRange:columns]];
        }
    }
}

-(void) reloadData {
    //Configure Table Columns depending on how many TiVos
    
	//save selection to restore after reload
	DDLogVerbose(@"Reloading DL table");
	NSArray * selectedShows = [self.sortedDownloads objectsAtIndexes: self.selectedRowIndexes];
	[self sizeToFit];
    self.sortedDownloads =nil;
    [super reloadData];
	
	//now restore selection
	NSIndexSet * showIndexes = [self.sortedDownloads indexesOfObjectsPassingTest:^BOOL(id obj, NSUInteger idx, BOOL *stop) {
		return [selectedShows indexOfObject:obj] !=NSNotFound;
	}];
	
	[self selectRowIndexes:showIndexes byExtendingSelection:NO];
    if (tiVoManager.anyTivoActive) {
        if (!self.updateTimer) {
            self.updateTimer = [NSTimer scheduledTimerWithTimeInterval:3.0 target:self selector:@selector(updateProgress:) userInfo:nil repeats:YES];
        }
    } else {
        if (self.updateTimer) {
            [self.updateTimer invalidate];
            self.updateTimer = nil;
            [self updateProgress:nil];
        }
    }
    
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

-(void) updateProgressInCell:(MTProgressindicator *) cell forDL:(MTDownload *) download {
    if (!cell) return;
	cell.doubleValue = download.processProgress;
	cell.rightText.stringValue = download.showStatus;
    NSString * timeLeft = download.timeLeft;
    if (timeLeft != nil) {
        NSString * mySpeed = [NSString stringFromBytesPerSecond: download.speed];
        cell.toolTip = [NSString stringWithFormat:@"%@; %0.0f%%; Est time left: %@",mySpeed, download.processProgress* 100, timeLeft];
    } else {
        cell.toolTip = download.show.showTitle;
    }
    [cell setNeedsDisplay:YES];

}
-(void)updateProgress:(id) sender
{
    MTDownload * download = nil;
    if ([sender isKindOfClass: [NSNotification class]]) {
        MTDownload * possDownload = ((NSNotification *)sender).object;
        if ([possDownload isKindOfClass: [MTDownload class]]) {
            download = possDownload;
        }
    }
    NSString *progressColumn = @"Series";
    if (self.showingStageColumn) {
        progressColumn = @"DL Stage";
    } else if (self.showingProgramsColumn) {
        progressColumn = @"Programs";
    }
    NSInteger progressIndex = [self columnWithIdentifier:progressColumn];
	NSArray *displayedShows = [self.sortedDownloads copy];
	for (NSUInteger i=0; i< displayedShows.count; i++) {
		MTDownload *thisDownload = [displayedShows objectAtIndex:i];
        if (download && thisDownload != download) continue; //only update current one
		MTProgressindicator *cell = [self viewAtColumn:progressIndex row:i makeIfNecessary:NO];
		[self updateProgressInCell: cell forDL: thisDownload];
        cell.displayProgress = YES;
	}
    if (!tiVoManager.anyTivoActive) {//somewhat expensive
        [self.performanceLabel setHidden:YES];
    } else {
        double myTimeLeft = tiVoManager.aggregateTimeLeft;
        if (myTimeLeft == 0.0) {
            [self.performanceLabel setHidden:YES];  //unlikely if a TiVo is active
        } else {
            [self.performanceLabel setHidden:NO];
            NSString * timeLeft = [NSString stringFromTimeInterval:  myTimeLeft];
            NSString * mySpeed = [NSString stringFromBytesPerSecond: tiVoManager.aggregateSpeed];
            self.performanceLabel.stringValue  = [NSString stringWithFormat:@"%@; Estimated time left: %@",mySpeed, timeLeft];
        }
    }
}

-(void)dealloc
{
	[self  unregisterDraggedTypes];
	 tiVoColumnHolder=nil;
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    if (self.updateTimer) {
        [self.updateTimer invalidate];
        self.updateTimer = nil;
    }

}

#pragma mark - Table Delegate Protocol

-(void)tableViewSelectionDidChange:(NSNotification *)notification
{
	[removeFromQueueButton setEnabled:[self numberOfSelectedRows] != 0];
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


-(BOOL)showingProgramsColumn
{
    NSTableColumn *programColumn = [self tableColumnWithIdentifier:@"Programs"];
    return !programColumn.isHidden;
    
}

-(BOOL)showingStageColumn
{
    NSTableColumn *programColumn = [self tableColumnWithIdentifier:@"DL Stage"];
    return !programColumn.isHidden;
    
}

-(void) columnChanged: (NSTableColumn *) column {
    //called automagically by table when columsn are shown/hidden
    if ([column tableView] != self) return;
    NSString * identifier = [column identifier];
    if ([identifier isEqualToString:@"Programs" ] ||
        [identifier isEqualToString:@"Series" ] ||
        [identifier isEqualToString:@"DL Stage" ] ) { //need to fixup Progress bars
        [self reloadData];
    }
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
	MTDownload *download = [self.sortedDownloads objectAtIndex:row];
	MTTiVoShow * thisShow = download.show;
	BOOL protected = thisShow.protectedShow.boolValue;
//	NSDictionary *idMapping = [NSDictionary dictionaryWithObjectsAndKeys:@"Title",@"Programs",kMTSelectedTiVo,@"TiVo",kMTSelectedFormat,@"Format", nil];
	
    // get an existing cell with the MyView identifier if it exists
	
    NSTableCellView *result = [tableView makeViewWithIdentifier:tableColumn.identifier owner:self];
    
    // There is no existing cell to reuse so we will create
    // result is now guaranteed to be valid, either as a re-used cell
    // or as a new cell, so set the stringValue of the cell to the
    // nameArray value at row
	NSString *textVal = nil;
	result.toolTip = nil;
    BOOL programColumn = [tableColumn.identifier isEqualToString:@"Programs"];
    BOOL seriesColumn = [tableColumn.identifier isEqualToString:@"Series"];
    BOOL stageColumn = [tableColumn.identifier isEqualToString:@"DL Stage"];

	if (programColumn || seriesColumn || stageColumn) {
        //Progress status should show in first visible of DL Stage, then Programs, then Series
 		NSString * cellVal;
		if (programColumn) {
			cellVal = thisShow.showTitle ;
		 } else if (seriesColumn){
			 cellVal = thisShow.seriesTitle ;
         } else {
              cellVal = @"" ;
         }
		MTProgressindicator *cell = (MTProgressindicator *) result;
		cell.leftText.stringValue = cellVal;
		cell.toolTip = cellVal;
		if (stageColumn ||
            (!self.showingStageColumn &&
                (programColumn ||
                 (!self.showingProgramsColumn && seriesColumn )
            ))) {
            cell.displayProgress = YES;
            [self updateProgressInCell:cell forDL:download];
        } else {
            cell.displayProgress = NO;
            cell.rightText.stringValue = @"";
        }
		if ([thisShow.protectedShow boolValue]) {
			cell.foregroundTextColor = [NSColor grayColor];
		} else {
			cell.foregroundTextColor = [NSColor blackColor];
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
           popUpButton.target = myController;
           popUpButton.action = @selector(selectFormat:);
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
        checkBox.target = myController;
        checkBox.action = @selector(changeiTunes:);
         checkBox.owner = download;

	} else if ([tableColumn.identifier isEqualToString:@"icon"]) {
        NSString * imageName = download.imageString;
           DDLogVerbose(@"Icon: %@ for %@",imageName, download.show.showTitle);
        //  result.imageView.autoresizingMask = NSViewMinXMargin | NSViewMaxXMargin;
		result.imageView.image = [NSImage imageNamed: imageName];
		result.toolTip = [[imageName stringByReplacingOccurrencesOfString:@"-" withString:@" "] capitalizedString];
//	} else if ([tableColumn.identifier isEqualToString:@"Simu"]) {
//        MTCheckBox * checkBox = ((MTDownloadCheckTableCell *)result).checkBox;
//        [checkBox setOn: download.simultaneousEncode];
//        checkBox.owner = download;
//        [checkBox setEnabled: download.isNew && !protected && download.encodeFormat.canSimulEncode];
//        
 	} else if ([tableColumn.identifier isEqualToString:@"Skip"]) {
        MTCheckBox * checkBox = ((MTDownloadCheckTableCell *)result).checkBox;
        [checkBox setOn: download.skipCommercials];
        checkBox.owner = download;
        checkBox.target = myController;
        checkBox.action = @selector(changeSkip:);
        [checkBox setEnabled: download.isNew && !protected && download.encodeFormat.canSkip];
        
 	} else if ([tableColumn.identifier isEqualToString:@"Mark"]) {
        MTCheckBox * checkBox = ((MTDownloadCheckTableCell *)result).checkBox;
        [checkBox setOn: download.markCommercials];
        checkBox.owner = download;
        checkBox.target = myController;
        checkBox.action = @selector(changeMark:);
        [checkBox setEnabled: download.isNew && !protected && download.encodeFormat.canMarkCommercials];
        
#ifndef deleteXML
 	} else if ([tableColumn.identifier isEqualToString:@"XML"]) {
        MTCheckBox * checkBox = ((MTDownloadCheckTableCell *)result).checkBox;
        [checkBox setOn: download.genXMLMetaData.boolValue];
        checkBox.owner = download;
        checkBox.target = myController;
        checkBox.action = @selector(changeXML:);
		checkBox.enabled = !download.isDone && !protected;
#endif
	} else if ([tableColumn.identifier isEqualToString:@"pyTiVo"]) {
        MTCheckBox * checkBox = ((MTDownloadCheckTableCell *)result).checkBox;
        [checkBox setOn: download.genTextMetaData.boolValue];
        checkBox.target = myController;
        checkBox.action = @selector(changepyTiVo:);
        checkBox.owner = download;
		checkBox.enabled = !download.isDone && !protected;
	} else if ([tableColumn.identifier isEqualToString:@"Subtitles"]) {
        MTCheckBox * checkBox = ((MTDownloadCheckTableCell *)result).checkBox;
        [checkBox setOn: download.exportSubtitles.boolValue];
        checkBox.target = myController;
        checkBox.action = @selector(changeSubtitle:);
        checkBox.owner = download;
		checkBox.enabled = download.isNew && !protected;
#ifndef deleteXML
	} else if ([tableColumn.identifier isEqualToString:@"Metadata"]) {
        MTCheckBox * checkBox = ((MTDownloadCheckTableCell *)result).checkBox;
        [checkBox setOn: download.includeAPMMetaData.boolValue && download.encodeFormat.canAcceptMetaData];
        checkBox.target = myController;
        checkBox.action = @selector(changeMetadata:);
        checkBox.owner = download;
		checkBox.enabled = download.encodeFormat.canAcceptMetaData && !download.isDone && !protected;
#endif
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
    } else if ([tableColumn.identifier isEqualToString:@"DL Stage"]) {
        textVal = download.showStatus;
	} else if ([tableColumn.identifier isEqualToString:@"Queued"]) {
		textVal = thisShow.isQueuedString;
		result.toolTip =@"Is program in queue to download?";
    } else if ([tableColumn.identifier isEqualToString:@"OnDisk"]) {
        textVal = thisShow.isOnDiskString;
        result.toolTip =@"Is program already downloaded and still on disk?";
	} else if ([tableColumn.identifier isEqualToString:@"HD"]) {
		textVal = thisShow.isHDString;
		result.textField.alignment = NSCenterTextAlignment;
		result.toolTip =@"Is program recorded in HD?";
    } else if ([tableColumn.identifier compare:@"H.264"] == NSOrderedSame) {
        textVal = thisShow.h264String;
        result.textField.alignment = NSCenterTextAlignment;
        result.toolTip =@"Does this channel use H.264 compression?";
	} else if ([tableColumn.identifier isEqualToString:@"Channel"]) {
		textVal = thisShow.channelString;
	} else if ([tableColumn.identifier isEqualToString:@"Size"]) {
		textVal = thisShow.sizeString;
	} else if ([tableColumn.identifier isEqualToString:@"TiVoID"]) {
		textVal = thisShow.idString;
	} else if ([tableColumn.identifier isEqualToString:@"EpisodeID"]) {
		textVal = thisShow.episodeID;
	} else if ([tableColumn.identifier isEqualToString:@"Title"]) {
		textVal = thisShow.episodeTitle;
	} else if ([tableColumn.identifier isEqualToString:@"Station"]) {
		textVal = thisShow.stationCallsign;
	} else if ([tableColumn.identifier isEqualToString:@"Genre"]) {
		textVal = thisShow.episodeGenre;
	} else if ([tableColumn.identifier isEqualToString:@"FirstAirDate"]) {
		textVal = thisShow.originalAirDateNoTime;
    } else if ([tableColumn.identifier compare:@"AgeRating"] == NSOrderedSame) {
        textVal = thisShow.ageRatingString;
        result.toolTip = textVal;
    } else if ([tableColumn.identifier compare:@"StarRating"] == NSOrderedSame) {
        textVal = thisShow.starRatingString;
	} else {
		DDLogReport(@"Unknown Column: %@ ",tableColumn.identifier);
	}
	result.textField.stringValue = textVal ?: @"";
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
            if ([selectedColumn.identifier isEqualToString:@"Programs"]) { //Check if over text
                MTProgressindicator *showCellView = [tv viewAtColumn:c row:r makeIfNecessary:NO];
                if (![showCellView isKindOfClass:[MTProgressindicator class]]) return NO;
                NSTextField *showField = showCellView.leftText;
                if (!showField) return NO;
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

	}
    // Drag and drop support
	[self selectRowIndexes:rowIndexes byExtendingSelection:NO ];
 	NSArray	*selectedObjects = [self.sortedDownloads objectsAtIndexes:rowIndexes ];
	[pboard clearContents];
	[pboard writeObjects:selectedObjects];
	DDLogVerbose (@"DraggingObjects: %@",selectedObjects);
//	NSLog(@"property Types available: %@",[pboard types]);
//	NSLog(@"Property list: URLS: %@", [pboard
//	 readObjectsForClasses:[NSArray arrayWithObject:[NSURL class]]
//	 options:[NSDictionary dictionaryWithObject:[NSNumber
//												 numberWithBool:YES]
//										 forKey:NSPasteboardURLReadingFileURLsOnlyKey]]);
	return YES;
}

// post 10.7,but redundant with above
- (void)tableView:(NSTableView *)tableView draggingSession:(NSDraggingSession *)session endedAtPoint:(NSPoint)screenPoint operation:(NSDragOperation)operation {
	//post 10.7
	if (operation == NSDragOperationDelete) {
		[myController removeFromDownloadQueue:nil];
	}
}


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
		if ([show videoFileURLWithEncrypted:NO]) {
			return  YES;
		}
	}
	return NO;
	
}

- (IBAction)clearHistory:(id)sender {
	NSString *message = @"Are you sure you want to delete history of completed downloads?";
	NSAlert *insertDownloadAlert = [NSAlert alertWithMessageText:message defaultButton:@"Delete" alternateButton:@"Cancel" otherButton:nil informativeTextWithFormat:@""];
	NSInteger returnValue = [insertDownloadAlert runModal];
	if (returnValue == 1) {
		DDLogDetail(@"User did clear history");
		[tiVoManager clearDownloadHistory];
	}
}

-(BOOL)playVideo
{
	NSIndexSet *selectedRowIndexes = [self selectedRowIndexes];
	NSArray *selectedDownloads = [self.sortedDownloads objectsAtIndexes:selectedRowIndexes];
    for (MTDownload *download in selectedDownloads) {
		if (download.isDone) {
			if ([download playVideo])  {
				return YES;		}
		}
	}
    return NO;
//	return [tiVoManager playVideoForDownloads:selectedDownloads];
}

-(BOOL)revealInFinder
{
	NSIndexSet *selectedRowIndexes = [self selectedRowIndexes];
	NSArray *selectedDownloads = [self.sortedDownloads objectsAtIndexes:selectedRowIndexes];
	NSMutableArray * showURLs = [NSMutableArray arrayWithCapacity:selectedDownloads.count];
	for (MTDownload *show in selectedDownloads) {
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
//	return [tiVoManager revealInFinderForDownloads:selectedDownloads];

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

-(BOOL) insertShowsFromPasteboard:(NSPasteboard*) pboard atRow: (NSUInteger) row {
    MTDownload * insertTarget = nil;
    NSUInteger insertRow = [tiVoManager downloadQueue].count;

    if (row < _sortedDownloads.count) {
        insertTarget = _sortedDownloads[row];
        insertRow = [[tiVoManager downloadQueue] indexOfObject:insertTarget];
    }
    
    NSArray	*classes = @[[MTTiVoShow class]];
    NSDictionary *options = [NSDictionary dictionary];
    NSArray	*draggedShows = [pboard readObjectsForClasses:classes options:options];
    DDLogDetail(@"Accepting drop: %@", draggedShows);

    //dragged shows are proxies, so we need to find the real show objects
    NSMutableArray * realShows = [NSMutableArray arrayWithCapacity:draggedShows.count ];

    for (MTTiVoShow * show in draggedShows) {
         MTTiVoShow * realShow= [tiVoManager findRealShow:show];
        if (realShow && !realShow.protectedShow.boolValue) {
            [realShows addObject:realShow];
        }
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
    return YES;
}

-(BOOL) insertDownloadsFromPasteboard:(NSPasteboard*) pboard atRow: (NSUInteger) row {
    MTDownload * insertTarget = nil;
    NSUInteger insertRow = [tiVoManager downloadQueue].count;

    if (row < _sortedDownloads.count) {
        insertTarget = _sortedDownloads[row];
        insertRow = [[tiVoManager downloadQueue] indexOfObject:insertTarget];
    }
    NSArray	*classes = @[[MTDownload class]];
    NSDictionary *options = [NSDictionary dictionary];
    NSArray	*draggedDLs = [pboard readObjectsForClasses:classes options:options];
    DDLogDetail(@"Accepting drop: %@", draggedDLs);

    //dragged downloads are proxies, so we need to find the real download objects
    NSMutableArray * realDLs = [NSMutableArray arrayWithCapacity:draggedDLs.count ];
    NSMutableArray * completedDownloadsBeingMoved =[NSMutableArray array];
    for (MTDownload * download in draggedDLs) {
        MTDownload * realDownload= [tiVoManager findRealDownload:download];
        if (realDownload) [realDLs addObject:realDownload];
        if (realDownload.isDone) [completedDownloadsBeingMoved addObject:realDownload];
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
                            if (![self askReschedule:activeDL]) {
                                return NO;
                            };
                            break;  // no need to ask again
                        }
                    }
                }
            }
        } else {
            //I'm not being moved
            if ((insertRow <= activeRow) &&   //shows being moved above me
                ([self downloads:realDLs  contain:activeDL.show.tiVo]))  {//and one of them is on same TiVo as me
                if (![self askReschedule: activeDL] ) {
                    return NO;
                };
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
        } else {
            return NO;
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
    return YES;

}

- (BOOL)tableView:(NSTableView *)aTableView acceptDrop:(id )info row:(NSInteger)row dropOperation:(NSTableViewDropOperation)operation
{
	NSUInteger realRow = (row < 0) ? 0: row ;
	//although displayed in sorted order, need to work in actual download order
	if ([info draggingSource] == myController.tiVoShowTable) {
        if ( [self insertShowsFromPasteboard:[info draggingPasteboard] atRow:realRow ]) {
            [self reloadData];
            return YES;
        }
	} else if( [info draggingSource] == aTableView ) {
        if ([self insertDownloadsFromPasteboard:[info draggingPasteboard] atRow:realRow]) {
            [self reloadData];
            return YES;
        }

	}
    return NO;
}

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem{
    if ([menuItem action]==@selector(copy:) ||
        [menuItem action]==@selector(cut:)  ||
        [menuItem action]==@selector(delete:)) {
        return (self.numberOfSelectedRows >0);
    } else  if ([menuItem action]==@selector(paste:)) {
        NSPasteboard * pboard = [NSPasteboard generalPasteboard];
        return  ([pboard.types containsObject:kMTTivoShowPasteBoardType] ||
                 [pboard.types containsObject:kMTDownloadPasteBoardType]);
    }
    return YES;
}

-(IBAction)copy: (id) sender {
    NSIndexSet *selectedRowIndexes = [self selectedRowIndexes];
    NSArray *selectedShows = [self.sortedDownloads objectsAtIndexes:selectedRowIndexes];
    if (selectedShows.count > 0) {
        MTDownload * firstDownload = selectedShows[0];

        NSPasteboard * pboard = [NSPasteboard generalPasteboard];
        [pboard declareTypes:[firstDownload writableTypesForPasteboard:pboard] owner:nil];
        [pboard writeObjects:selectedShows];
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
    }
}

-(IBAction) delete:(id)sender {
    DDLogDetail(@"user request to delete shows");
    [myController removeFromDownloadQueue:sender];
}



@end
