//
//  MTDownloadList.m
//  myTivo
//
//  Created by Scott Buchanan on 12/8/12.
//  Copyright (c) 2012 Scott Buchanan. All rights reserved.
//

#import "MTDownloadTableView.h"

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

}

-(void)awakeFromNib
{
    self.dataSource = self;
    self.delegate    = self;
    self.allowsMultipleSelection = YES;
	self.columnAutoresizingStyle = NSTableViewUniformColumnAutoresizingStyle;
}

-(void) reloadData {
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
	NSArray *displayedShows = self.sortedShows;
	for (int i=0; i< displayedShows.count; i++) {
		MTDownloadTableCellView *thisCell = [self viewAtColumn:0 row:i makeIfNecessary:NO];
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
    if([identifier compare: @"Program"] == NSOrderedSame) {
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
	} else {
        result =[super makeViewWithIdentifier:identifier owner:owner];
    }
    return result;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
    MTTiVoShow *rowData = [self.sortedShows objectAtIndex:row];
//	NSDictionary *idMapping = [NSDictionary dictionaryWithObjectsAndKeys:@"Title",@"Program",kMTSelectedTiVo,@"TiVo",kMTSelectedFormat,@"Format", nil];
	
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
	if ([tableColumn.identifier compare:@"Program"] == NSOrderedSame) {
		result.progressIndicator.rightText.stringValue = rowData.showStatus;
        result.progressIndicator.leftText.stringValue = rowData.showTitle ;
        result.progressIndicator.doubleValue = rowData.processProgress;
        result.toolTip = rowData.showTitle;
	
    } else if ([tableColumn.identifier compare:@"TiVo"] == NSOrderedSame) {
        result.textField.stringValue = rowData.tiVo.tiVo.name ;
        result.toolTip = result.textField.stringValue;
	
    } else if ([tableColumn.identifier compare:@"Format"] == NSOrderedSame) {
        result.textField.stringValue = [rowData.encodeFormat objectForKey:@"name"] ;
        result.toolTip = result.textField.stringValue;
	
    } else if ([tableColumn.identifier compare:@"iTunes"] == NSOrderedSame) {
        MTCheckBox * checkBox = ((MTDownloadCheckTableCell *)result).checkBox;
        [checkBox setOn: rowData.addToiTunesWhenEncoded];
        [checkBox setEnabled: [rowData.downloadStatus intValue] != kMTStatusDone &&
                              [tiVoManager canAddToiTunes:rowData.encodeFormat] ];
         checkBox.owner = rowData;

 	} else if ([tableColumn.identifier compare:@"Simu"] == NSOrderedSame) {
        MTCheckBox * checkBox = ((MTDownloadCheckTableCell *)result).checkBox;
        [checkBox setOn: rowData.simultaneousEncode];
         checkBox.owner = rowData;
        [checkBox setEnabled: [rowData.downloadStatus intValue] == kMTStatusNew &&
                              [tiVoManager canSimulEncode:rowData.encodeFormat ]];

	}
    
    // return the result.
    return result;
    
}

@end
