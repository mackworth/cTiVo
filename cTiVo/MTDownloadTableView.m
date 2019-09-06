//
//  MTDownloadList.m
//  myTivo
//
//  Created by Scott Buchanan on 12/8/12.
//  Copyright (c) 2012 Scott Buchanan. All rights reserved.
//

#import "MTDownloadTableView.h"
#import "MTFormatPopUpTableCellView.h"
#import "NSString+Helpers.h"
#import "MTWeakTimer.h"
#import "MTSubscriptionList.h"
#import "MTShowFolder.h"

@interface MTDownloadTableView ()
@property (nonatomic, weak) IBOutlet NSTextField *performanceLabel;
@property (nonatomic, readonly) BOOL showingProgramsColumn;
@property (nonatomic, strong) NSTimer *updateTimer;
@property (nonatomic, strong) NSArray <MTDownload *> * lastCopy;

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
		if (@available(macOS 10.15, *)) {
            NSTableColumn * iTunesColumn = [self tableColumnWithIdentifier:@"iTunes"];
            iTunesColumn.title = [iTunesColumn.title stringByReplacingOccurrencesOfString:@"iTunes" withString:@"TV"];
            iTunesColumn.headerToolTip = [iTunesColumn.headerToolTip stringByReplacingOccurrencesOfString:@"iTunes" withString:@"Apple's TV app"];
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
    [self registerForDraggedTypes:[NSArray arrayWithObjects:kMTTivoShowPasteBoardType, kMTTiVoShowArrayPasteBoardType, kMTDownloadPasteBoardType, nil]];
	[self  setDraggingSourceOperationMask:NSDragOperationLink forLocal:NO];
	[self  setDraggingSourceOperationMask:NSDragOperationCopy forLocal:YES];
}

-(void)showTiVoColumn:(NSNotification *)notification {
    [self tableColumnWithIdentifier:@"TiVo"].hidden = NO;
}

-(void) reloadDataTiVos {
	DDLogDetail(@"Reloading DL table from TivoListUpdated");
	[self reloadData];
}

-(void) reloadDataFormat{
	DDLogDetail(@"Reloading DL table from FormatStatusChanged");
	[self reloadData];
}

-(void) reallyReloadDownload:(MTDownload *) download {
	NSUInteger row = [self.sortedDownloads indexOfObject:download];
	if (row != NSNotFound) {
		NSRange columns = NSMakeRange(0,self.numberOfColumns);//[self columnWithIdentifier:@"Episode"];
		[self reloadDataForRowIndexes:[NSIndexSet indexSetWithIndex:row] columnIndexes:[NSIndexSet indexSetWithIndexesInRange:columns]];
	}
}

-(void)reloadEpisodeShow:(NSNotification *)notification
{
	MTTiVoShow *thisShow = (MTTiVoShow *)notification.object;
	NSArray *downloads = [NSArray arrayWithArray:self.sortedDownloads];
	for (MTDownload *download in downloads) {
		if ([download.show isEqual:thisShow]) {
			[self reallyReloadDownload:download];
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
		[self reallyReloadDownload:thisDownload];
    }
}

-(void) reloadData {
    //Configure Table Columns depending on how many TiVos
    
	//save selection to restore after reload
	DDLogDetail(@"Reloading DL table");
	NSArray * selectedShows = @[];
	if (self.selectedRowIndexes.lastIndex < self.sortedDownloads.count) {
		selectedShows = [self.sortedDownloads objectsAtIndexes: self.selectedRowIndexes];
	}
    CGRect frame = self.enclosingScrollView.documentVisibleRect;
	[self sizeToFit];
    self.sortedDownloads =nil;
    [super reloadData];
	
	//now restore selection
	if (selectedShows.count > 0) {
		NSIndexSet * showIndexes = [self.sortedDownloads indexesOfObjectsPassingTest:^BOOL(id obj, NSUInteger idx, BOOL *stop) {
			return [selectedShows indexOfObjectIdenticalTo:obj] !=NSNotFound;
		}];
	
		[self selectRowIndexes:showIndexes byExtendingSelection:NO];
	}
	[self scrollRectToVisible:frame];

    if (tiVoManager.anyTivoActive) {
        if (!self.updateTimer) {
            self.updateTimer = [MTWeakTimer scheduledTimerWithTimeInterval:3.0 target:self selector:@selector(updateProgress:) userInfo:nil repeats:YES];
        }
    } else {
        if (self.updateTimer) {
            [self.updateTimer invalidate];
            self.updateTimer = nil;
            [self updateProgress:nil];
        }
    }
    
}

-(NSArray <MTDownload *> *) sortedDownloads
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
	cell.leftText.toolTip = nil;
	cell.rightText.toolTip = nil;
	NSString * timeLeft = download.timeLeft;  //00:00:00
    if (timeLeft.length > 3) {
		if (download.downloadStatus.intValue == kMTStatusWaiting){
			cell.toolTip = [NSString stringWithFormat:@"%@ seconds till launch", [timeLeft substringFromIndex: timeLeft.length - 2]];
		} else {
			NSString * mySpeed = [NSString stringFromBytesPerSecond: download.speed];
			cell.toolTip = [NSString stringWithFormat:@"%@; %0.0f%%; Est time left: %@",mySpeed, download.processProgress* 100, timeLeft];
		}
    } else {
        cell.toolTip = download.show.showTitle;
    }
    [cell setNeedsDisplay:YES];

}
-(void)updateProgress:(id) sender {
    if ([sender isKindOfClass: [NSNotification class]]) {
        MTDownload * download = ((NSNotification *)sender).object;
        if ([download isKindOfClass: [MTDownload class]]) {
			NSString *progressColumn = @"Series";
			if (self.showingStageColumn) {
				progressColumn = @"DL Stage";
			} else if (self.showingProgramsColumn) {
				progressColumn = @"Programs";
			}
			NSInteger progressIndex = [self columnWithIdentifier:progressColumn];
			NSUInteger row = [self.sortedDownloads indexOfObjectIdenticalTo:download];
			if (row != NSNotFound && ((NSInteger)row < self.numberOfRows)) {
				MTProgressindicator *cell = [self viewAtColumn:progressIndex row:row makeIfNecessary:NO];
				[self updateProgressInCell: cell forDL: download];
				cell.displayProgress = YES;
				
			}
        }
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
	NSUInteger index = [selectedRowIndexes firstIndex];
    if (selectedRowIndexes.count == 1 && index < self.sortedDownloads.count) {
		MTTiVoShow * show = self.sortedDownloads[index].show;
		if (!show.protectedShow.boolValue && self == self.window.firstResponder ) {
			[myController setValue:show forKey:@"showForDetail"];
		}
    }
}

- (NSArray<NSTableViewRowAction *> *)tableView:(NSTableView *)tableView
                              rowActionsForRow:(NSInteger)row
										  edge:(NSTableRowActionEdge)edge  API_AVAILABLE(macos(10.11)){
										  
	return @[ [NSTableViewRowAction rowActionWithStyle:NSTableViewRowActionStyleDestructive
		  title:@"Delete"
		handler:^(NSTableViewRowAction * _Nonnull action, NSInteger deleteRow) {
			if ((NSUInteger) deleteRow >= self.sortedDownloads.count) return;
			[self deleteDownloads:@[self.sortedDownloads[deleteRow]]];
		}]
	];
}

#pragma mark - Table Data Source Protocol

- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView {
    return self.sortedDownloads.count;
}

-(BOOL)showingProgramsColumn {
    NSTableColumn *programColumn = [self tableColumnWithIdentifier:@"Programs"];
    return !programColumn.isHidden;
}

-(BOOL)showingStageColumn {
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
	if ((NSUInteger) row >= self.sortedDownloads.count) return nil;
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
	result.imageView.image = nil;
	
    BOOL programColumn = [tableColumn.identifier isEqualToString:@"Programs"];
    BOOL seriesColumn = [tableColumn.identifier isEqualToString:@"Series"];
    BOOL stageColumn = [tableColumn.identifier isEqualToString:@"DL Stage"];

	MTCheckBox * checkBox = nil;
	if ([result isKindOfClass:[MTDownloadCheckTableCell class]]) {
		checkBox = ((MTDownloadCheckTableCell *)result).checkBox;
		checkBox.target = myController;
		checkBox.owner = download;
		checkBox.alignment = NSCenterTextAlignment;
	}
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
            [self updateProgressInCell:cell forDL:download];
			cell.displayProgress = YES;
        } else {
            cell.displayProgress = NO;
            cell.rightText.stringValue = @"";
        }
		if ([thisShow.protectedShow boolValue]) {
			cell.foregroundTextColor = [NSColor disabledControlTextColor ];
		} else {
			cell.foregroundTextColor = [NSColor controlTextColor];
		}
   } else if ([tableColumn.identifier isEqualToString:@"TiVo"]) {
        textVal = thisShow.tiVoName ;
        result.textField.textColor = [NSColor controlTextColor];
        if (!thisShow.tiVo.isReachable && download.isDownloading) {
			if (@available(macOS 10.10,*)) {
            	result.textField.textColor = [NSColor systemRedColor];
			} else {
				result.textField.textColor = [NSColor redColor];
			}
        }
        
    } else if ([tableColumn.identifier isEqualToString:@"Order"]) {
        textVal = [NSString stringWithFormat:@"%@",download.downloadIndex] ;
        
    } else if ([tableColumn.identifier isEqualToString:@"Format"]) {
		MTFormatPopUpTableCellView * cell = (MTFormatPopUpTableCellView *)result;
		MTFormatPopUpButton *popUpButton = cell.popUpButton;
		popUpButton.owner = download;
       if (download.isNew) {
		    popUpButton.owner = download;
			//ensure this format is still "available"
            popUpButton.formatList = tiVoManager.formatList;
			download.encodeFormat = [ popUpButton selectFormat:download.encodeFormat];
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
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wundeclared-selector"
    } else if ([tableColumn.identifier isEqualToString:@"iTunes"]) {
        [checkBox setOn: download.addToiTunesWhenEncoded];
        [checkBox setEnabled: !download.isCompletelyDone && !protected &&
                              download.encodeFormat.canAddToiTunes ];
        checkBox.action = @selector(changeiTunes:);
	} else if ([tableColumn.identifier isEqualToString:@"icon"]) {
        NSString * imageName = download.imageString;
           DDLogVerbose(@"Icon: %@ for %@",imageName, download.show.showTitle);
        //  result.imageView.autoresizingMask = NSViewMinXMargin | NSViewMaxXMargin;
		result.imageView.image = [NSImage imageNamed: imageName];
		result.toolTip = [[imageName stringByReplacingOccurrencesOfString:@"-" withString:@" "] capitalizedString];
	} else if ([tableColumn.identifier isEqualToString:@"SkipMode"]) {
		switch (download.show.rpcSkipMode.intValue) {
			case 5: result.imageView.image = [NSImage imageNamed:@"skipModeComskip"];
				result.toolTip = @"cSkip: Commercial information loaded from Comskip ";
				break;
			case 4:  result.imageView.image = [NSImage imageNamed:@"skipModeQuestion"];
				result.toolTip = @"SkipMode data may still be coming";
				break;
			case 3:  result.imageView.image = [NSImage imageNamed:@"skipMode"];
				result.toolTip = @"SkipMode data retrieved.";
				break;
			case 2:  result.imageView.image = [NSImage imageNamed:@"skipModeSlash"];
				result.toolTip = @"SkipMode retrieval failed";
				break;
			case 1:  result.imageView.image = [NSImage imageNamed:@"skipModeInverted"];
				result.toolTip = @"SkipMode available, but not retrieved yet.";
				break;
			default: result.imageView.image = nil;
				break;
		}
		CGFloat width = tableColumn.width;
		CGFloat height = MIN(width, MIN(self.rowHeight, 24));
		CGFloat leftMargin = (width -height)/2;
		CGFloat topMargin = (self.rowHeight-height)/2;
		result.imageView.frame = CGRectMake(leftMargin, topMargin, height, height);
		return result;
	} else if ([tableColumn.identifier isEqualToString:@"Skip"]) {
        [checkBox setOn: download.skipCommercials];
        checkBox.action = @selector(changeSkip:);
        [checkBox setEnabled: download.isNew && !protected && download.encodeFormat.canSkip];
	} else if ([tableColumn.identifier isEqualToString:@"UseTS"]) {
		[checkBox setOn: download.useTransportStream.boolValue];
		checkBox.action = @selector(changeUseTS:);
		[checkBox setEnabled: download.isNew && !protected && download.show.tiVo.supportsTransportStream];
 	} else if ([tableColumn.identifier isEqualToString:@"Mark"]) {
        [checkBox setOn: download.markCommercials];
        checkBox.action = @selector(changeMark:);
		int status = download.downloadStatus.intValue;
		[checkBox setEnabled: (download.isNew || status == kMTStatusSkipModeWaitEnd || status == kMTStatusAwaitingPostCommercial ||
							   (download.isInProgress && download.useSkipMode) ) &&
		 						!protected && download.encodeFormat.canMarkCommercials];
	} else if ([tableColumn.identifier isEqualToString:@"UseSkipMode"]) {
		[checkBox setOn: download.useSkipMode];
		checkBox.action = @selector(changeUseSkipMode:);
		int status = download.downloadStatus.intValue;
		[checkBox setEnabled:
		 	(download.isNew ||
			 status == kMTStatusSkipModeWaitEnd ||
			 (download.isInProgress && download.markCommercials)) &&
			(download.show.mightHaveSkipModeInfo || download.useSkipMode) &&
		 	!protected &&
		 	(download.encodeFormat.canMarkCommercials || download.encodeFormat.canSkip)];
		
	} else if ([tableColumn.identifier isEqualToString:@"pyTiVo"]) {
        [checkBox setOn: download.genTextMetaData.boolValue];
        checkBox.action = @selector(changepyTiVo:);
		checkBox.enabled = !download.isDone && !protected;
	} else if ([tableColumn.identifier isEqualToString:@"Subtitles"]) {
        [checkBox setOn: download.exportSubtitles.boolValue];
        checkBox.action = @selector(changeSubtitle:);
		checkBox.enabled = download.isNew && !protected;
	} else if ([tableColumn.identifier isEqualToString:@"Delete"]) {
		[checkBox setOn: download.deleteAfterDownload.boolValue];
		checkBox.action = @selector(changeDelete:);
		checkBox.enabled = !download.isCompletelyDone && !protected ;
#pragma clang diagnostic pop
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
        result.toolTip =@"Does this show (✔) or channel (√) use H.264 compression v. MPEG2 ( -- or -)?";
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
        result.textField.textColor = [NSColor disabledControlTextColor];
    } else {
        result.textField.textColor = [NSColor controlTextColor];
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

- (BOOL)canDragRowsWithIndexes:(NSIndexSet *)rowIndexes
                       atPoint:(NSPoint)mouseDownPoint {
   	if (![[NSUserDefaults standardUserDefaults]boolForKey:kMTDisableDragSelect] ) {
        //if user wants drag-to-select, then check if we're selecting new rows or not
        //drag/drop if current row is  already selected OR we're over name of show
        //this is parallel to Finder behavior.
		NSInteger r = [self rowAtPoint:mouseDownPoint];
		NSInteger c = [self columnAtPoint:mouseDownPoint];
		if (c >= 0 && r >=0 && ![self isRowSelected:r]) {
            NSTableColumn *selectedColumn = self.tableColumns[c];
            if ([selectedColumn.identifier isEqualToString:@"Programs"]) { //Check if over text
                MTProgressindicator *showCellView = [self viewAtColumn:c row:r makeIfNecessary:NO];
                if (![showCellView isKindOfClass:[MTProgressindicator class]]) return NO;
                NSTextField *showField = showCellView.leftText;
                if (!showField) return NO;
                NSPoint clickInText = [showField convertPoint:mouseDownPoint fromView:self];
                NSSize stringSize = [showField.stringValue sizeWithAttributes:@{NSFontAttributeName : showField.font}];
                if (clickInText.x > stringSize.width || clickInText.x > showField.bounds.size.width) {
                    return NO;
                }
            }
        }
	}
	return YES;
}

- (id<NSPasteboardWriting>)tableView:(NSTableView *)tableView pasteboardWriterForRow:(NSInteger)row {
	if ((NSUInteger) row > self.sortedDownloads.count) return nil;
	return self.sortedDownloads[row];
}

- (void)tableView:(NSTableView *)tableView draggingSession:(NSDraggingSession *)session endedAtPoint:(NSPoint)screenPoint operation:(NSDragOperation)operation {
	//drag to trash?
	NSMutableArray <MTDownload *> * downloads = [NSMutableArray array];
	if (operation == NSDragOperationDelete) {
		[session enumerateDraggingItemsWithOptions: NSDraggingItemEnumerationConcurrent
		forView:tableView classes:@[[MTDownload class]]
		searchOptions:@{}
		 usingBlock:^(NSDraggingItem * _Nonnull draggingItem, NSInteger idx, BOOL * _Nonnull stop) {
			MTDownload * pasteboardDownload = (MTDownload *) draggingItem.item;
			[downloads addObject: [tiVoManager findRealDownload:pasteboardDownload]];
		}];
		[self deleteDownloads:downloads];
	}
}
//implement to show images
// also add to MTTiVoShow encoding
// 	[encoder encodeObject:self.thumbnailImage forKey: kMTQueueImage];
//and to decoding
//		self.thumbnailImage =	   [decoder decodeObjectOfClass:[NSImage class] forKey: kMTQueueImage] ;  //to show while dragging
//
//- (void)tableView:(NSTableView *)tableView updateDraggingItemsForDrag:(id <NSDraggingInfo>)draggingInfo {
//   [draggingInfo enumerateDraggingItemsWithOptions:NSDraggingItemEnumerationConcurrent
//                                      forView:tableView
//                                      classes:@[[MTDownload class],[MTTiVoShow class]]
//                                searchOptions:@{}
//                                   usingBlock:^(NSDraggingItem *draggingItem, NSInteger index, BOOL *stop) {
//		MTTiVoShow * show = nil;
//		id obj = draggingItem.item;
//		if ([obj isKindOfClass:[MTTiVoShow class]] ) {
//			show = (MTTiVoShow*) obj;
//		} else if ([obj isKindOfClass:[MTDownload class]] ) {
// 			show = ((MTDownload *) obj).show;
//		}
//		NSImage * image = show.thumbnailImage;
//		NSDraggingImageComponent * component = nil;
//		if (image) {
//		draggingInfo.draggingFormation = NSDraggingFormationPile;
//			component = [NSDraggingImageComponent draggingImageComponentWithKey:NSDraggingImageComponentIconKey];
//			component.contents = image;
//			CGFloat ratio = image.size.height/image.size.width;
//			component.frame = NSMakeRect(0, 0, 100, 100*ratio);
//		} else {
//			component = [NSDraggingImageComponent draggingImageComponentWithKey:NSDraggingImageComponentLabelKey];
//			component.contents = show.showTitle;
//			component.frame = NSMakeRect(0, 0, 100, 50);
//		}
//      	draggingItem.imageComponentsProvider = ^NSArray*(void) {
//        	return @[component];
//	   };
//    }];
//
//}

//Drag and drop destination

- (NSDragOperation)tableView:(NSTableView *)aTableView validateDrop:(id < NSDraggingInfo >)info proposedRow:(NSInteger)row proposedDropOperation:(NSTableViewDropOperation)operation {
	if ([info draggingSource] == self) {
		DDLogDetail(@"User dragged to Row: %@%@", @(row+1), operation == NSTableViewDropOn ? @"" : @"+");
		if (@available(macOS 10.14,*)) {
			//bug in Mojave
			self.draggingDestinationFeedbackStyle = NSTableViewDraggingDestinationFeedbackStyleRegular;
		} else {
			self.draggingDestinationFeedbackStyle = NSTableViewDraggingDestinationFeedbackStyleGap;
		}
		if (operation != NSTableViewDropAbove ) {
			[self setDropRow:row dropOperation:NSTableViewDropAbove];
		}
		return NSDragOperationMove;

	} else if ([info draggingSource] == myController.tiVoShowTable) {
		DDLogDetail(@"User dragged from TivoShow Table");
		[self setDropRow: row dropOperation:NSTableViewDropAbove];
		self.draggingDestinationFeedbackStyle = NSTableViewDraggingDestinationFeedbackStyleGap;
		return NSDragOperationCopy;
	} else {
		self.draggingDestinationFeedbackStyle = NSTableViewDraggingDestinationFeedbackStyleNone;
		return NSDragOperationNone;
	}
}

- (BOOL)tableView:(NSTableView *)aTableView acceptDrop:(id )info row:(NSInteger)row dropOperation:(NSTableViewDropOperation)operation {
	NSUInteger realRow = (row < 0) ? 0: row ;
	//although displayed in sorted order, need to work in actual download order
	if ([info draggingSource] == myController.tiVoShowTable) {
        if ( [self insertShowsFromPasteboard:[info draggingPasteboard] atRow:realRow ]) {
            return YES;
        }
	} else if( [info draggingSource] == aTableView ) {
        if ([self insertDownloadsFromPasteboard:[info draggingPasteboard] atRow:realRow]) {
            return YES;
        }
	}
    return NO;
}

-(BOOL)downloads:(NSArray *)downloads contain:(MTTiVo *)tiVo {
	for (MTDownload * download in downloads) {
		if (download.show.tiVo  == tiVo) {
			return  YES;
		}
	}
	return NO;
}

-(NSArray <MTDownload *> *) actionItems {
	NSIndexSet *selectedRowIndexes = [self selectedRowIndexes];
	if (self.clickedRow < 0 || (NSUInteger) self.clickedRow >= self.sortedDownloads.count || [selectedRowIndexes containsIndex:self.clickedRow]) {
		return [self.sortedDownloads objectsAtIndexes:selectedRowIndexes];
	} else {
		return @[self.sortedDownloads[self.clickedRow]];
	}
}

-(BOOL)selectionContainsCompletedShows {
	for (MTDownload *show in self.actionItems) {
		if ([show videoFileURLWithEncrypted:NO]) {
			return  YES;
		}
	}
	return NO;
}

#pragma mark - user commands

- (IBAction)clearHistory:(id)sender {
	NSString *message = @"Are you sure you want to delete history of completed downloads?";
	NSAlert *insertDownloadAlert = [NSAlert alertWithMessageText:message defaultButton:@"Delete" alternateButton:@"Cancel" otherButton:nil informativeTextWithFormat:@" "];
	NSInteger returnValue = [insertDownloadAlert runModal];
	if (returnValue == 1) {
		DDLogDetail(@"User did clear history");
		[tiVoManager clearDownloadHistory];
	}
}

-(IBAction)reschedule:(id) sender {
	[tiVoManager rescheduleDownloads:self.actionItems];
}

-(IBAction)subscribe:(id)sender {
	[tiVoManager.subscribedShows addSubscriptionsDL:self.actionItems];
}

-(BOOL) confirmCancel:(NSString *) title {
	NSAlert *myAlert = [NSAlert alertWithMessageText:[NSString stringWithFormat:@"Do you want to cancel active download of '%@'?",title] defaultButton:@"No" alternateButton:@"Yes" otherButton:nil informativeTextWithFormat:@" "];
	myAlert.alertStyle = NSCriticalAlertStyle;
	NSInteger result = [myAlert runModal];
	return (result == NSAlertAlternateReturn);
	
}

-(IBAction)removeFromDownloadQueue:(id)sender {
	[self deleteDownloads:self.actionItems];
	[self deselectAll:nil];
}
	
-(void) deleteDownloads: (NSArray <MTDownload *> *) itemsToRemove {
	for (MTDownload * download in itemsToRemove) {
		if ((download.isInProgress || download.downloadStatus.intValue == kMTStatusSkipModeWaitEnd) && download.downloadStatus.intValue != kMTStatusWaiting) {
			//if just waiting on TiVo, go ahead w/o confirmation
			if( ![self confirmCancel:download.show.showTitle]) {
				//if any cancelled, cancel the whole group
				return;
			}
		}
	}
	[tiVoManager deleteFromDownloadQueue:itemsToRemove];
	if (itemsToRemove.count)[myController playTrashSound];
}

-(BOOL)playVideo {
    for (MTDownload *download in self.actionItems) {
		if (download.isDone) {
			if ([download playVideo])  {
				return YES;		}
		}
	}
    return NO;
}

-(BOOL) askReschedule: (MTDownload *) download {
	//ask user if they'd like to reschedule a show that's being demoted
	NSString *message = [NSString stringWithFormat:@"Do you want to reschedule %@?",download.show.showTitle];
	NSAlert *insertDownloadAlert = [NSAlert alertWithMessageText:message defaultButton:@"Reschedule" alternateButton:@"No" otherButton:nil informativeTextWithFormat:@" "];
	NSInteger returnValue = [insertDownloadAlert runModal];
	if (returnValue == 1) {
		DDLogMajor(@"User did reschedule active show %@",download);
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
	NSAlert *insertDownloadAlert = [NSAlert alertWithMessageText:message defaultButton:@"Re-download" alternateButton:@"No" otherButton:nil informativeTextWithFormat:@" "];
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
    
    NSArray	*classes = @[[MTTiVoShow class], [MTShowFolder class]];
    NSDictionary *options = [NSDictionary dictionary];
    NSArray	*draggedShows = [pboard readObjectsForClasses:classes options:options];
	draggedShows = [draggedShows flattenShows]; //expand any folders
    DDLogMajor(@"Accepting drop: %@", draggedShows);

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


    NSArray <MTDownload *> * newDownloads = [tiVoManager downloadShowsWithCurrentOptions:realShows beforeDownload:insertTarget];
	if (!newDownloads.count) return NO;
	
    self.sortedDownloads = nil;
    [tiVoManager sortDownloadQueue];
    DDLogVerbose(@"afterSort: %@", self.sortedDownloads);

    NSIndexSet * selectionIndexes = [self.sortedDownloads indexesOfObjectsPassingTest:^BOOL(MTDownload * download, NSUInteger idx, BOOL *stop) {
		return [newDownloads containsObject: download];
    }];
	[self insertRowsAtIndexes:selectionIndexes withAnimation:NSTableViewAnimationEffectGap];
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
    NSArray	<MTDownload *> *draggedDLs = [pboard readObjectsForClasses:classes options:options];
    DDLogDetail(@"Accepting drop: %@", draggedDLs);
    if (draggedDLs.count == 0) return NO;
    //dragged downloads are proxies, so we need to find the real download objects
    //we use lastCopy as a cheat to better handle "similar" downloads
    NSMutableArray <MTDownload *> * realDLs = [NSMutableArray arrayWithCapacity:draggedDLs.count ];
    NSMutableArray * completedDownloadsBeingMoved =[NSMutableArray array];
    BOOL useLastCopy = draggedDLs.count == self.lastCopy.count;

    for (NSUInteger i= 0; i<draggedDLs.count; i++) {
        MTDownload * draggedDownload = draggedDLs[i];
        MTDownload * realDownload = nil;
        if (useLastCopy && [self.lastCopy[i] isSimilarTo:draggedDownload]) {
            realDownload = self.lastCopy[i];
        } else {
            realDownload = [tiVoManager findRealDownload:draggedDownload];
        }
        if (realDownload) {
            [realDLs addObject:realDownload];
            if (realDownload.downloadStatus.intValue == kMTStatusRemovedFromQueue) {
            	realDownload.downloadStatus = draggedDownload.downloadStatus;
			}
			realDownload.show.isQueued = YES;
            if (realDownload.isDone) {
                [completedDownloadsBeingMoved addObject:realDownload];
            }
        }
    }

    //Now look for reschedulings. Group could either be moving up over an active show, or moving an active show down...

    for (MTDownload * activeDL in [tiVoManager downloadQueue]) {
        if (activeDL.isNew) break;  //we're through any active ones
        if (activeDL.isDone) continue;
        NSUInteger activeRow = [[tiVoManager downloadQueue] indexOfObject:activeDL];

        if ([realDLs containsObject: activeDL]) {
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
 //   [self scrollRowToVisible:[selectionIndexes firstIndex]];
    return YES;

}

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem{
    if ([menuItem action]==@selector(copy:) ||
		[menuItem action]==@selector(cut:)  ||
		[menuItem action]==@selector(reschedule:)  ||
		[menuItem action]==@selector(subscribe:)  ||
        [menuItem action]==@selector(delete:)) {
        return (self.actionItems.count >0);
    } else  if ([menuItem action]==@selector(paste:)) {
        NSPasteboard * pboard = [NSPasteboard generalPasteboard];
        return  ([pboard.types containsObject:kMTTivoShowPasteBoardType] ||
				 [pboard.types containsObject:kMTTiVoShowArrayPasteBoardType] ||
				 [pboard.types containsObject:kMTDownloadPasteBoardType]);
    }
    return YES;
}

-(IBAction)copy: (id) sender {
	NSArray *selectedShows = self.actionItems;

    if (selectedShows.count > 0) {
        MTDownload * firstDownload = selectedShows[0];
        self.lastCopy = selectedShows;
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
	if (self.clickedRow >=0) row = self.clickedRow;
    NSPasteboard * pboard = [NSPasteboard generalPasteboard];
    if ([pboard.types containsObject:kMTDownloadPasteBoardType]) {
        [self insertDownloadsFromPasteboard:pboard atRow:row];
	} else if ([pboard.types containsObject:kMTTivoShowPasteBoardType] ||
			   [pboard.types containsObject:kMTTiVoShowArrayPasteBoardType]) {
		[self insertShowsFromPasteboard:pboard atRow:row];
    }
}

-(IBAction) delete:(id)sender {
    DDLogMajor(@"user request to delete downloads");
	[self deleteDownloads:self.actionItems];
}

@end
