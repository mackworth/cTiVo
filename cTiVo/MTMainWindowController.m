//
//  MTMainWindowController.m
//  cTiVo
//
//  Created by Scott Buchanan on 12/13/12.
//  Copyright (c) 2012 Scott Buchanan. All rights reserved.
//

#import "MTMainWindowController.h"
#import "MTDownloadList.h"
#import "MTProgramList.h"
#import "MTSubscriptionTableView.h"
#import "MTPopUpButton.h"
#import "MTCheckBox.h"

@interface MTMainWindowController ()

@end

@implementation MTMainWindowController

@synthesize tiVoShowTable,subscriptionTable, downloadQueueTable;

-(id)initWithWindowNibName:(NSString *)windowNibName
{
	self = [super initWithWindowNibName:windowNibName];
	if (self) {
		loadingTiVos = [NSMutableArray new];
        self.selectedTiVo = nil;
	}
	return self;
}

-(void)awakeFromNib
{
	[self refreshFormatListPopup];
}

- (void)windowDidLoad
{
    [super windowDidLoad];
    
    // Implement this method to handle any initialization after your window controller's window has been loaded from its nib file.
	[tiVoListPopUp removeAllItems];
	[tiVoListPopUp addItemWithTitle:@"Searching for TiVos..."];
    downloadDirectory.stringValue = tiVoManager.downloadDirectory;
	NSNotificationCenter *defaultCenter = [NSNotificationCenter defaultCenter];
	[defaultCenter addObserver:self selector:@selector(refreshTiVoListPopup:) name:kMTNotificationTiVoListUpdated object:nil];
    [defaultCenter addObserver:self selector:@selector(refreshFormatListPopup) name:kMTNotificationFormatListUpdated object:nil];
    [defaultCenter addObserver:self selector:@selector(reloadProgramData) name:kMTNotificationTiVoShowsUpdated object:nil];
    [defaultCenter addObserver:downloadQueueTable selector:@selector(reloadData) name:kMTNotificationDownloadQueueUpdated object:nil];
    [defaultCenter addObserver:downloadQueueTable selector:@selector(updateProgress) name:kMTNotificationProgressUpdated object:nil];
	
	//Spinner Progress Handling 
    [defaultCenter addObserver:self selector:@selector(manageLoadingIndicator:) name:kMTNotificationShowListUpdating object:nil];
    [defaultCenter addObserver:self selector:@selector(manageLoadingIndicator:) name:kMTNotificationShowListUpdated object:nil];
	
    [defaultCenter addObserver:self selector:@selector(tableSelectionChanged:) name:NSTableViewSelectionDidChangeNotification object:nil];
    [tiVoManager addObserver:self forKeyPath:@"selectedFormat" options:NSKeyValueObservingOptionInitial context:nil];
    

}

-(void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if ([keyPath compare:@"selectedFormat"] == NSOrderedSame) {
        BOOL caniTune = [[tiVoManager.selectedFormat objectForKey:@"iTunes"] boolValue];
        [addToiTunesButton setEnabled:caniTune];
        if (caniTune) {
            BOOL wantsiTunes = [[NSUserDefaults standardUserDefaults] boolForKey:kMTiTunesEncode];
            if (wantsiTunes) {
                [addToiTunesButton setState:NSOnState];
				tiVoManager.addToItunes = YES;
            } else {
                [addToiTunesButton setState:NSOffState];
				tiVoManager.addToItunes = NO;
            }
       } else {
           [addToiTunesButton setState:NSOffState];
		   tiVoManager.addToItunes = YES;
        }

        BOOL canSimulEncode = ![[tiVoManager.selectedFormat objectForKey:@"mustDownloadFirst"] boolValue];
        [simultaneousEncodeButton setEnabled:canSimulEncode];
        if (canSimulEncode) {
            BOOL wantsSimul = [[NSUserDefaults standardUserDefaults] boolForKey:kMTSimultaneousEncode];
            if (wantsSimul) {
                [simultaneousEncodeButton setState:NSOnState];
				tiVoManager.simultaneousEncode = YES;
            } else {
                [simultaneousEncodeButton setState:NSOffState];
				tiVoManager.simultaneousEncode = NO;
            }
        } else {
            [simultaneousEncodeButton setState:NSOffState];
			tiVoManager.simultaneousEncode = NO;
        }
    }
}

-(void)manageLoadingIndicator:(NSNotification *)notification
{
	if (!notification) { //Don't accept nil notifications
		return;  
	}
	if ([notification.name  compare:kMTNotificationShowListUpdating] == NSOrderedSame) {
		[loadingTiVos addObject:notification.object];
	} else if ([notification.name compare:kMTNotificationShowListUpdated] == NSOrderedSame) {
		[loadingTiVos removeObject:notification.object];
	}
if (loadingTiVos.count) {
	[loadingProgramListIndicator startAnimation:nil];
	NSMutableString *message = [NSMutableString stringWithString:@"Updating "];
	for (MTTiVo *tiVo in loadingTiVos) {
		[message appendString:[NSString stringWithFormat:@" %@,",tiVo.tiVo.name]];
	}
	
	loadingProgramListLabel.stringValue = [message substringToIndex:message.length-1];

} else {
	[loadingProgramListIndicator stopAnimation:nil];
	loadingProgramListLabel.stringValue = @"";
}
}

-(void)reloadProgramData
{
	[tiVoShowTable reloadData];
}

#pragma mark - Notification Responsders

-(void)refreshFormatListPopup
{
	[formatListPopUp removeAllItems];
	for (NSDictionary *fl in tiVoManager.formatList) {
		[formatListPopUp addItemWithTitle:[fl objectForKey:@"name"]];
        [[formatListPopUp lastItem] setRepresentedObject:fl];
		if (tiVoManager.selectedFormat && [[fl objectForKey:@"name"] compare:[tiVoManager.selectedFormat objectForKey:@"name"]] == NSOrderedSame) {
			[formatListPopUp selectItem:[formatListPopUp lastItem]];
		}
		
	}
}

-(void)refreshTiVoListPopup:(NSNotification *)notification
{
	self.selectedTiVo = notification.object;
    if (!_selectedTiVo) {
        self.selectedTiVo = [[NSUserDefaults standardUserDefaults] objectForKey:kMTSelectedTiVo];
        if (!_selectedTiVo) {
            self.selectedTiVo = kMTAllTiVos;
        }
    }
	[tiVoListPopUp removeAllItems];
	for (MTTiVo *ts in tiVoManager.tiVoList) {
		[tiVoListPopUp addItemWithTitle:ts.tiVo.name];
        [[tiVoListPopUp lastItem] setRepresentedObject:ts];
		if ([ts.tiVo.name compare:_selectedTiVo] == NSOrderedSame) {
			[tiVoListPopUp selectItem:[tiVoListPopUp lastItem]];
		}
		
	}
    if (tiVoManager.tiVoList.count == 1) {
        [tiVoListPopUp selectItem:[tiVoListPopUp lastItem]];
    } else {
        [tiVoListPopUp addItemWithTitle:kMTAllTiVos];
        if ([kMTAllTiVos compare:_selectedTiVo] == NSOrderedSame) {
            [tiVoListPopUp selectItem:[tiVoListPopUp lastItem]];
        }
    }
}

#pragma mark - UI Actions

-(IBAction)selectFormat:(id)sender
{
    if (sender == formatListPopUp) {
        NSPopUpButton *thisButton = (NSPopUpButton *)sender;
        tiVoManager.selectedFormat = [[thisButton selectedItem] representedObject];
        [[NSUserDefaults standardUserDefaults] setObject:[tiVoManager.selectedFormat objectForKey:@"name"] forKey:kMTSelectedFormat];
    } else {
        MTPopUpButton *thisButton = (MTPopUpButton *)sender;
        if ([thisButton.owner class] == [MTSubscription class]) {
            MTSubscription * subscription = (MTSubscription *) thisButton.owner;
            
            subscription.encodeFormat = [tiVoManager findFormat:[thisButton selectedItem].title];
               [tiVoManager.subscribedShows saveSubscriptions];
        }
    }
}

#pragma mark - Subscription Management

-(IBAction)subscribe:(id) sender {
	BOOL anySubscribed = NO;
    for (int i = 0; i < tiVoShowTable.sortedShows.count; i++) {
        if ([tiVoShowTable isRowSelected:i]) {
			anySubscribed = YES;
			MTTiVoShow *thisShow = [tiVoShowTable.sortedShows objectAtIndex:i];
			[tiVoManager.subscribedShows addSubscription:thisShow];
		}
	}
	if (anySubscribed) {
		[tiVoManager.subscribedShows checkSubscriptionsAll];
		[subscriptionTable reloadData];
	}
}


-(IBAction)downloadSelectedShows:(id)sender
{
	NSIndexSet *selectedRows = [tiVoShowTable selectedRowIndexes];
	NSArray *selectedShows = [tiVoShowTable.sortedShows objectsAtIndexes:selectedRows];
    for (MTTiVoShow * show in selectedShows) {
        [tiVoManager downloadthisShowWithCurrentOptions:show];
    }
	[tiVoShowTable deselectAll:nil];
	[downloadQueueTable deselectAll:nil];
}

-(BOOL) confirmCancel:(NSString *) title {
    NSAlert *myAlert = [NSAlert alertWithMessageText:[NSString stringWithFormat:@"Do you want to cancel active download of '%@'?",title] defaultButton:@"No" alternateButton:@"Yes" otherButton:nil informativeTextWithFormat:@""];
    myAlert.alertStyle = NSCriticalAlertStyle;
    NSInteger result = [myAlert runModal];
    return (result == NSAlertAlternateReturn);
    
}

-(IBAction)removeFromDownloadQueue:(id)sender
{
	NSIndexSet *selectedRows = [downloadQueueTable selectedRowIndexes];
	NSArray *itemsToRemove = [downloadQueueTable.sortedShows objectsAtIndexes:selectedRows];
 	for (MTTiVoShow * show in itemsToRemove) {
        if (show.isInProgress) {
            if( ![self confirmCancel:show.showTitle]) {
                //if any cancelled, cancel the whole group
                return;
            }
        }
    }
    for (MTTiVoShow * show in itemsToRemove) {
        [tiVoManager deleteProgramFromDownloadQueue:show];
	}
 	[downloadQueueTable deselectAll:nil];
}

-(IBAction)getDownloadDirectory:(id)sender
{
	NSOpenPanel *myOpenPanel = [NSOpenPanel openPanel];
	[myOpenPanel setCanChooseDirectories:YES];
	[myOpenPanel setCanChooseFiles:NO];
	[myOpenPanel setAllowsMultipleSelection:NO];
	NSInteger ret = [myOpenPanel runModal];
	if (ret == NSFileHandlingPanelOKButton) {
		NSString *dir = [myOpenPanel.URL.absoluteString substringFromIndex:16];
		downloadDirectory.stringValue = dir;
        tiVoManager.downloadDirectory = dir;
		[[NSUserDefaults standardUserDefaults] setObject:dir forKey:kMTDownloadDirectory];
        downloadDirectory.toolTip = dir;
	}
}

-(IBAction)changeSimultaneous:(id)sender
{
    MTCheckBox *checkbox = sender;
    if (sender == simultaneousEncodeButton) {
        [[NSUserDefaults standardUserDefaults] setBool:checkbox.state forKey:kMTSimultaneousEncode];
    
    } else if ([checkbox.owner isKindOfClass:[MTTiVoShow class]]){
        ((MTTiVoShow *)checkbox.owner).simultaneousEncode = ! ((MTTiVoShow *)checkbox.owner).simultaneousEncode;

    } else if ([checkbox.owner isKindOfClass:[MTSubscription class]]){
		
        MTSubscription *sub = (MTSubscription *)(checkbox.owner);
		sub.simultaneousEncode = [NSNumber numberWithBool: ! [sub.simultaneousEncode boolValue]];
        [tiVoManager.subscribedShows saveSubscriptions];
        
   }
}

-(IBAction)changeiTunes:(id)sender
{     
    MTCheckBox *checkbox = sender;
    if (sender == addToiTunesButton) {
        [[NSUserDefaults standardUserDefaults] setBool:checkbox.state forKey:kMTiTunesEncode];

    } else if ([checkbox.owner isKindOfClass:[MTTiVoShow class]]){
        //updating an individual show in download queue
            ((MTTiVoShow *)checkbox.owner).addToiTunesWhenEncoded = !((MTTiVoShow *)checkbox.owner).addToiTunesWhenEncoded;

    } else if ([checkbox.owner isKindOfClass:[MTSubscription class]]){
		MTSubscription *sub = (MTSubscription *)(checkbox.owner);
		sub.addToiTunes = [NSNumber numberWithBool:!sub.shouldAddToiTunes];
        [tiVoManager.subscribedShows saveSubscriptions];
        
    }
}

#pragma mark - Table View Notification Handling

-(void)tableSelectionChanged:(NSNotification *)notification
{
    [addToQueueButton setEnabled:NO];
    [removeFromQueueButton setEnabled:NO];
	[subscribeButton setEnabled:NO];
    if ([downloadQueueTable numberOfSelectedRows]) {
        [removeFromQueueButton setEnabled:YES];
    }
    if ([tiVoShowTable numberOfSelectedRows]) {
        [addToQueueButton setEnabled:YES];
        [subscribeButton setEnabled:YES];
    }
}

#pragma mark - Memory Management

-(void)dealloc
{
	[loadingTiVos release];
    self.selectedTiVo = nil;
    [[NSNotificationCenter defaultCenter] removeObserver:self];
	[super dealloc];
}


#pragma mark - Text Editing Delegate

-(BOOL)control:(NSControl *)control textShouldEndEditing:(NSText *)fieldEditor
{
    if (control == downloadDirectory) {
        tiVoManager.downloadDirectory = control.stringValue;
		[[NSUserDefaults standardUserDefaults] setObject:control.stringValue forKey:kMTDownloadDirectory];
    }
	return YES;
}



@end
