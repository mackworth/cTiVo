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

__DDLOGHERE__

-(id) initWithCoder:(NSCoder *)aDecoder
{
	self = [super initWithCoder:aDecoder];
	if (self) {
		[self setNotifications];
        DDLogVerbose(@"ProgramTable init");
        self.dataSource = self;
        self.delegate    = self;
        self.allowsMultipleSelection = YES;
        self.columnAutoresizingStyle = NSTableViewUniformColumnAutoresizingStyle;
        self.selectedTiVo = [[NSUserDefaults standardUserDefaults] objectForKey:kMTSelectedTiVo];
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
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reloadEpisode:) name:kMTNotificationShowDownloadDidFinish object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reloadEpisode:) name:kMTNotificationDetailsLoaded object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reloadData) name:kMTNotificationTiVoShowsUpdated  object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reloadData) name:kMTNotificationTiVoListUpdated object:nil];
 	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(showTiVoColumn:) name:kMTNotificationFoundMultipleTiVos object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshAddToQueueButton:) name:kMTNotificationDownloadQueueUpdated object:nil];
	[[NSUserDefaults standardUserDefaults] addObserver:self forKeyPath:kMTShowCopyProtected options:NSKeyValueObservingOptionInitial context:nil];
	[[NSUserDefaults standardUserDefaults] addObserver:self forKeyPath:kMTShowSuggestions options:NSKeyValueObservingOptionInitial context:nil];
	
	[self  setDraggingSourceOperationMask:NSDragOperationMove forLocal:NO];
	[self  setDraggingSourceOperationMask:NSDragOperationCopy forLocal:YES];

}

-(void)showTiVoColumn:(NSNotification *)notification
{
    NSTableColumn *tiVoColumn = [self tableColumnWithIdentifier:@"TiVo"];
	[tiVoColumn setHidden:NO];
	
}

-(void) reloadData {
    //Configure Table Columns depending on how many TiVos
	DDLogVerbose(@"Reload Program Table");
	//save selection to preserve after reloadData
	NSIndexSet * selectedRowIndexes = [self selectedRowIndexes];
    NSArray * selectedShows = [self.sortedShows objectsAtIndexes:selectedRowIndexes];
    
	self.sortedShows = nil;
    [super reloadData];
    
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
		DDLogDetail(@"User changed ShowCopyProtected menu item");
 		[self reloadData];
	} else 	if ([keyPath compare:kMTShowSuggestions] == NSOrderedSame) {
		DDLogDetail(@"User changed ShowSuggestions menu item");
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
    tiVoColumnHolder = nil;
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}
#pragma mark find/filter support

-(void) showFindField: (BOOL) show {
	[self.findText setHidden:!show];
	[self.findText setEnabled:show];
	[self.findLabel setHidden:!show];
	if (!show) {
		self.findText.stringValue = @"";
		[self reloadData];
	}
}

- (BOOL)isTextFieldInFocus:(NSTextField *)textField
{
	NSResponder *firstResponder = [[textField window] firstResponder];
	BOOL inFocus = ([firstResponder isKindOfClass:[NSTextView class]]
			   && [[textField window] fieldEditor:NO forObject:nil]!=nil
			   && [textField isEqualTo:(id)((NSTextView *)firstResponder).delegate]
					 );
	
	return inFocus;
}

-(IBAction)findShows:(id)sender {
	if ([self isTextFieldInFocus:self.findText]) {
		[self.window makeFirstResponder:nil];
		[self showFindField:NO];
	} else {
		[self showFindField:YES];
		[self.window makeFirstResponder:self.findText];
	}
}
-(IBAction)changedSearchText:(id)sender {
	if (sender != self.findText) {
		DDLogMajor(@"Error invalid textField %@", sender);
		return;
	}
	DDLogVerbose(@"FindText = %@",self.findText.stringValue);
	[self reloadData];
}

-(void)textDidEndEditing:(NSNotification *) notification {
	if (notification.object != self.findText) {
		DDLogMajor(@"Error invalid textField %@", notification.object);
		return;
	}
	int movementCode = [notification.userInfo[@"NSTextMovement"] intValue];
	DDLogVerbose(@"Ending FindText = %@",self.findText.stringValue);
	if (movementCode == NSCancelTextMovement || [self.findText.stringValue isEqualToString:@""]) {
		[self showFindField:NO];
	}
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
		DDLogVerbose(@"Re-sorting Program table");
		NSPredicate *yesPredicate =	[NSPredicate predicateWithValue:YES];

		NSPredicate *protectedPredicate = yesPredicate;
		if ( ! [[[NSUserDefaults standardUserDefaults] objectForKey:kMTShowCopyProtected] boolValue]) {
			protectedPredicate = [NSPredicate predicateWithFormat:@"protectedShow == %@",[NSNumber numberWithBool:NO]];
		}
		
		NSPredicate *suggestedPredicate = yesPredicate;
		if ( ! [[[NSUserDefaults standardUserDefaults] objectForKey:kMTShowSuggestions] boolValue]) {
			suggestedPredicate = [NSPredicate predicateWithFormat:@"isSuggestion == NO"];
		}
		
		NSPredicate *findPredicate = yesPredicate;
		if (self.findText.stringValue.length > 0) {
			findPredicate = [NSPredicate predicateWithFormat:@"showTitle contains[cd] %@",self.findText.stringValue];
		}
		
		NSPredicate *tiVoPredicate = yesPredicate;
		if (self.selectedTiVo && [tiVoManager foundTiVoNamed:self.selectedTiVo] && [self.selectedTiVo compare:kMTAllTiVos] != NSOrderedSame) { //We need a predicate for filtering
			tiVoPredicate = [NSPredicate predicateWithFormat:@"tiVo.tiVo.name == %@",self.selectedTiVo];
		}
		NSArray * whichShows = [[[[tiVoManager.tiVoShows filteredArrayUsingPredicate:tiVoPredicate]
					 filteredArrayUsingPredicate:findPredicate]
					filteredArrayUsingPredicate:protectedPredicate]
				   filteredArrayUsingPredicate:suggestedPredicate];
		self.sortedShows = [whichShows
				sortedArrayUsingDescriptors:self.sortDescriptors];
	}
	return _sortedShows;
}

- (void) refreshAddToQueueButton: (NSNotification *) notification {
	if (tiVoManager.processingPaused.boolValue || [tiVoManager anyShowsWaiting]) {
		addToQueueButton.title =@"Add to Queue";
	} else {
		addToQueueButton.title = @"Download";
	}
}

-(void)tableViewSelectionDidChange:(NSNotification *)notification
{
	NSInteger numRows = [self numberOfSelectedRows];
	[addToQueueButton setEnabled:numRows != 0];
	[subscribeButton setEnabled: numRows != 0];
    if (numRows == 1) {
		NSIndexSet *selectedRowIndexes = [self selectedRowIndexes];
		NSArray *selectedRows = [self.sortedShows objectsAtIndexes:selectedRowIndexes];
        [myController setValue:selectedRows[0] forKey:@"showForDetail"];
    }
}

-(void) tableViewColumnDidResize:(NSNotification *) notification {

	NSTableColumn * column = notification.userInfo[@"NSTableColumn"];
    if (([column.identifier compare:@"Date" ] ==NSOrderedSame) || ([column.identifier compare:@"icon" ] ==NSOrderedSame)) {
        NSInteger columnNum = [self columnWithIdentifier:column.identifier];
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

-(void)prepareContentInRect:(NSRect)rect {
    NSRect visibleRect = [self visibleRect];
    CGFloat newHeight = (rect.size.height + visibleRect.size.height)/2.0;
    NSRect newRect = CGRectMake(rect.origin.x, rect.origin.y, rect.size.width, newHeight);
    [super prepareContentInRect:newRect];
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
	MTTiVoShow *thisShow = [self.sortedShows objectAtIndex:row];
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
    
    NSString * textVal = @"";
    result.toolTip = @"";
    if ([tableColumn.identifier compare:@"Programs"] == NSOrderedSame) {
       textVal = thisShow.showTitle?: @"" ;
        result.toolTip = textVal;
    } else if ([tableColumn.identifier compare:@"TiVo"] == NSOrderedSame) {
        textVal = thisShow.tiVoName;
        result.textField.textColor = [NSColor blackColor];
        if (!thisShow.tiVo.isReachable) {
            result.textField.textColor = [NSColor redColor];
        }
        result.toolTip = thisShow.tiVoName;
    } else if ([tableColumn.identifier compare:@"Date"] == NSOrderedSame) {
        if ([tableColumn width] > 135) {
            textVal = thisShow.showMediumDateString;
        } else {
            textVal = thisShow.showDateString;
        }
        result.toolTip = textVal;
    } else if ([tableColumn.identifier compare:@"Length"] == NSOrderedSame) {
        textVal = thisShow.lengthString;
        result.toolTip = textVal;
    } else if ([tableColumn.identifier compare:@"Series"] == NSOrderedSame) {
        textVal = thisShow.seriesTitle;
        result.toolTip = textVal;
    } else if ([tableColumn.identifier compare:@"Episode"] == NSOrderedSame) {
        textVal = thisShow.seasonEpisode;
        result.toolTip = textVal;
    } else if ([tableColumn.identifier compare:@"Queued"] == NSOrderedSame) {
        textVal = thisShow.isQueuedString;
    } else if ([tableColumn.identifier compare:@"HD"] == NSOrderedSame) {
        textVal = thisShow.isHDString;
        result.textField.alignment = NSCenterTextAlignment;
    } else if ([tableColumn.identifier compare:@"Channel"] == NSOrderedSame) {
        textVal = thisShow.channelString;
    } else if ([tableColumn.identifier compare:@"Size"] == NSOrderedSame) {
        textVal = thisShow.sizeString;
    } else if ([tableColumn.identifier compare:@"TiVoID"] == NSOrderedSame) {
        textVal = thisShow.idString;
    } else if ([tableColumn.identifier compare:@"EpisodeID"] == NSOrderedSame) {
        textVal = thisShow.episodeID;
    } else if ([tableColumn.identifier compare:@"Title"] == NSOrderedSame) {
        textVal = thisShow.episodeTitle;
        result.toolTip = textVal;
    } else if ([tableColumn.identifier compare:@"Station"] == NSOrderedSame) {
        textVal = thisShow.stationCallsign;
    } else if ([tableColumn.identifier compare:@"Genre"] == NSOrderedSame) {
        textVal = thisShow.episodeGenre;
        result.toolTip = textVal;
    } else if ([tableColumn.identifier compare:@"FirstAirDate"] == NSOrderedSame) {
        textVal = thisShow.originalAirDateNoTime ?: @"";
    } else if ([tableColumn.identifier isEqualToString:@"icon"]) {
        NSString * imageName = thisShow.imageString;
        result.imageView.autoresizingMask = NSViewMinXMargin | NSViewMaxXMargin| NSViewMinYMargin |NSViewMaxYMargin;
        result.autoresizingMask = NSViewMinXMargin | NSViewMaxXMargin| NSViewMinYMargin |NSViewMaxYMargin;
        result.imageView.image = [NSImage imageNamed: imageName];
        result.toolTip = [[imageName stringByReplacingOccurrencesOfString:@"-" withString:@" "] capitalizedString];
    }
    result.textField.stringValue = textVal ?: @"";
    result.textField.font = [[NSFontManager sharedFontManager] convertFont:result.textField.font toNotHaveTrait:NSFontBoldTrait];
    if ([thisShow.protectedShow boolValue]) {
        result.textField.textColor = [NSColor grayColor];
    } else if ([tiVoManager.showsOnDisk objectForKey:thisShow.showKey]){
        //        result.textField.textColor = [NSColor blueColor];
        result.textField.font = [[NSFontManager sharedFontManager] convertFont:result.textField.font toHaveTrait:NSFontBoldTrait];
        result.textField.textColor = [NSColor blackColor];
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
            return NSDragOperationCopy;  //could theoretically allow, as completed shows are also here.
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
		if (r < 0) {
			r = 0;
		}
		NSInteger c = [tv columnAtPoint:p];
		if (c < 0) {
			c = 0;
		}
//		NSTableColumn *selectedColumn = tv.tableColumns[c];
//        NSTableCellView *selectedCell = selectedColumn.dataCell;
		BOOL isSelectedRow = [tv isRowSelected:r];
		BOOL isOverText = NO;
        NSTableCellView *showCellView = [tv viewAtColumn:c row:r makeIfNecessary:NO];
        NSTextAlignment alignment = showCellView.textField.alignment;
        NSTextField *showField = showCellView.textField;
		if (showField) {
			NSPoint clickInText = [showField convertPoint:windowPoint fromView:nil];
			NSSize stringSize = [showField.stringValue sizeWithAttributes:@{NSFontAttributeName : showField.font}];
			NSSize cellSize = showCellView.frame.size;
			switch (alignment) {
				case NSLeftTextAlignment:
				case NSNaturalTextAlignment:
					if (clickInText.x < stringSize.width) {
						isOverText = YES;
					}
					break;
				case NSRightTextAlignment:
					if (clickInText.x > cellSize.width - stringSize.width) {
						isOverText = YES;
					}
					break;
				case NSCenterTextAlignment:
					if (clickInText.x < (cellSize.width + stringSize.width)/2.0 && clickInText.x > (cellSize.width - stringSize.width)/2.0) {
						isOverText = YES;
					}
					break;
					
				default:
					break;
			}
		}
		if (!isSelectedRow && !isOverText) {
			return NO;
		}
	}
	// Drag and drop support
	[self selectRowIndexes:rowIndexes byExtendingSelection:NO ];
	NSArray	*selectedObjects = [self.sortedShows objectsAtIndexes:rowIndexes ] ;
	DDLogVerbose(@"Dragging Objects: %@", selectedObjects);
	[pboard writeObjects:selectedObjects];
   return (selectedObjects.count > 0);
}

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem{
    if ([menuItem action]==@selector(copy:)) {
        return (self.numberOfSelectedRows >0);
    } 
    return YES;
}

-(IBAction)copy: (id) sender {
    NSIndexSet *selectedRowIndexes = [self selectedRowIndexes];

    NSArray	*selectedShows = [self.sortedShows objectsAtIndexes:selectedRowIndexes ];

    if (selectedShows.count > 0) {
        MTTiVoShow * firstShow = selectedShows[0];

        NSPasteboard * pboard = [NSPasteboard generalPasteboard];
        [pboard declareTypes:[firstShow writableTypesForPasteboard:pboard] owner:nil];
        [[NSPasteboard generalPasteboard] writeObjects:selectedShows];
   }
}


@end
