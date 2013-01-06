//
//  MTProgramList.m
//  myTivo
//
//  Created by Scott Buchanan on 12/7/12.
//  Copyright (c) 2012 Scott Buchanan. All rights reserved.
//

#import "MTProgramList.h"
#import "MTDownloadListCheckCell.h"
#import "MTTiVoManager.h"


@implementation MTProgramList

//
//-(id)init
//{
//	self = [super init];
//	if (self) {
//		[self setNotifications];
//	}
//	return self;
//}

-(id) initWithCoder:(NSCoder *)aDecoder
{
	self = [super initWithCoder:aDecoder];
	if (self) {
		[self setNotifications];
	}
	return self;
}

//-(id)initWithFrame:(NSRect)frameRect
//{
//	self = [super initWithFrame:frameRect];
//	if (self) {
//		[self setNotifications];
//	}
//	return self;
//}
//
-(void)setNotifications
{
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reloadEpisode:) name:kMTNotificationReloadEpisode object:nil];
//	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reloadData) name:kMTNotificationShowListUpdated object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reloadData) name:kMTNotificationTiVoShowsUpdated  object:nil];
	
}

-(void)awakeFromNib
{
    self.dataSource = self;
    self.delegate    = self;
    self.allowsMultipleSelection = YES;
	self.columnAutoresizingStyle = NSTableViewUniformColumnAutoresizingStyle;
    self.selectedTiVo = [[NSUserDefaults standardUserDefaults] objectForKey:kMTSelectedTiVo];
}

-(void)reloadData
{
    [super reloadData];
}

-(void)reloadEpisode:(NSNotification *)notification
{
	MTTiVoShow *thisShow = notification.object;
	NSInteger row = 0;
	NSArray *displayedShows = self.sortedShows;
	for (row=0; row < displayedShows.count; row++) {
		if ([displayedShows objectAtIndex:row] == thisShow) {
			break;
		}
	}
	NSInteger column = [self columnWithIdentifier:@"Episode"];
	[self reloadDataForRowIndexes:[NSIndexSet indexSetWithIndex:row] columnIndexes:[NSIndexSet indexSetWithIndex:column]];
}


-(void)dealloc
{
    self.selectedTiVo = nil;
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [super dealloc];
}

#pragma mark - Table Delegate Protocol

-(void)tableViewSelectionDidChange:(NSNotification *)notification
{
	return;
//    NSTableView *viewChanged = (NSTableView *)notification.object;
//    for (int i = 0; i <  _myTivos.recordings.count; i++) {
//        NSTextField *thisRow = [viewChanged viewAtColumn:0 row:i makeIfNecessary:NO];
//        if ([viewChanged isRowSelected:i]) {
//            thisRow.backgroundColor = [NSColor colorWithCalibratedRed:.4 green:.4 blue:1 alpha:.5];
//        } else {
//            thisRow.backgroundColor = [NSColor colorWithCalibratedRed:0 green:0 blue:0 alpha:0];
//        }
//    }
    
}

-(IBAction)selectTivo:(id)sender
{
    if (tiVoManager.tiVoList.count > 1) { //Nothing to change otherwise
        self.selectedTiVo = [(NSPopUpButton *)sender selectedItem].title;
        [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationTiVoListUpdated object:nil];
        [[NSUserDefaults standardUserDefaults] setObject:self.selectedTiVo forKey:kMTSelectedTiVo];
    }
    
}

-(NSArray *)sortedShows
{
    NSMutableArray *arrayToSort = [NSMutableArray arrayWithArray:tiVoManager.tiVoShows];
    NSPredicate *tiVoPredicate = [NSPredicate predicateWithBlock:^BOOL(id evaluatedObject, NSDictionary *bindings) {
        return YES;
    }];;
    if (self.selectedTiVo && [self.selectedTiVo compare:kMTAllTiVos] != NSOrderedSame) { //We need a predicate for filtering
        tiVoPredicate = [NSPredicate predicateWithFormat:@"tiVo.name == %@",self.selectedTiVo];
    }
    [arrayToSort filterUsingPredicate:tiVoPredicate];
	return [arrayToSort  sortedArrayUsingDescriptors:self.sortDescriptors];
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

//-(id)makeViewWithIdentifier:(NSString *)identifier owner:(id)owner
//{
//    id result;
//	NSTableColumn *thisColumn = [self tableColumnWithIdentifier:identifier];
//    if([identifier compare: @"Queued"] == NSOrderedSame) {
//        MTDownloadListCheckCell *thisCell = [[[MTDownloadListCheckCell alloc] initWithFrame:CGRectMake(thisColumn.width/2.0-10, 0, 20, 20)] autorelease];
//        thisCell.identifier = identifier;
//        result = (id)thisCell;
//	} else {
//        result =[super makeViewWithIdentifier:identifier owner:owner];
//    }
//    return result;
//}
//

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
        result = [[[NSTableCellView alloc] initWithFrame:CGRectMake(0, 0, tableView.frame.size.width, 20)] autorelease];
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
		result.textField.stringValue = thisShow.showTitle ;
        result.toolTip = result.textField.stringValue;
	} else if ([tableColumn.identifier compare:@"TiVo"] == NSOrderedSame) {
        result.textField.stringValue = thisShow.tiVo.name;
        result.toolTip = thisShow.tiVo.name;
    } else if ([tableColumn.identifier compare:@"Date"] == NSOrderedSame) {
		result.textField.stringValue = thisShow.showDateString;
		[result.textField setAlignment:NSCenterTextAlignment];
        result.toolTip = result.textField.stringValue;
	} else if ([tableColumn.identifier compare:@"Length"] == NSOrderedSame) {
		result.textField.stringValue = [NSString stringWithFormat:@"%ld:%0.2ld",thisShow.showLength/60,thisShow.showLength % 60];
		[result.textField setAlignment:NSCenterTextAlignment];
        result.toolTip = result.textField.stringValue;
	} else if ([tableColumn.identifier compare:@"Episode"] == NSOrderedSame) {
		result.textField.stringValue = thisShow.seasonEpisode;
		[result.textField setAlignment:NSCenterTextAlignment];
        result.toolTip = result.textField.stringValue;
	} else if ([tableColumn.identifier compare:@"Queued"] == NSOrderedSame) {
//        NSInteger c = NSOffState;
        if (thisShow.isQueued) {
            result.textField.stringValue = @"✔";
        } else {
            result.textField.stringValue = @"";
        }
	}

    // return the result.
    return result;
    
}

@end
