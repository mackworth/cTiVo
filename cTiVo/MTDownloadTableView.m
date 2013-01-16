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
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reloadData) name:kMTNotificationDownloadStatusChanged object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reloadData) name:kMTNotificationFormatChanged object:nil];

}

-(void)awakeFromNib
{
    self.dataSource = self;
    self.delegate    = self;
    self.allowsMultipleSelection = YES;
	self.columnAutoresizingStyle = NSTableViewUniformColumnAutoresizingStyle;
    tiVoColumnHolder = [[self tableColumnWithIdentifier:@"TiVo"] retain];
}

-(void) reloadData {
    //Configure Table Columns depending on how many TiVos
    NSTableColumn *tiVoColumn = [self tableColumnWithIdentifier:@"TiVo"];
    NSTableColumn *programColumn = [self tableColumnWithIdentifier:@"Programs"];
    if (tiVoManager.tiVoList.count == 1) {
        if (tiVoColumn) {
            [self removeTableColumn:tiVoColumn];
            programColumn.width += tiVoColumn.width + 3;
        }
    } else {
        if (!tiVoColumn) {
            [self addTableColumn:tiVoColumnHolder];
            NSInteger colPos = [self columnWithIdentifier:@"TiVo"];
            [self moveColumn:colPos toColumn:1];
            programColumn.width -= tiVoColumn.width + 3;
        }
    }
    self.sortedShows =nil;
    [super reloadData];
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
    [tiVoColumnHolder release];
    self.sortedShows= nil;
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [super dealloc];
}

#pragma mark - Table Delegate Protocol


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
	MTTiVoShow *rowData = [self.sortedShows objectAtIndex:row];
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
		result.progressIndicator.rightText.stringValue = rowData.showStatus;
 		result.progressIndicator.leftText.stringValue = rowData.showTitle ;
        result.progressIndicator.doubleValue = rowData.processProgress;
        result.toolTip = rowData.showTitle;
	
    } else if ([tableColumn.identifier compare:@"TiVo"] == NSOrderedSame) {
        result.textField.stringValue = rowData.tiVo.tiVo.name ;
        result.toolTip = result.textField.stringValue;
        result.textField.textColor = [NSColor blackColor];
        if (!rowData.tiVo.isReachable && [rowData.downloadStatus intValue] == kMTStatusDownloading) {
            result.textField.textColor = [NSColor redColor];
        }
        
    } else if ([tableColumn.identifier compare:@"Order"] == NSOrderedSame) {
        result.textField.stringValue = [NSString stringWithFormat:@"%@",rowData.downloadIndex] ;
        result.toolTip = result.textField.stringValue;
        
    } else if ([tableColumn.identifier compare:@"Format"] == NSOrderedSame) {
		MTFormatPopUpButton *popUpButton = ((MTPopUpTableCellView *)result).popUpButton;
        popUpButton.owner = rowData;
		popUpButton.formatList = tiVoManager.formatList;
        rowData.encodeFormat = [popUpButton selectFormatNamed:rowData.encodeFormat.name];
        popUpButton.enabled = ([rowData.downloadStatus intValue] == kMTStatusNew);
		
    } else if ([tableColumn.identifier compare:@"iTunes"] == NSOrderedSame) {
        MTCheckBox * checkBox = ((MTDownloadCheckTableCell *)result).checkBox;
        [checkBox setOn: rowData.addToiTunesWhenEncoded];
        [checkBox setEnabled: [rowData.downloadStatus intValue] != kMTStatusDone &&
                              rowData.encodeFormat.canAddToiTunes ];
         checkBox.owner = rowData;

 	} else if ([tableColumn.identifier compare:@"Simu"] == NSOrderedSame) {
        MTCheckBox * checkBox = ((MTDownloadCheckTableCell *)result).checkBox;
        [checkBox setOn: rowData.simultaneousEncode];
         checkBox.owner = rowData;
        [checkBox setEnabled: [rowData.downloadStatus intValue] == kMTStatusNew &&
                              rowData.encodeFormat.canSimulEncode];

	}
    
    // return the result.
    return result;
    
}

@end
