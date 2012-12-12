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
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateTable) name:kMTNotificationDownloadQueueUpdated object:nil];
    self.dataSource = self;
    self.delegate    = self;
//    self.rowHeight = 24;
    self.allowsMultipleSelection = YES;
}

-(void)updateTable
{
    [super reloadData];
    [_myTivos manageDownloads];
}

-(void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [super dealloc];
}

#pragma mark - Table Delegate Protocol

-(void)tableViewSelectionDidChange:(NSNotification *)notification
{
	return;
//    NSTableView *viewChanged = (NSTableView *)notification.object;
//    for (int i = 0; i <  _myTivos.downloadQueue.count; i++) {
//        NSTextField *thisRow = [viewChanged viewAtColumn:0 row:i makeIfNecessary:NO];
//        if ([viewChanged isRowSelected:i]) {
//            thisRow.backgroundColor = [NSColor colorWithCalibratedRed:.4 green:.4 blue:1 alpha:.5];
//        } else {
//            thisRow.backgroundColor = [NSColor colorWithCalibratedRed:0 green:0 blue:0 alpha:0];
//        }
//    }
    
}


#pragma mark - Table Data Source Protocol

- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView
{
    return _myTivos.downloadQueue.count;
}

-(id)makeViewWithIdentifier:(NSString *)identifier owner:(id)owner
{
    id result;
    if([identifier compare: @"Program"] == NSOrderedSame) {
        NSTableColumn *thisColumn = [self tableColumnWithIdentifier:identifier];
        MTDownloadListCellView *thisCell = [[[MTDownloadListCellView alloc] initWithFrame:CGRectMake(0, 0, thisColumn.width, 20)] autorelease];
        //        result.textField.font = [NSFont userFontOfSize:14];
        thisCell.textField.editable = NO;
        
        // the identifier of the NSTextField instance is set to MyView. This
        // allows it to be re-used
        thisCell.identifier = identifier;
        result = (id)thisCell;
    } else {
        result =[super makeViewWithIdentifier:identifier owner:owner];       
    }
    return result;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
    NSDictionary *rowData = [_myTivos.downloadQueue objectAtIndex:row];
	NSDictionary *idMapping = [NSDictionary dictionaryWithObjectsAndKeys:@"Title",@"Program",kMTSelectedTivo,@"TiVo",kMTSelectedFormat,@"Format", nil];
	
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
	NSString *dataKey = [idMapping objectForKey:tableColumn.identifier];
	id columnItem = [rowData objectForKey:dataKey];
	NSString *content = @"";
	if ([dataKey compare:@"Title"] == NSOrderedSame) {
		content = columnItem;
		result.progressIndicator.rightText.stringValue = [rowData objectForKey:kMTDownloadStatus];
        result.progressIndicator.leftText.stringValue = content ;
        result.progressIndicator.doubleValue = [[rowData objectForKey:kMTDownloadPercent] doubleValue];
	} else if ([dataKey compare:kMTSelectedTivo] == NSOrderedSame) {
		content	= [columnItem name];
        result.textField.stringValue = content ;
	} else {
		content	= [columnItem objectForKey:@"name"];
        result.textField.stringValue = content ;
	}
    
    // return the result.
    return result;
    
}

@end
