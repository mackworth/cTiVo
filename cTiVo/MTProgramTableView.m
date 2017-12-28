//
//  MTProgramList.m
//  myTivo
//
//  Created by Scott Buchanan on 12/7/12.
//  Copyright (c) 2012 Scott Buchanan. All rights reserved.
//

#import "MTProgramTableView.h"

#import "MTTiVoManager.h"
#import "MTMainWindowController.h"

#import "MTDownloadCheckTableCell.h"
#import "MTProgressCell.h"
#import "DragDropImageView.h"

@interface MTProgramTableView  ()

@property (nonatomic, assign) CGFloat imageRowHeight;

@end
@implementation MTProgramTableView
@synthesize  sortedShows= _sortedShows;

__DDLOGHERE__

#define kMTArtColumn @"Art"
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
        self.imageRowHeight = -1;
	}
	return self;
}

-(void)setNotifications
{
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reloadEpisode:) name:kMTNotificationShowDownloadDidFinish object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reloadEpisode:) name:kMTNotificationDetailsLoaded object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reloadPicture:) name:kMTNotificationPictureLoaded object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reloadData) name:kMTNotificationTiVoShowsUpdated  object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reloadData) name:kMTNotificationTiVoListUpdated object:nil];
 	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(showTiVoColumn:) name:kMTNotificationFoundMultipleTiVos object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshAddToQueueButton:) name:kMTNotificationDownloadQueueUpdated object:nil];
	[[NSUserDefaults standardUserDefaults] addObserver:self forKeyPath:kMTShowCopyProtected options:NSKeyValueObservingOptionInitial context:nil];
	[[NSUserDefaults standardUserDefaults] addObserver:self forKeyPath:kMTShowSuggestions options:NSKeyValueObservingOptionInitial context:nil];
    [[self tableColumnWithIdentifier:kMTArtColumn] addObserver:self forKeyPath:@"hidden" options:0 context:nil];
	[self  setDraggingSourceOperationMask:NSDragOperationMove forLocal:NO];
	[self  setDraggingSourceOperationMask:NSDragOperationCopy forLocal:YES];

}

-(void)showTiVoColumn:(NSNotification *)notification {
    [self tableColumnWithIdentifier:@"TiVo"].hidden = NO;
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
	if ([keyPath isEqualToString:kMTShowCopyProtected] ) {
		DDLogDetail(@"User changed ShowCopyProtected menu item");
 		[self reloadData];
	} else 	if ([keyPath isEqualToString:kMTShowSuggestions]) {
		DDLogDetail(@"User changed ShowSuggestions menu item");
 		[self reloadData];
    } else if ([keyPath isEqualToString:@"hidden"]){
        if (self.imageRowHeight > 0) [self columnChanged:object ];
    } else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

-(void)reloadEpisode:(NSNotification *)notification
{
    MTTiVoShow *thisShow = notification.object;
	NSInteger row = [self.sortedShows indexOfObject:thisShow];
    if (row != NSNotFound) {
        NSRange columns = NSMakeRange(0,self.numberOfColumns);
        [self reloadDataForRowIndexes:[NSIndexSet indexSetWithIndex:row] columnIndexes:[NSIndexSet indexSetWithIndexesInRange:columns]];
    }
}

-(void)reloadPicture:(NSNotification *)notification
{
    MTTiVoShow *thisShow = notification.object;
    NSInteger row = [self.sortedShows indexOfObject:thisShow];
    if (row != NSNotFound) {
        [self reloadDataForRowIndexes:[NSIndexSet indexSetWithIndex:row] columnIndexes:[NSIndexSet indexSetWithIndex:[self columnWithIdentifier:kMTArtColumn] ]];
    }
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


-(IBAction)selectTivo:(id)sender {
    if (tiVoManager.tiVoList.count > 1) { //Nothing to change otherwise
        self.selectedTiVo = ((MTTiVo *)[(NSPopUpButton *)sender selectedItem].representedObject).tiVo.name;
        [[NSUserDefaults standardUserDefaults] setObject:self.selectedTiVo forKey:kMTSelectedTiVo];
        [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationTiVoListUpdated object:_selectedTiVo];
    }
}

-(NSInteger)numberOfSelectedRows {
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
    CGFloat oldWidth = ((NSNumber *)notification.userInfo[@"NSOldWidth"]).floatValue;
    if ([column.identifier isEqualToString:@"icon" ]  ||
         [column.identifier isEqualToString:kMTArtColumn ]  ) {
        DDLogVerbose(@"changed column width for %@ from %0.1f to %0.1f", column.identifier, oldWidth, column.width );
        if (ABS(column.width - oldWidth) < 3.0) return; //patch to prevent height/width looping in High Sierra
        NSIndexSet * allRows = [NSIndexSet indexSetWithIndexesInRange: NSMakeRange(0, self.sortedShows.count) ];
       if ( [column.identifier isEqualToString:kMTArtColumn ] && self.imageRowHeight > 0) {
            self.imageRowHeight = -self.imageRowHeight;  //use as trigger to recalculate, but remember old size in case it hasn't changed.
           [self noteHeightOfRowsWithIndexesChanged: allRows ];
		   [self reloadData];
	   } else {
        	[self reloadDataForRowIndexes: allRows
                            columnIndexes:[NSIndexSet indexSetWithIndex: [[self tableColumns] indexOfObject:column]]];
	   }
    }
}

-(void) columnChanged: (NSTableColumn *) column {
    //called when column added or deleted
    if ([column.identifier isEqualToString: kMTArtColumn]) {
        //have to confirm height changed
        if (column.isHidden) {
            //free up memory from images
            for (MTTiVoShow * show in tiVoManager.tiVoShows) {
                show.thumbnailImage = nil;
            }
        }
        if (self.imageRowHeight > 0) {
            self.imageRowHeight = -self.imageRowHeight;  //use as trigger to recalculate, but remember old size in case it hasn't changed.
        } else if (self.imageRowHeight == 0){
            self.imageRowHeight = -1;
        }
        [self reloadData];
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

-(CGFloat) tableView:(NSTableView *)tableView heightOfRow:(NSInteger)row {
    //use negative numbers to indicate we need to recalculate, but save old one as negative to see if we need to reload or not.
    //Yes, it's ugly.
    //even worse, sometimes imageColumn.hidden is incorrectly NO the first time after relaunch;
    //and then sometimes hidden correctly changes back to YES but without notifying columndidChange,
    //so we have to add a special observer on the hidden keypath!

    if (self.imageRowHeight < 0) {
        NSTableColumn *imageColumn = [self tableColumnWithIdentifier:kMTArtColumn];
        CGFloat newRowHeight = [super rowHeight];
        if  (!imageColumn.hidden ) {
           newRowHeight =  MAX(newRowHeight, 9.0/16.0*imageColumn.width);
        }
        DDLogVerbose(@"rowHeight calculation: %0.1f => %0.1f .", -self.imageRowHeight, newRowHeight);
        if (newRowHeight != -self.imageRowHeight) {
            //now preserve the current first row.
            CGPoint scroll = self.enclosingScrollView.contentView.bounds.origin;
            NSInteger spacing = [self intercellSpacing].height;
            scroll.y = scroll.y/(-self.imageRowHeight+spacing) * (newRowHeight+spacing);
            [self scrollPoint:scroll];
        }
        self.imageRowHeight = newRowHeight;
    }
    return self.imageRowHeight;
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

    NSString * textVal = @"";
    result.toolTip = @"";
    result.imageView.image = nil;
    NSString* identifier = tableColumn.identifier;
	result.frame =CGRectMake(0,0, tableColumn.width, self.imageRowHeight);
    if ([tableColumn.identifier isEqualToString:@"Programs"]) {
       textVal = thisShow.showTitle?: @"" ;
        result.toolTip = textVal;
    } else if ([identifier isEqualToString:@"TiVo"]) {
        textVal = thisShow.tiVoName;
        result.textField.textColor = [NSColor blackColor];
        if (!thisShow.tiVo.isReachable) {
            result.textField.textColor = [NSColor redColor];
        }
        result.toolTip = thisShow.tiVoName;
    } else if ([identifier isEqualToString:@"Date"]) {
        if ([tableColumn width] > 135) {
            textVal = thisShow.showMediumDateString;
        } else {
            textVal = thisShow.showDateString;
        }
        result.toolTip = textVal;
    } else if ([identifier isEqualToString:@"Length"]) {
        textVal = thisShow.lengthString;
        result.toolTip = textVal;
    } else if ([identifier isEqualToString:@"Series"]) {
        textVal = thisShow.seriesTitle;
        result.toolTip = textVal;
    } else if ([identifier isEqualToString:@"Episode"]) {
        textVal = thisShow.seasonEpisode;
        result.toolTip = textVal;
    } else if ([identifier isEqualToString:@"Queued"]) {
        textVal = thisShow.isQueuedString;
    } else if ([identifier isEqualToString:@"OnDisk"]) {
        textVal = thisShow.isOnDiskString;
        result.toolTip =@"Is program already downloaded and still on disk?";
   } else if ([identifier isEqualToString:@"HD"]) {
        textVal = thisShow.isHDString;
        result.textField.alignment = NSCenterTextAlignment;
    } else if ([identifier isEqualToString:@"Channel"]) {
        textVal = thisShow.channelString;
    } else if ([identifier isEqualToString:@"Size"]) {
        textVal = thisShow.sizeString;
    } else if ([identifier isEqualToString:@"TiVoID"]) {
        textVal = thisShow.idString;
    } else if ([identifier isEqualToString:@"EpisodeID"]) {
        textVal = thisShow.episodeID;
    } else if ([identifier isEqualToString:@"Title"]) {
        textVal = thisShow.episodeTitle;
        result.toolTip = textVal;
    } else if ([identifier isEqualToString:@"Station"]) {
        textVal = thisShow.stationCallsign;
    } else if ([identifier isEqualToString:@"Genre"]) {
        textVal = thisShow.episodeGenre;
        result.toolTip = textVal;
    } else if ([identifier isEqualToString:@"AgeRating"]) {
        textVal = thisShow.ageRatingString;
        result.toolTip = textVal;
    } else if ([identifier isEqualToString:@"StarRating"]) {
        textVal = thisShow.starRatingString;
    } else if ([identifier isEqualToString:@"FirstAirDate"]) {
        textVal = thisShow.originalAirDateNoTime ?: @"";
    } else if ([identifier isEqualToString:@"H.264"]) {
        textVal = thisShow.h264String;
        result.textField.alignment = NSCenterTextAlignment;
        result.toolTip =@"Does this channel use H.264 compression?";
    } else if ([identifier isEqualToString: kMTArtColumn]) {
//        DDLogVerbose(@"looking for image for %@",thisShow);
       MTProgressCell * cell = (MTProgressCell *) result;
        DragDropImageView * imageView = (DragDropImageView *) result.imageView;
        imageView.delegate = thisShow; //drag drop support
		CGRect rect = CGRectMake(0, 0, tableColumn.width, fabs(self.imageRowHeight));
		cell.frame = rect;
		cell.imageView.frame = rect;
		cell.progressIndicator.frame = rect;
        NSImage * image = thisShow.thumbnailImage;
        if (image) {
			DDLogVerbose(@"got image for %@: %@",thisShow, NSStringFromRect(cell.bounds));
            imageView.image = image ;
			imageView.autoresizingMask = NSViewMinXMargin | NSViewMaxXMargin| NSViewMinYMargin |NSViewMaxYMargin;
            imageView.imageScaling = NSImageScaleProportionallyUpOrDown;
            cell.progressIndicator.hidden = YES;
            [cell.progressIndicator stopAnimation:self];
        } else if (thisShow.noImageAvailable) {
            //no image, and it's never coming
            DDLogVerbose(@"No image for %@",thisShow);
           imageView.image = nil ;
            cell.progressIndicator.hidden = YES;
            [cell.progressIndicator stopAnimation:self];
       } else {
            //no image, but it may be coming
           DDLogVerbose(@"Waiting for image for %@",thisShow); 
           imageView.image = nil ;
            cell.progressIndicator.hidden = NO;
            [cell.progressIndicator startAnimation:self];
        }

    } else if ([identifier isEqualToString:@"icon"]) {
        MTProgressCell * cell = (MTProgressCell *) result;
        NSImageView * imageView = cell.imageView;
        NSString * imageName = thisShow.imageString;
        imageView.imageScaling = NSImageScaleProportionallyUpOrDown;
        imageView.image = [NSImage imageNamed: imageName];
        CGFloat width = tableColumn.width;
        CGFloat height = MIN(width, MIN(self.imageRowHeight, 24));
        CGFloat leftMargin = (width -height)/2;
        CGFloat topMargin = (self.imageRowHeight-height)/2;
		imageView.frame = CGRectMake(leftMargin, topMargin, height, height);
        imageView.animates = YES;
        result.toolTip = [[imageName stringByReplacingOccurrencesOfString:@"-" withString:@" "] capitalizedString];
    } else {
        DDLogReport(@"Invalid Column: %@", identifier);
    }
    result.textField.stringValue = textVal ?: @"";
    if ([thisShow.protectedShow boolValue]) {
		result.textField.font = [[NSFontManager sharedFontManager] convertFont:result.textField.font toNotHaveTrait:NSFontBoldTrait];
        result.textField.textColor = [NSColor grayColor];
    } else if ([thisShow isOnDisk]){
        result.textField.font = [[NSFontManager sharedFontManager] convertFont:result.textField.font toHaveTrait:NSFontBoldTrait];
        result.textField.textColor = [NSColor blackColor];
    } else {
		result.textField.font = [[NSFontManager sharedFontManager] convertFont:result.textField.font toNotHaveTrait:NSFontBoldTrait];
       result.textField.textColor = [NSColor blackColor];
    }
	CGFloat rowHeight = ABS(self.imageRowHeight);
	CGFloat textSize = MIN(result.textField.font.pointSize + 4, rowHeight);
	result.textField.frame = CGRectMake(0, round((rowHeight-textSize)/2), tableColumn.width, textSize );
	result.textField.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin | NSViewMaxYMargin;
	result.textField.translatesAutoresizingMaskIntoConstraints = YES;
    // return the result.
    return result;
}
#pragma mark Drag N Drop support

/*// What kind of drag operation should I perform?
- (NSDragOperation)tableView:(NSTableView*)tv validateDrop:(id )info proposedRow:(NSInteger)row proposedDropOperation:(NSTableViewDropOperation)op {
    return op == NSTableViewDropOn ? NSDragOperationCopy : NSDragOperationNone; // Specifies that the drop should occur on the specified row.
}

// The mouse button was released over a row in the table view, should I accept the drop?
- (BOOL)tableView:(NSTableView *) tv acceptDrop:(id )info row:(NSInteger)row dropOperation:(NSTableViewDropOperation)op {
    MTTiVoShow * show = self.sortedShows[row];
    NSLog(@"Dragged Show: %@", show);
    return YES;
}

- (NSDragOperation)draggingEntered:(id <NSDraggingInfo>)sender
{
    if ([[[sender draggingPasteboard] types] containsObject:NSFilenamesPboardType]) {
        return NSDragOperationCopy;
    }
    
    return NSDragOperationNone;
}

- (BOOL)performDragOperation:(id <NSDraggingInfo>)sender {
    NSPasteboard *pboard;
    pboard = [sender draggingPasteboard];
    NSPoint windowDropPoint = [sender draggingLocation];
    NSPoint tableDropPoint = [self convertPoint:windowDropPoint fromView:nil];
    NSUInteger row = [self rowAtPoint:tableDropPoint];
    if (row >= self.sortedShows.count) return NO;
    MTTiVoShow * show = self.sortedShows[row];
    NSImage * image = [[NSImage alloc] initWithPasteboard:pboard];
    if (image) {
        [show setArtworkFromImage: image];
        return YES;
    } else {
        return NO;
    }
}
*/

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

-(void) mouseDown:(NSEvent *)event {
    //pass drag drop to ArtColumn if present
    NSPoint p = [self convertPoint: event.locationInWindow fromView:nil];
    NSInteger c = [self columnAtPoint:p];
    NSInteger r = [self rowAtPoint:p];
    if (c >= 0 && r >= 0 && [self.tableColumns[c].identifier isEqualToString:kMTArtColumn]){
        NSTableCellView *showCellView = [self viewAtColumn:c row:r makeIfNecessary:NO];
        [showCellView.imageView mouseDown:event];
    } else {
        [super mouseDown:event];
    }

}
-(NSDragOperation) draggingEntered:(id<NSDraggingInfo>)sender {
    return NSDragOperationCopy;
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
    BOOL deleteItem = [menuItem action]==@selector(delete:);
    BOOL stopItem =   [menuItem action]==@selector(stopRecording:);
    if (deleteItem || stopItem ) {
        if (deleteItem) menuItem.title = @"Delete from TiVo"; //alternates with remove from Queue
        NSIndexSet *selectedRowIndexes = [self selectedRowIndexes];
        NSArray	*selectedShows = [self.sortedShows objectsAtIndexes:selectedRowIndexes ];
        for (MTTiVoShow * show in selectedShows) {
            if (show.rpcData && show.tiVo.rpcActive) {
                if (stopItem) {
                    if (show.inProgress.boolValue) return YES;
                } else {
                    return YES;
                }
            }
        }
        return NO;
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

-(BOOL) confirmBehavior: (NSString *) behavior preposition:(NSString *) prep forShows:(NSArray <MTTiVoShow *> *) shows {
    NSString * msg = nil;
    if (shows.count == 1) {
        msg = [NSString stringWithFormat:@"Are you sure you want to %@ '%@' %@ TiVo %@?", behavior, shows[0].showTitle, prep, shows[0].tiVoName ];
    } else if (shows.count == 2) {
        msg = [NSString stringWithFormat:@"Are you sure you want to %@ '%@' and '%@' %@ your TiVo?",behavior, shows[0].showTitle, shows[1].showTitle, prep ];
    } else {
        msg = [NSString stringWithFormat:@"Are you sure you want to %@ '%@' and %d others %@ your TiVo?", behavior, shows[0].showTitle, (int)shows.count -1, prep ];
    }

    NSAlert *myAlert = [NSAlert alertWithMessageText:msg defaultButton:@"No" alternateButton:@"Yes" otherButton:nil informativeTextWithFormat:@"This cannot be undone."];
    myAlert.alertStyle = NSCriticalAlertStyle;
    NSInteger result = [myAlert runModal];
    return (result == NSAlertAlternateReturn);
}

-(IBAction)delete:(id)sender {
    NSIndexSet *selectedRowIndexes = [self selectedRowIndexes];
    if (selectedRowIndexes.count == 0) return;
    NSArray	<MTTiVoShow *> *selectedShows = [self.sortedShows objectsAtIndexes:selectedRowIndexes ];
    if ([self confirmBehavior:@"delete" preposition: @"from" forShows:selectedShows]) {
        [tiVoManager deleteTivoShows:selectedShows];
    }
}

-(IBAction)stopRecording:(id)sender {
    NSIndexSet *selectedRowIndexes = [self selectedRowIndexes];
    if (selectedRowIndexes.count ==0) return;
   NSArray <MTTiVoShow *>	*selectedShows = [self.sortedShows objectsAtIndexes:selectedRowIndexes ];
    if ([self confirmBehavior:@"stop recording" preposition:@"on" forShows:selectedShows]) {
        [tiVoManager stopRecordingShows:selectedShows];
    }
}

-(void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[[self tableColumnWithIdentifier:kMTArtColumn] removeObserver:self forKeyPath:@"hidden" ];
	[[NSUserDefaults standardUserDefaults] removeObserver:self forKeyPath:kMTShowCopyProtected ];
	[[NSUserDefaults standardUserDefaults] removeObserver:self forKeyPath:kMTShowSuggestions ];
}


@end
