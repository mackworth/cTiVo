//
//  MTDownloadList.m
//  myTivo
//
//  Created by Scott Buchanan on 12/8/12.
//  Copyright (c) 2012 Scott Buchanan. All rights reserved.
//

#import "MTDownloadList.h"

@implementation MTDownloadList

-(void)awakeFromNib
{
    self.dataSource = self;
    self.delegate    = self;
    self.allowsMultipleSelection = YES;
	self.columnAutoresizingStyle = NSTableViewUniformColumnAutoresizingStyle;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reloadData) name:kMTNotificationDownloadStatusChanged object:nil];
	tiVoManager = [MTTiVoManager sharedTiVoManager];
}

-(void)updateTable
{
    [self reloadData];
    //Check download Status
}

-(NSArray *)sortedShows
{
	return [tiVoManager.downloadQueue sortedArrayUsingDescriptors:self.sortDescriptors];
}



-(void)updateProgress
{
	NSArray *displayedShows = self.sortedShows;
	for (int i=0; i< displayedShows.count; i++) {
		MTDownloadListCellView *thisCell = [self viewAtColumn:0 row:i makeIfNecessary:NO];
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
        MTDownloadListCellView *thisCell = [[[MTDownloadListCellView alloc] initWithFrame:CGRectMake(0, 0, thisColumn.width, 20)] autorelease];
        //        result.textField.font = [NSFont userFontOfSize:14];
        thisCell.textField.editable = NO;
        
        // the identifier of the NSTextField instance is set to MyView. This
        // allows it to be re-used
        thisCell.identifier = identifier;
        result = (id)thisCell;
    } else if([identifier compare: @"iTunes"] == NSOrderedSame) {
        MTDownloadListCheckCell *thisCell = [[[MTDownloadListCheckCell alloc] initWithFrame:CGRectMake(thisColumn.width/2.0-10, 0, 20, 20) withTarget:myController withAction:@selector(changeiTunes:)] autorelease];
        thisCell.identifier = identifier;
        result = (id)thisCell;
    } else if([identifier compare: @"Simu"] == NSOrderedSame) {
        MTDownloadListCheckCell *thisCell = [[[MTDownloadListCheckCell alloc] initWithFrame:CGRectMake(thisColumn.width/2.0-10, 0, 20, 20) withTarget:myController withAction:@selector(changeSimultaneous:)] autorelease];
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
	
    MTDownloadListCellView *result = [tableView makeViewWithIdentifier:tableColumn.identifier owner:self];
    
    // There is no existing cell to reuse so we will create a new one
    if (result == nil) {
        
        // create the new NSTextField with a frame of the {0,0} with the width of the table
        // note that the height of the frame is not really relevant, the row-height will modify the height
        // the new text field is then returned as an autoreleased object
        result = [[[MTDownloadListCellView alloc] initWithFrame:CGRectMake(0, 0, tableColumn.width, 20)] autorelease];
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
        result.textField.stringValue = rowData.tiVo.name ;
        result.toolTip = result.textField.stringValue;
	} else if ([tableColumn.identifier compare:@"Format"] == NSOrderedSame) {
        result.textField.stringValue = [rowData.encodeFormat objectForKey:@"name"] ;
        result.toolTip = result.textField.stringValue;
	} else if ([tableColumn.identifier compare:@"iTunes"] == NSOrderedSame) {
        NSInteger c = NSOffState;
        if (rowData.addToiTunesWhenEncoded) {
            c = NSOnState;
        }
        [((MTDownloadListCheckCell *)result).checkBox setState:c] ;
        if ([rowData.downloadStatus intValue] != kMTStatusDone) {
            [((MTDownloadListCheckCell *)result).checkBox setEnabled:YES] ;
        } else {
            [((MTDownloadListCheckCell *)result).checkBox setEnabled:NO] ;
        }
        ((MTDownloadListCheckCell *)result).checkBox.owner = rowData;
 	} else if ([tableColumn.identifier compare:@"Simu"] == NSOrderedSame) {
        NSInteger c = NSOffState;
        if (rowData.simultaneousEncode) {
            c = NSOnState;
        }
        [((MTDownloadListCheckCell *)result).checkBox setState:c] ;
        ((MTDownloadListCheckCell *)result).checkBox.owner = rowData;
        if ([rowData.downloadStatus intValue] == kMTStatusNew) {
            [((MTDownloadListCheckCell *)result).checkBox setEnabled:YES] ;
        } else {
            [((MTDownloadListCheckCell *)result).checkBox setEnabled:NO] ;
        }
        
	}
    
    // return the result.
    return result;
    
}

@end
