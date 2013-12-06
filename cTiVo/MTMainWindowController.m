//
//  MTMainWindowController.m
//  cTiVo
//
//  Created by Scott Buchanan on 12/13/12.
//  Copyright (c) 2012 Scott Buchanan. All rights reserved.
//

#import "MTMainWindowController.h"
#import "MTDownloadTableView.h"
#import "MTProgramTableView.h"
#import "MTSubscriptionTableView.h"
#import "MTFormatPopUpButton.h"
#import "MTCheckBox.h"
#import "MTTiVo.h"
#import "MTHelpViewController.h"
#import <Quartz/Quartz.h>

@interface MTMainWindowController ()

@property (nonatomic, strong) NSSound *trashSound;
@end

@implementation MTMainWindowController

__DDLOGHERE__

@synthesize tiVoShowTable,subscriptionTable, downloadQueueTable;

-(id)initWithWindowNibName:(NSString *)windowNibName
{
	DDLogDetail(@"creating Main Window");
	self = [super initWithWindowNibName:windowNibName];
	if (self) {
		loadingTiVos = [NSMutableArray new];
        self.selectedTiVo = nil;
        _myTiVoManager = tiVoManager;
	}
	return self;
}

-(void)awakeFromNib
{
	DDLogDetail(@"MainWindow awakeFromNib");
	[self refreshFormatListPopup];
}

- (void)windowDidLoad
{
    [super windowDidLoad];
    
	DDLogDetail(@"MainWindow windowDidLoad");
    // Implement this method to handle any initialization after your window controller's window has been loaded from its nib file.
	[NSBundle loadNibNamed:@"MTMainWindowDrawer" owner:self];
	showDetailDrawer.parentWindow = self.window;
	
	NSNotificationCenter *defaultCenter = [NSNotificationCenter defaultCenter];
	[defaultCenter addObserver:self selector:@selector(refreshTiVoListPopup:) name:kMTNotificationTiVoListUpdated object:nil];
	[defaultCenter addObserver:self selector:@selector(buildColumnMenuForTables) name:kMTNotificationTiVoListUpdated object:nil];
	[defaultCenter addObserver:self selector:@selector(refreshTiVoListPopup:) name:kMTNotificationTiVoShowsUpdated object:nil];
    [defaultCenter addObserver:self selector:@selector(refreshFormatListPopup) name:kMTNotificationFormatListUpdated object:nil];
	
	//Spinner Progress Handling 
    [defaultCenter addObserver:self selector:@selector(manageLoadingIndicator:) name:kMTNotificationShowListUpdating object:nil];
    [defaultCenter addObserver:self selector:@selector(manageLoadingIndicator:) name:kMTNotificationShowListUpdated object:nil];
    [defaultCenter addObserver:self selector:@selector(networkChanged:) name:kMTNotificationNetworkChanged object:nil];
	
    [defaultCenter addObserver:self selector:@selector(columnOrderChanged:) name:NSTableViewColumnDidMoveNotification object:nil];
     [tiVoManager addObserver:self forKeyPath:@"selectedFormat" options:NSKeyValueObservingOptionInitial context:nil];
	[tiVoManager addObserver:self forKeyPath:@"downloadDirectory" options:NSKeyValueObservingOptionInitial context:nil];
	
	[tiVoManager determineCurrentProcessingState];

	[self buildColumnMenuForTables ];
	[pausedLabel setNextResponder:downloadQueueTable];  //Pass through mouse events to the downloadQueueTable.
	
	[tiVoShowTable setTarget: self];
	[tiVoShowTable setDoubleAction:@selector(doubleClickForDetails:)];
	
	[downloadQueueTable setTarget: self];
	[downloadQueueTable setDoubleAction:@selector(doubleClickForDetails:)];
	
	CALayer *viewLayer = [CALayer layer];
	struct CGColor * color = CGColorCreateGenericRGB(0.0, 0.0, 0.0, 0.4);
	[viewLayer setBackgroundColor:color]; //RGB plus Alpha Channel
	[self.cancelQuitView setWantsLayer:YES]; // view's backing store is using a Core Animation Layer
	CFRelease(color);
	[self.cancelQuitView setLayer:viewLayer];


}

-(void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
	if ([keyPath compare:@"downloadDirectory"] == NSOrderedSame) {
		DDLogDetail(@"changing downloadDirectory");
		downloadDirectory.stringValue = tiVoManager.downloadDirectory;
		NSString *dir = tiVoManager.downloadDirectory;
		if (!dir) dir = @"Directory not available!";
		downloadDirectory.stringValue = dir;
		downloadDirectory.toolTip = dir;
	}
}

-(void)networkChanged:(NSNotification *)notification
{
	DDLogMajor(@"MainWindow network Changed");
	[[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationTiVoListUpdated object:_selectedTiVo];
	[[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationTiVoShowsUpdated object:nil];
	
}

-(void)manageLoadingIndicator:(NSNotification *)notification
{
	if (!notification) { //Don't accept nil notifications
		return;  
	}
    MTTiVo * tivo = (MTTiVo *) notification.object;
	DDLogDetail(@"LoadingIndicator: %@ for %@",notification.name, tivo.tiVo.name);
    if ([notification.name  compare:kMTNotificationShowListUpdating] == NSOrderedSame) {
		if ([loadingTiVos indexOfObject:tivo] == NSNotFound) {
			[loadingTiVos addObject:tivo];
		}
	} else if ([notification.name compare:kMTNotificationShowListUpdated] == NSOrderedSame) {
		[loadingTiVos removeObject:tivo];
	}
    
	if (loadingTiVos.count) {
        [loadingProgramListIndicator startAnimation:nil];
        NSString *message =[NSString stringWithFormat: @"Updating %@",[[loadingTiVos valueForKeyPath:@"tiVo.name" ] componentsJoinedByString:@", "]];

        loadingProgramListLabel.stringValue = message;
    } else {
        [loadingProgramListIndicator stopAnimation:nil];
        loadingProgramListLabel.stringValue = @"";
    }
}

#pragma mark - Notification Responsders

-(void)refreshFormatListPopup {
	formatListPopUp.showHidden = NO;
	formatListPopUp.formatList =  tiVoManager.formatList;
	[formatListPopUp refreshMenu];
	[tiVoManager setValue:[formatListPopUp selectFormatNamed:tiVoManager.selectedFormat.name] forKey:@"selectedFormat"];

}

-(void)refreshTiVoListPopup:(NSNotification *)notification
{
	if (notification) {
		self.selectedTiVo = notification.object;
		if (!_selectedTiVo) {
			self.selectedTiVo = [[NSUserDefaults standardUserDefaults] objectForKey:kMTSelectedTiVo];
			if (!_selectedTiVo) {
				self.selectedTiVo = kMTAllTiVos;
			}
		}
	}
	[tiVoListPopUp removeAllItems];
	BOOL lastTivoWasManual = NO;
	for (MTTiVo *ts in tiVoManager.tiVoList) {
		NSString *tsTitle = [NSString stringWithFormat:@"%@ (%ld)",ts.tiVo.name,ts.shows.count];
		if (!ts.manualTiVo && lastTivoWasManual) { //Insert a separator
			NSMenuItem *menuItem = [NSMenuItem separatorItem];
			[tiVoListPopUp.menu addItem:menuItem];
		}
		lastTivoWasManual = ts.manualTiVo;
		[tiVoListPopUp addItemWithTitle:tsTitle];
        [[tiVoListPopUp lastItem] setRepresentedObject:ts];
        NSMenuItem *thisItem = [tiVoListPopUp lastItem];
        if (!ts.isReachable) {
            NSFont *thisFont = [NSFont systemFontOfSize:13];
            NSString *thisTitle = [NSString stringWithFormat:@"%@ offline",ts.tiVo.name];
            NSAttributedString *aTitle = [[NSAttributedString alloc] initWithString:thisTitle attributes:[NSDictionary dictionaryWithObjectsAndKeys:[NSColor redColor], NSForegroundColorAttributeName, thisFont, NSFontAttributeName, nil]];
            [thisItem setAttributedTitle:aTitle];

        }
		if ([ts.tiVo.name compare:self.selectedTiVo] == NSOrderedSame) {
			[tiVoListPopUp selectItem:thisItem];
		}
		
	}
    if (tiVoManager.tiVoList.count == 0) {
		[tiVoListPopUp setHidden:YES];
		tiVoListPopUpLabel.stringValue = @"Searching for TiVos...";
		tiVoListPopUpLabel.hidden = NO;
		[searchingTiVosIndicator startAnimation:nil];
        [self performSelector:@selector(popupHelpIfNotTiVosAfterInterval) withObject:Nil afterDelay:kMTTimeToHelpIfNoTiVoFound];
	} else if (tiVoManager.tiVoList.count == 1) {
        [searchingTiVosIndicator stopAnimation:nil];
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(popupHelpIfNotTiVosAfterInterval) object:nil];
		MTTiVo *ts = tiVoManager.tiVoList[0];
        [tiVoListPopUp selectItem:[tiVoListPopUp lastItem]];
		[tiVoListPopUpLabel setHidden:NO];
		[tiVoListPopUp setHidden:YES];
        tiVoListPopUpLabel.stringValue = [NSString stringWithFormat:@"TiVo: %@ (%ld)",ts.tiVo.name,ts.shows.count];
        if (!ts.isReachable) {
            NSFont *thisFont = [NSFont systemFontOfSize:13];
            NSString *thisTitle = [NSString stringWithFormat:@"TiVo: %@ offline",ts.tiVo.name];
            NSAttributedString *aTitle = [[NSAttributedString alloc] initWithString:thisTitle attributes:[NSDictionary dictionaryWithObjectsAndKeys:[NSColor redColor], NSForegroundColorAttributeName, thisFont, NSFontAttributeName, nil]];
            [tiVoListPopUpLabel setAttributedStringValue:aTitle];
			
        }
    } else if (tiVoManager.tiVoList.count > 1){
        [searchingTiVosIndicator stopAnimation:nil];
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(popupHelpIfNotTiVosAfterInterval) object:nil];
      [tiVoListPopUp addItemWithTitle:[NSString stringWithFormat:@"%@ (%d shows)",kMTAllTiVos,tiVoManager.totalShows]];
        if ([kMTAllTiVos compare:_selectedTiVo] == NSOrderedSame) {
            [tiVoListPopUp selectItem:[tiVoListPopUp lastItem]];
        }
        [tiVoListPopUp setHidden:NO];
        [tiVoListPopUpLabel setHidden:NO];
        tiVoListPopUpLabel.stringValue = @"Filter TiVo:";
    }
}

-(void)popupHelpIfNotTiVosAfterInterval
{
   	//Get help text for encoder
	NSString *helpFilePath = [[NSBundle mainBundle] pathForResource:@"FindTiVoHelpFile" ofType:@"rtf"];
	NSAttributedString *attrHelpText = [[NSAttributedString alloc] initWithRTF:[NSData dataWithContentsOfFile:helpFilePath] documentAttributes:NULL];
	//	NSString *helpText = [NSString stringWithContentsOfFile:helpFilePath encoding:NSUTF8StringEncoding error:nil];
    NSPopover *myPopover = [[NSPopover alloc] init];
    myPopover.delegate = self;
    myPopover.behavior = NSPopoverBehaviorTransient;
    MTHelpViewController *helpContoller = [[MTHelpViewController alloc] initWithNibName:@"MTHelpViewController" bundle:nil];
    myPopover.contentViewController = helpContoller;
    [helpContoller loadView];
    [helpContoller.displayMessage.textStorage setAttributedString:attrHelpText];
    //	[self.helpController.displayMessage insertText:helpText];
	[myPopover showRelativeToRect:searchingTiVosIndicator.bounds ofView:searchingTiVosIndicator preferredEdge:NSMaxXEdge];
 
}

#pragma mark - UI Actions

-(IBAction)selectFormat:(id)sender
{
    if (sender == formatListPopUp) {
        MTFormatPopUpButton *thisButton = (MTFormatPopUpButton *)sender;
        [tiVoManager setValue:[[thisButton selectedItem] representedObject] forKey:@"selectedFormat"];
        [[NSUserDefaults standardUserDefaults] setObject:tiVoManager.selectedFormat.name forKey:kMTSelectedFormat];
    } else {
        MTFormatPopUpButton *thisButton = (MTFormatPopUpButton *)sender;
        if ([thisButton.owner class] == [MTSubscription class]) {
            MTSubscription * subscription = (MTSubscription *) thisButton.owner;
            
            subscription.encodeFormat = [tiVoManager findFormat:[thisButton selectedItem].title];
       } else if ([thisButton.owner class] == [MTDownload class]) {
            MTDownload * download = (MTDownload *) thisButton.owner;
           if(download.isNew) {
                download.encodeFormat = [tiVoManager findFormat:[thisButton selectedItem].title];
            }
          [[NSNotificationCenter defaultCenter] postNotificationName: kMTNotificationDownloadStatusChanged object:nil];
       }
     }
}

#pragma mark - Menu Delegate

-(BOOL)validateMenuItem:(NSMenuItem *)menuItem
{
	BOOL returnValue = YES;
	if (menuItem == _showInFinderMenuItem || menuItem == _playVideoMenuItem) {
		BOOL itemsToProcess = [self selectionContainsCompletedShows];
		if (!itemsToProcess) {
			returnValue = NO;
		}
	}
	if ([menuItem.title rangeOfString:@"refresh" options:NSCaseInsensitiveSearch].location != NSNotFound) {
		if (tiVoManager.tiVoList.count > 1) {
			menuItem.title = @"Refresh this TiVo";
		} else {
			menuItem.title = @"Refresh TiVo";
		}
	}
	return returnValue;
}


-(void)menuWillOpen:(NSMenu *)menu
{
	menuCursorPosition = [self.window mouseLocationOutsideOfEventStream];
	NSTableView<MTTableViewProtocol> *workingTable = nil;
	SEL selector = NULL;
	if ([menu.title compare:@"ProgramTableMenu"] == NSOrderedSame) {
		workingTable = tiVoShowTable;
		selector = @selector(programMenuHandler:);
	}
	if ([menu.title compare:@"DownloadTableMenu"] == NSOrderedSame) {
		workingTable = downloadQueueTable;
		selector = @selector(downloadMenuHandler:);
	}
	if ([menu.title compare:@"SubscriptionTableMenu"] == NSOrderedSame) {
		workingTable = subscriptionTable;
		selector = @selector(subscriptionMenuHandler:);
	}
	if (workingTable) {
		NSPoint p = [workingTable convertPoint:menuCursorPosition fromView:nil];
		menuTableRow = [workingTable rowAtPoint:p];
		for (NSMenuItem *mi in [menu itemArray]) {
			[mi setAction:selector];
		}
		if (menuTableRow < 0) { //disable row functions  Row based functions have tag=1 or 2;
			for (NSMenuItem *mi in [menu itemArray]) {
				if (mi.tag == 1 || mi.tag == 2) {
					[mi setAction:NULL];
				}
			}
		} else {
			if (![[workingTable selectedRowIndexes] containsIndex:menuTableRow] ) {
				[workingTable selectRowIndexes:[NSIndexSet indexSetWithIndex:menuTableRow] byExtendingSelection:NO];
			}
			if (workingTable == downloadQueueTable) {
				MTDownload *thisDownload = downloadQueueTable.sortedDownloads[menuTableRow];
				//diable menu items that depend on having a completed show tag = 2
				if (!thisDownload.canPlayVideo) {
					for (NSMenuItem *mi in [menu itemArray]) {
						if (mi.tag == 2 ) {
							[mi setAction:NULL];
						}
					}
				}
			}
			if (workingTable == tiVoShowTable) {
				MTTiVoShow *thisShow = tiVoShowTable.sortedShows[menuTableRow];
				//diable menu items that depend on having a completed show tag = 2
				if (![tiVoManager.showsOnDisk objectForKey:thisShow.showKey]) {
					for (NSMenuItem *mi in [menu itemArray]) {
						if (mi.tag == 2 ) {
							[mi setAction:NULL];
						}
					}
				}
			}
		}
		if ([workingTable selectedRowIndexes].count == 0) { //No selection so disable group functions
			for (NSMenuItem *mi in [menu itemArray]) {
				if (mi.tag == 0) {
					[mi setAction:NULL];
				}
			}

		}

	}
}

- (void) openDrawer:(MTTiVoShow *) show {
	if (show) {		
		self.showForDetail = show;
		[showDetailDrawer open];
		//[self.drawerVariableFields setAutoresizingMask:self.drawerVariableFields.autoresizingMask |NSViewHeightSizable]; //workaround bug in IB?
	}
}

-(IBAction)programMenuHandler:(NSMenuItem *)menu
{
	if ([menu.title caseInsensitiveCompare:@"Download"] == NSOrderedSame) {
		[self downloadSelectedShows:menu];
	} else if ([menu.title rangeOfString:@"Refresh" options:NSCaseInsensitiveSearch].location != NSNotFound) {
		NSMutableSet * tiVos = [NSMutableSet set];
		for (MTTiVoShow * show in [tiVoShowTable.sortedShows objectsAtIndexes:[tiVoShowTable selectedRowIndexes]]) {
			[tiVos addObject: show.tiVo];
		}
		for (MTTiVo* tiVo in tiVos) {
			[tiVo  updateShows:nil];
		}
	} else if ([menu.title caseInsensitiveCompare:@"Subscribe to series"] == NSOrderedSame) {
		[self subscribe:menu];
	} else if ([menu.title caseInsensitiveCompare:@"Show Details"] == NSOrderedSame) {
		[self openDrawer:tiVoShowTable.sortedShows[menuTableRow]];
	} else if ([menu.title caseInsensitiveCompare:@"Play Video"] == NSOrderedSame) {
		MTTiVoShow *thisShow = tiVoShowTable.sortedShows[menuTableRow];
        //Eventually if more than 1 download present will open up choice alert (or extend menu with a right pull)
        //For now just play the first
        if ([tiVoManager.showsOnDisk objectForKey:thisShow.showKey]) {
                [thisShow playVideo:[tiVoManager.showsOnDisk objectForKey:thisShow.showKey][0]];
        }
    } else if ([menu.title caseInsensitiveCompare:@"Show in Finder"] == NSOrderedSame) {
		MTTiVoShow *thisShow = tiVoShowTable.sortedShows[menuTableRow];
        //Eventually if more than 1 download present will open up choice alert (or extend menu with a right pull)
        //For now just play the first
        if ([tiVoManager.showsOnDisk objectForKey:thisShow.showKey]) {
            [thisShow revealInFinder:[tiVoManager.showsOnDisk objectForKey:thisShow.showKey]];
        }
	}
}


-(IBAction)doubleClickForDetails:(id)input {
	if (input==tiVoShowTable) {
		NSInteger rowNumber = [tiVoShowTable clickedRow];
		if (rowNumber != -1) {
			[self openDrawer:tiVoShowTable.sortedShows[rowNumber]];
		}
	}else if (input==downloadQueueTable) {
		NSInteger rowNumber = [downloadQueueTable clickedRow];
		if (rowNumber != -1) {
			MTDownload * download = [[downloadQueueTable sortedDownloads] objectAtIndex:rowNumber];
			[self openDrawer:download.show];
			if (!download.show.protectedShow.boolValue) {
				[download revealInFinder];
				[download playVideo];
			}
		}
	}
}


-(IBAction)downloadMenuHandler:(NSMenuItem *)menu
{
	DDLogMajor(@"User specified to %@",menu.title);
	if ([menu.title caseInsensitiveCompare:@"Delete"] == NSOrderedSame) {
		[self removeFromDownloadQueue:menu];
	} else if ([menu.title caseInsensitiveCompare:@"Reschedule"] == NSOrderedSame) {
		NSIndexSet *selectedRows = [downloadQueueTable selectedRowIndexes];
		NSArray *itemsToRemove = [downloadQueueTable.sortedDownloads objectsAtIndexes:selectedRows];
		if ([tiVoManager.processingPaused boolValue]) {
			for (MTDownload *download in itemsToRemove) {
					[download prepareForDownload:YES];
			}
		} else {
			//Can't reschedule items that haven't loaded yet.
			NSMutableArray * realItemsToRemove = [NSMutableArray arrayWithArray:itemsToRemove];
			for (MTDownload *download in itemsToRemove) {
				if (download.show.protectedShow.boolValue) {
					//A proxy DL waiting for "real" show
					[download prepareForDownload:YES];
					[realItemsToRemove removeObject:download];
				}
			}
			[tiVoManager deleteFromDownloadQueue:realItemsToRemove];
			[tiVoManager addToDownloadQueue:realItemsToRemove beforeDownload:nil];
		}
	} else if ([menu.title caseInsensitiveCompare:@"Subscribe to series"] == NSOrderedSame) {
		NSArray * selectedDownloads = [downloadQueueTable.sortedDownloads objectsAtIndexes:downloadQueueTable.selectedRowIndexes];
		[tiVoManager.subscribedShows addSubscriptionsDL:selectedDownloads];
	} else if ([menu.title caseInsensitiveCompare:@"Show Details"] == NSOrderedSame) {
		MTDownload * download = downloadQueueTable.sortedDownloads[menuTableRow];
		[self openDrawer:download.show];
	} else if ([menu.title caseInsensitiveCompare:@"Play Video"] == NSOrderedSame) {
		[downloadQueueTable playVideo];
	} else if ([menu.title caseInsensitiveCompare:@"Show in Finder"] == NSOrderedSame) {
		[downloadQueueTable revealInFinder];
		
	}
	
}

-(BOOL) selectionContainsCompletedShows {
	BOOL itemsToProcess = [self.downloadQueueTable selectionContainsCompletedShows ] ;
	return itemsToProcess;
}

-(IBAction)revealInFinder: (id) sender
{
	[self.downloadQueueTable revealInFinder];
}

-(IBAction)playVideo: (id) sender
{
	[self.downloadQueueTable playVideo];
	
}

-(void) playTrashSound {
	self.trashSound = [[NSSound alloc] initWithContentsOfFile:@"/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/dock/drag to trash.aif" byReference:YES];
	if (_trashSound) {
		[self.trashSound play];
	}
}

#pragma mark - Subscription Buttons

-(IBAction)subscriptionMenuHandler:(NSMenuItem *)menu
{
	if ([menu.title caseInsensitiveCompare:@"Unsubscribe"] == NSOrderedSame) {
		[subscriptionTable unsubscribeSelectedItems:menu];
	} else if ([menu.title caseInsensitiveCompare:@"Re-Apply to Shows"] == NSOrderedSame) {
		[subscriptionTable reapplySelectedItems:menu];
	}
}

-(IBAction)subscribe:(id) sender {
	NSArray * selectedShows = [tiVoShowTable.sortedShows objectsAtIndexes:tiVoShowTable.selectedRowIndexes];
	[tiVoManager.subscribedShows addSubscriptions:selectedShows];
}

#pragma mark - Download Buttons

-(IBAction)downloadSelectedShows:(id)sender
{
	NSIndexSet *selectedRows = [tiVoShowTable selectedRowIndexes];
	NSArray *selectedShows = [tiVoShowTable.sortedShows objectsAtIndexes:selectedRows];
	[tiVoManager downloadShowsWithCurrentOptions:selectedShows beforeDownload:nil];
    
	[tiVoShowTable deselectAll:nil];
	[downloadQueueTable deselectAll:nil];
}

-(IBAction)dontQuit:(id)sender
{
	DDLogDetail(@"User canceled Quit after processing");
	tiVoManager.quitWhenCurrentDownloadsComplete = @(NO);
	tiVoManager.processingPaused = @(NO);
	[self.cancelQuitView setHidden:YES];
}



-(BOOL) confirmCancel:(NSString *) title {
    NSAlert *myAlert = [NSAlert alertWithMessageText:[NSString stringWithFormat:@"Do you want to cancel active download of '%@'?",title] defaultButton:@"No" alternateButton:@"Yes" otherButton:nil informativeTextWithFormat:@""];
    myAlert.alertStyle = NSCriticalAlertStyle;
    NSInteger result = [myAlert runModal];
    return (result == NSAlertAlternateReturn);
    
}

-(IBAction)removeFromDownloadQueue:(id)sender
{
	NSArray *itemsToRemove;
	if ([sender isKindOfClass:[NSArray class]]) {
		itemsToRemove = sender;
	}else {
		NSIndexSet *selectedRows = [downloadQueueTable selectedRowIndexes];
		itemsToRemove = [downloadQueueTable.sortedDownloads objectsAtIndexes:selectedRows];
	}
 	for (MTDownload * download in itemsToRemove) {
        if (download.isInProgress) {
            if( ![self confirmCancel:download.show.showTitle]) {
                //if any cancelled, cancel the whole group
                return;
            }
        }
    }
	[tiVoManager deleteFromDownloadQueue:itemsToRemove];
	if (itemsToRemove.count)[self playTrashSound];

 	[downloadQueueTable deselectAll:nil];
}

-(IBAction)getDownloadDirectory:(id)sender
{
	NSOpenPanel *myOpenPanel = [NSOpenPanel openPanel];
	[myOpenPanel setCanChooseDirectories:YES];
	[myOpenPanel setCanChooseFiles:NO];
	[myOpenPanel setAllowsMultipleSelection:NO];
    [myOpenPanel setCanCreateDirectories:YES];
    [myOpenPanel setTitle:@"Choose Directory for Download of Videos"];
    [myOpenPanel setPrompt:@"Choose"];
	NSInteger ret = [myOpenPanel runModal];
	if (ret == NSFileHandlingPanelOKButton) {
		tiVoManager.downloadDirectory = myOpenPanel.URL.path;
	}
}

#pragma mark - Download Options

-(IBAction)changeSkip:(id)sender
{
    MTCheckBox *checkbox = sender;
	if ([checkbox.owner isKindOfClass:[MTDownload class]]){
		MTDownload *download = (MTDownload *)(checkbox.owner);
        download.skipCommercials = ! download.skipCommercials;
		//		if (download.skipCommercials) {  //Need to make sure that simul encode is not checked
		//				download.simultaneousEncode = NO;
		//		}
		if (download.skipCommercials) {
			download.markCommercials = NO;
		}
        [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationDownloadRowChanged object:download];
    } else if ([checkbox.owner isKindOfClass:[MTSubscription class]]){
		
        MTSubscription *sub = (MTSubscription *)(checkbox.owner);
		sub.skipCommercials = [NSNumber numberWithBool: ! [sub.skipCommercials boolValue]];
		if ([sub.skipCommercials boolValue]) {
			sub.markCommercials = @NO;
		}
		//		if ([sub.skipCommercials boolValue]) { //Need to make sure simultaneous encode is off
		//			sub.simultaneousEncode = @(NO);
		//		}
		[[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationSubscriptionChanged object:sub];
                
    }
}

-(IBAction)changeMark:(id)sender
{
    MTCheckBox *checkbox = sender;
	if ([checkbox.owner isKindOfClass:[MTDownload class]]){
		MTDownload *download = (MTDownload *)(checkbox.owner);
        download.markCommercials = ! download.markCommercials;
		//		if (download.skipCommercials) {  //Need to make sure that simul encode is not checked
		//				download.simultaneousEncode = NO;
		//		}
		if (download.markCommercials) {
			download.skipCommercials = NO;
		}
        [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationDownloadRowChanged object:download];
    } else if ([checkbox.owner isKindOfClass:[MTSubscription class]]){
		
        MTSubscription *sub = (MTSubscription *)(checkbox.owner);
		sub.markCommercials = [NSNumber numberWithBool: ! [sub.markCommercials boolValue]];
		if ([sub.markCommercials boolValue]) {
			sub.skipCommercials = @NO;
		}
		[[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationSubscriptionChanged object:sub];
		//		if ([sub.skipCommercials boolValue]) { //Need to make sure simultaneous encode is off
		//			sub.simultaneousEncode = @(NO);
		//		}
                
    }
}

//-(IBAction)changeSimultaneous:(id)sender
//{
//    MTCheckBox *checkbox = sender;
//	if ([checkbox.owner isKindOfClass:[MTDownload class]]){
//		MTDownload *download = (MTDownload *)(checkbox.owner);
//        download.simultaneousEncode = ! download.simultaneousEncode;
//		if (download.simultaneousEncode) {  //Need to make sure that simul encode is not checked
//				download.skipCommercials = NO;
//		}
//        [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationDownloadRowChanged object:download];
//    } else if ([checkbox.owner isKindOfClass:[MTSubscription class]]){
//		
//        MTSubscription *sub = (MTSubscription *)(checkbox.owner);
//		sub.simultaneousEncode = [NSNumber numberWithBool: ! [sub.simultaneousEncode boolValue]];
//		if ([sub.simultaneousEncode boolValue]) { //Need to make sure simultaneous encode is off
//			sub.skipCommercials = @(NO);
//		}
//        //        
//    }
//}

-(IBAction)changeiTunes:(id)sender
{
    MTCheckBox *checkbox = sender;
	if ([checkbox.owner isKindOfClass:[MTDownload class]]){
        //updating an individual show in download queue
            ((MTDownload *)checkbox.owner).addToiTunesWhenEncoded = !((MTDownload *)checkbox.owner).addToiTunesWhenEncoded;

    } else if ([checkbox.owner isKindOfClass:[MTSubscription class]]){
		MTSubscription *sub = (MTSubscription *)(checkbox.owner);
		sub.addToiTunes = [NSNumber numberWithBool: ! sub.shouldAddToiTunes];
                
    }
}
#ifndef deleteXML
-(IBAction)changeXML:(id)sender
{
    MTCheckBox *checkbox = sender;
	if ([checkbox.owner isKindOfClass:[MTDownload class]]){
        //updating an individual show in download queue
		MTDownload * download = (MTDownload *)checkbox.owner;
		NSNumber *newVal = [NSNumber numberWithBool: ! download.genXMLMetaData.boolValue ];
		download.genXMLMetaData = newVal;
		
    } else if ([checkbox.owner isKindOfClass:[MTSubscription class]]){
		MTSubscription *sub = (MTSubscription *)(checkbox.owner);
		NSNumber *newVal = [NSNumber numberWithBool: ! sub.genXMLMetaData.boolValue ];
		sub.genXMLMetaData = newVal;
                
    }
}

-(IBAction)changeMetadata:(id)sender
{
    MTCheckBox *checkbox = sender;
	if ([checkbox.owner isKindOfClass:[MTDownload class]]){
        //updating an individual show in download queue
		MTDownload * download = (MTDownload *)checkbox.owner;
		NSNumber *newVal = [NSNumber numberWithBool: ! download.includeAPMMetaData.boolValue ];
		download.includeAPMMetaData = newVal;
		
    } else if ([checkbox.owner isKindOfClass:[MTSubscription class]]){
		MTSubscription *sub = (MTSubscription *)(checkbox.owner);
		NSNumber *newVal = [NSNumber numberWithBool: ! sub.includeAPMMetaData.boolValue ];
		sub.includeAPMMetaData = newVal;
                
    }
}


#endif

-(IBAction)changepyTiVo:(id)sender
{
    MTCheckBox *checkbox = sender;
	if ([checkbox.owner isKindOfClass:[MTDownload class]]){
        //updating an individual show in download queue
		MTDownload * download = (MTDownload *)checkbox.owner;
		NSNumber *newVal = [NSNumber numberWithBool: ! download.genTextMetaData.boolValue ];
		download.genTextMetaData = newVal;
		
    } else if ([checkbox.owner isKindOfClass:[MTSubscription class]]){
		MTSubscription *sub = (MTSubscription *)(checkbox.owner);
		NSNumber *newVal = [NSNumber numberWithBool: ! sub.genTextMetaData.boolValue ];
		sub.genTextMetaData = newVal;
	}
}

-(IBAction)changeSubtitle:(id)sender
{
    MTCheckBox *checkbox = sender;
	if ([checkbox.owner isKindOfClass:[MTDownload class]]){
        //updating an individual show in download queue
		MTDownload * download = (MTDownload *)checkbox.owner;
		NSNumber *newVal = [NSNumber numberWithBool: ! download.exportSubtitles.boolValue ];
		download.exportSubtitles = newVal;
		
    } else if ([checkbox.owner isKindOfClass:[MTSubscription class]]){ 
		MTSubscription *sub = (MTSubscription *)(checkbox.owner);
		NSNumber *newVal = [NSNumber numberWithBool: ! sub.exportSubtitles.boolValue ];
		sub.exportSubtitles = newVal;
        		
    }
}


#pragma mark - Customize Columns

-(void) buildColumnMenuForTables{
	[self buildColumnMenuForTable: downloadQueueTable];
	[self buildColumnMenuForTable: tiVoShowTable];
	[self buildColumnMenuForTable: subscriptionTable ];
}

-(void) columnOrderChanged: (NSNotification *) notification {
	[self buildColumnMenuForTables];
}

-(void) buildColumnMenuForTable:(NSTableView *) table {
	NSMenu *tableHeaderContextMenu = [[NSMenu alloc] initWithTitle:@""];
	[[table headerView] setMenu:tableHeaderContextMenu];
	
	for (NSTableColumn *column in [table tableColumns]) {
        if ([column.identifier compare:@"TiVo"] != NSOrderedSame || [[NSUserDefaults standardUserDefaults] boolForKey:kMTHasMultipleTivos]) {
            NSString *title = [[column headerCell] title];
            NSMenuItem *item = [tableHeaderContextMenu addItemWithTitle:title action:@selector(contextMenuSelected:) keyEquivalent:@""];
            [item setTarget:self];
            [item setRepresentedObject:@{@"Column" : column, @"Table" : table}];
            [item setState:column.isHidden?NSOffState: NSOnState];
        }
	}
}


- (void)contextMenuSelected:(id)sender {
	NSMenuItem * menuItem = (NSMenuItem *) sender;
    NSTableColumn *column = [menuItem representedObject][@"Column"];
	BOOL wasOn = ([menuItem state] == NSOnState);
	[column setHidden:wasOn];
	if(wasOn) {
		[menuItem setState: NSOffState ];
	} else {
		[menuItem setState: NSOnState];
	}
}

#pragma mark - Memory Management

-(void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}


#pragma mark - Text Editing Delegate

-(BOOL)control:(NSControl *)control textShouldEndEditing:(NSText *)fieldEditor
{
    if (control == downloadDirectory) {
        tiVoManager.downloadDirectory = control.stringValue;
    }
	return YES;
}

#pragma mark - Split View Delegate
- (CGFloat)splitView:(NSSplitView *)splitView constrainMinCoordinate:(CGFloat)proposedMin ofSubviewAt:(NSInteger)dividerIndex {
	//all three tables have same minimum
	return proposedMin + 120;
}

- (CGFloat)splitView:(NSSplitView *)splitView constrainMaxCoordinate:(CGFloat)proposedMaximumPosition ofSubviewAt:(NSInteger)dividerIndex;
{
    return proposedMaximumPosition - 120;
}
@end
