//
//  MTAppDelegate.m
//  myTivo
//
//  Created by Scott Buchanan on 12/6/12.
//  Copyright (c) 2012 Scott Buchanan. All rights reserved.
//

#import "MTAppDelegate.h"
#import "MTTiVo.h"

void signalHandler(int signal)
{
	//Do nothing only use to intercept SIGPIPE.  Ignoring this should be fine as the the retry system should catch the failure and cancel and restart
	NSLog(@"Got signal %d",signal);
}

@implementation MTAppDelegate

- (void)dealloc
{
	[tiVoGlobalManager release];
    [super dealloc];
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    // Insert code here to initialize your application
	
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateTivoRefreshMenu) name:kMTNotificationTiVoListUpdated object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(getMediaKeyFromUser:) name:kMTNotificationMediaKeyNeeded object:nil];
	tiVoGlobalManager = [MTTiVoManager sharedTiVoManager];
	mainWindowController = nil;
	_formatEditorController = nil;
	[self showMainWindow:nil];
	[self updateTivoRefreshMenu];
	mediaKeyQueue = [NSMutableArray new];
	gettingMediaKey = NO;
	signal(SIGPIPE, &signalHandler);
	signal(SIGABRT, &signalHandler );
}

#pragma mark - UI support

-(void)updateTivoRefreshMenu
{
	if (tiVoGlobalManager.tiVoList.count == 0) {
		[refreshTiVoMenuItem setEnabled:NO];
	} else if (tiVoGlobalManager.tiVoList.count ==1) {
		[refreshTiVoMenuItem setTarget:nil];
		[refreshTiVoMenuItem setAction:NULL];
		if (((MTTiVo *)tiVoGlobalManager.tiVoList[0]).isReachable) {
			[refreshTiVoMenuItem setTarget:tiVoGlobalManager.tiVoList[0]];
			[refreshTiVoMenuItem setAction:@selector(updateShows:)];
			[refreshTiVoMenuItem setEnabled:YES];
		} else  {
			[refreshTiVoMenuItem setEnabled:NO];
		}
	} else {
		NSSortDescriptor *sd = [NSSortDescriptor sortDescriptorWithKey:@"tiVo.name" ascending:YES];
		NSArray *sortedTiVos = [[NSArray arrayWithArray:tiVoGlobalManager.tiVoList] sortedArrayUsingDescriptors:[NSArray arrayWithObject:sd]];
		NSMenu *thisMenu = [[[NSMenu alloc] initWithTitle:@"Refresh Tivo"] autorelease];
		for (MTTiVo *tiVo in sortedTiVos) {
			NSMenuItem *thisMenuItem = [[[NSMenuItem alloc] initWithTitle:tiVo.tiVo.name action:NULL keyEquivalent:@""] autorelease];
			if (!tiVo.isReachable) {
				NSFont *thisFont = [NSFont systemFontOfSize:13];
				NSString *thisTitle = [NSString stringWithFormat:@"%@ offline",tiVo.tiVo.name];
				NSAttributedString *aTitle = [[[NSAttributedString alloc] initWithString:thisTitle attributes:[NSDictionary dictionaryWithObjectsAndKeys:[NSColor redColor], NSForegroundColorAttributeName, thisFont, NSFontAttributeName, nil]] autorelease];
				[thisMenuItem setAttributedTitle:aTitle];
			} else {
				[thisMenuItem setTarget:tiVo];
				[thisMenuItem setAction:@selector(updateShows:)];
				[thisMenuItem setEnabled:YES];
			}
			[thisMenu addItem:thisMenuItem];
		}
		NSMenuItem *thisMenuItem = [[[NSMenuItem alloc] initWithTitle:@"All TiVos" action:NULL keyEquivalent:@""] autorelease];
		[thisMenuItem setTarget:self];
		[thisMenuItem setAction:@selector(updateAllTiVos:)];
		[thisMenuItem setEnabled:YES];
		[thisMenu addItem:thisMenuItem];
		[refreshTiVoMenuItem setSubmenu:thisMenu];
		[refreshTiVoMenuItem setEnabled:YES];
	}
	return;
	
}

-(NSNumber *)numberOfUserFormats
{
	return [NSNumber numberWithInteger:tiVoGlobalManager.userFormats.count];
}

-(IBAction)editFormats:(id)sender
{
	[self.formatEditorController showWindow:nil];
}

-(IBAction)exportFormats:(id)sender
{
	NSSavePanel *mySavePanel = [[[NSSavePanel alloc] init] autorelease];
	[mySavePanel setTitle:@"Export User Formats"];
	[mySavePanel setAllowedFileTypes:[NSArray arrayWithObject:@"plist"]];
    [mySavePanel setAccessoryView:formatSelectionTable];
	
	NSInteger ret = [mySavePanel runModal];
	if (ret == NSFileHandlingPanelOKButton) {
        NSMutableArray *formatsToWrite = [NSMutableArray array];
        for (int i = 0; i < tiVoGlobalManager.userFormats.count; i++) {
            //Get selected formats
            NSButton *checkbox = [exportTableView viewAtColumn:0 row:i makeIfNecessary:NO];
            if (checkbox.state) {
                [formatsToWrite addObject:[tiVoGlobalManager.userFormats[i] toDictionary]];
            }
        }
		NSString *filename = mySavePanel.URL.path;
		[formatsToWrite writeToFile:filename atomically:YES];
	}
}

#pragma mark - Table Support Methods

-(NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    return tiVoGlobalManager.userFormats.count;
}

-(CGFloat)tableView:(NSTableView *)tableView heightOfRow:(NSInteger)row
{
    return 17;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
    // get an existing cell with the MyView identifier if it exists
    NSTableCellView *result = [tableView makeViewWithIdentifier:tableColumn.identifier owner:self];
    MTFormat *thisFomat = [tiVoGlobalManager.userFormats objectAtIndex:row];
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
	if ([tableColumn.identifier compare:@"checkBox"] == NSOrderedSame) {
	} else if ([tableColumn.identifier compare:@"name"] == NSOrderedSame) {
        result.textField.stringValue = thisFomat.name;
        result.textField.textColor = [NSColor blackColor];
    }     // return the result.
    return result;
    
}



-(IBAction)importFormats:(id)sender
{
	
	NSArray *newFormats = nil;
	NSOpenPanel *myOpenPanel = [[[NSOpenPanel alloc] init] autorelease];
	[myOpenPanel setTitle:@"Import User Formats"];
	[myOpenPanel setAllowedFileTypes:[NSArray arrayWithObject:@"plist"]];
	NSInteger ret = [myOpenPanel runModal];
	if (ret == NSFileHandlingPanelOKButton) {
		NSString *filename = myOpenPanel.URL.path;
		newFormats = [NSArray arrayWithContentsOfFile:filename];
		[tiVoGlobalManager addFormatsToList:newFormats];	
	}
	
}

-(MTFormatEditorController *)formatEditorController
{
	if (!_formatEditorController) {
		_formatEditorController = [[MTFormatEditorController alloc] initWithWindowNibName:@"MTFormatEditorController"];
	}
	return _formatEditorController;
}

-(void)updateAllTiVos:(id)sender
{
	for (MTTiVo *tiVo in tiVoGlobalManager.tiVoList) {
		[tiVo updateShows:sender];
	}
}

-(void)getMediaKeyFromUser:(NSNotification *)notification
{
	if (notification && notification.object) {  //If sent a new tiVo then add to queue to start
		[mediaKeyQueue addObject:notification.object];
	}
	if (gettingMediaKey || mediaKeyQueue.count == 0) {  //If we're in the middle of a get or nothing to get return
		return;
	}
	MTTiVo *tiVo = [mediaKeyQueue objectAtIndex:0]; //Pop off the first in the queue
	gettingMediaKey = YES;
	if ( tiVo.mediaKey.length == 0 && tiVoGlobalManager.tiVoList.count && tiVo != (MTTiVo *)[tiVoGlobalManager.tiVoList objectAtIndex:0]) {
		tiVo.mediaKey = ((MTTiVo *)[tiVoGlobalManager.tiVoList objectAtIndex:0]).mediaKey;
		[mediaKeyQueue removeObject:tiVo];
		NSLog(@"set key for tivo %@ to %@",tiVo.tiVo.name,tiVo.mediaKey);
		[tiVo updateShows:nil];
	}  else {
		NSString *message = [NSString stringWithFormat:@"Need Media Key for %@",tiVo.tiVo.name];
		if (!tiVo.mediaKeyIsGood && tiVo.mediaKey.length > 0) {
			message = [NSString stringWithFormat:@"Incorrect Media Key for %@",tiVo.tiVo.name];
		}
		NSAlert *keyAlert = [NSAlert alertWithMessageText:message defaultButton:@"New Key" alternateButton:nil otherButton:nil informativeTextWithFormat:@""];
		NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 200, 24)];
		
		[input setStringValue:tiVo.mediaKey];
		[input autorelease];
		[keyAlert setAccessoryView:input];
		NSInteger button = [keyAlert runModal];
		if (button == NSAlertDefaultReturn) {
			[input validateEditing];
			NSLog(@"Got Media Key %@",input.stringValue);
			tiVo.mediaKey = input.stringValue;
			[mediaKeyQueue removeObject:tiVo];
			[tiVo updateShows:nil]; //Assume if needed and got a key we should reload
		}
	}
	gettingMediaKey = NO;
	[[NSUserDefaults standardUserDefaults] setObject:[tiVoGlobalManager currentMediaKeys] forKey:kMTMediaKeys];
	[self getMediaKeyFromUser:nil];//Process rest of queue
}


#pragma mark - Application Support

- (NSURL *)applicationFilesDirectory
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSURL *appSupportURL = [[fileManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask] lastObject];
    return [appSupportURL URLByAppendingPathComponent:@"com.cTiVo.cTivo"];
}

-(IBAction)closeMainWindow:(id)sender
{
    [mainWindowController close];
}

-(IBAction)showMainWindow:(id)sender
{
	if (!mainWindowController) {
		mainWindowController = [[MTMainWindowController alloc] initWithWindowNibName:@"MTMainWindowController"];
	}
	[mainWindowController showWindow:nil];
	
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender
{
    // Save changes in the application's user defaults before the application terminates.
	[tiVoManager writeDownloadQueueToUserDefaults];
    [[NSUserDefaults standardUserDefaults] synchronize];
	[mediaKeyQueue release];
    return NSTerminateNow;
}

@end
