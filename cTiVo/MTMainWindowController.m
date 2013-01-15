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
#import "MTPopUpButton.h"
#import "MTCheckBox.h"
#import "MTTiVo.h"

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
	subDirectoriesButton.state = [[NSUserDefaults standardUserDefaults ] boolForKey:kMTMakeSubDirs] ? NSOnState : NSOffState;
	NSNotificationCenter *defaultCenter = [NSNotificationCenter defaultCenter];
	[defaultCenter addObserver:self selector:@selector(refreshTiVoListPopup:) name:kMTNotificationTiVoListUpdated object:nil];
    [defaultCenter addObserver:self selector:@selector(refreshFormatListPopup) name:kMTNotificationFormatListUpdated object:nil];
    [defaultCenter addObserver:self selector:@selector(reloadProgramData) name:kMTNotificationTiVoShowsUpdated object:nil];
    [defaultCenter addObserver:downloadQueueTable selector:@selector(reloadData) name:kMTNotificationDownloadQueueUpdated object:nil];
	[defaultCenter addObserver:self selector:@selector(refreshAddToQueueButton:) name:kMTNotificationDownloadQueueUpdated object:nil];
    [defaultCenter addObserver:downloadQueueTable selector:@selector(updateProgress) name:kMTNotificationProgressUpdated object:nil];
	
	//Spinner Progress Handling 
    [defaultCenter addObserver:self selector:@selector(manageLoadingIndicator:) name:kMTNotificationShowListUpdating object:nil];
    [defaultCenter addObserver:self selector:@selector(manageLoadingIndicator:) name:kMTNotificationShowListUpdated object:nil];
    [defaultCenter addObserver:self selector:@selector(networkChanged:) name:kMTNotificationNetworkChanged object:nil];
	
    [defaultCenter addObserver:self selector:@selector(tableSelectionChanged:) name:NSTableViewSelectionDidChangeNotification object:nil];
    [tiVoManager addObserver:self forKeyPath:@"selectedFormat" options:NSKeyValueObservingOptionInitial context:nil];
	[tiVoManager addObserver:self forKeyPath:@"downloadDirectory" options:NSKeyValueObservingOptionInitial context:nil];


}

-(void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if ([keyPath compare:@"selectedFormat"] == NSOrderedSame) {
        BOOL caniTune = [tiVoManager.selectedFormat.iTunes boolValue];
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

        BOOL canSimulEncode = ![tiVoManager.selectedFormat.mustDownloadFirst boolValue];
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
    } else if ([keyPath compare:@"downloadDirectory"] == NSOrderedSame) {
		downloadDirectory.stringValue = tiVoManager.downloadDirectory;
		NSString *dir = tiVoManager.downloadDirectory;
		if (!dir) dir = @"Directory not available!";
		downloadDirectory.stringValue = dir;
		downloadDirectory.toolTip = dir;
	}
}

-(void)networkChanged:(NSNotification *)notification
{
	[[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationTiVoListUpdated object:_selectedTiVo];
	[[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationTiVoShowsUpdated object:nil];
	
}

-(void)manageLoadingIndicator:(NSNotification *)notification
{
	if (!notification) { //Don't accept nil notifications
		return;  
	}
    MTTiVo * tivo = (MTTiVo *) notification.object;
    if ([notification.name  compare:kMTNotificationShowListUpdating] == NSOrderedSame) {
		[loadingTiVos addObject:tivo];
	} else if ([notification.name compare:kMTNotificationShowListUpdated] == NSOrderedSame) {
		[loadingTiVos removeObject:tivo];
	}
    
	if (loadingTiVos.count) {
        [loadingProgramListIndicator startAnimation:nil];
        //note: this relies on [MTTivo description]
        NSString *message =[NSString stringWithFormat: @"Updating %@",[loadingTiVos componentsJoinedByString:@", "]];

        loadingProgramListLabel.stringValue = message;
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
	[self refreshFormatListPopup:formatListPopUp selected:tiVoManager.selectedFormat.name];
}

-(void)refreshFormatListPopup:(NSPopUpButton *)popUp selected:(NSString *)selectedName
{
	[popUp removeAllItems];
    NSPredicate *hiddenPredicate = [NSPredicate predicateWithFormat:@"isHidden == %@",[NSNumber numberWithBool:NO]];
    NSSortDescriptor *user = [NSSortDescriptor sortDescriptorWithKey:@"isFactoryFormat" ascending:YES];
    NSSortDescriptor *title = [NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES selector:@selector(caseInsensitiveCompare:)];
    NSArray *sortDescriptors = [NSArray arrayWithObjects:user,title, nil];
    
    NSArray *sortedFormatList = [[tiVoManager.formatList filteredArrayUsingPredicate:hiddenPredicate] sortedArrayUsingDescriptors:sortDescriptors];
//    NSArray *sortedFormatList = [tiVoManager.formatList sortedArrayUsingDescriptors:sortDescriptors];
    BOOL isFactory = YES;
	for (MTFormat *fl in sortedFormatList) {
        if ([popUp numberOfItems] == 0 && ![fl.isFactoryFormat boolValue]) {
            [popUp addItemWithTitle:@"    User Formats"];
            [[popUp lastItem] setEnabled:NO];
            [[popUp lastItem] setTarget:nil];

        }
        if ([fl.isFactoryFormat boolValue] && isFactory) { //This is a changeover from user input to factory input (if any
            NSMenuItem *separator = [NSMenuItem separatorItem];
            [[popUp menu] addItem:separator];
            [popUp addItemWithTitle:@"    Built In Formats"];
            [[popUp lastItem] setEnabled:NO];
            [[popUp lastItem] setTarget:nil];
            isFactory = NO;
        }
		[popUp addItemWithTitle:fl.name];
		if (![fl.isFactoryFormat boolValue]) { //Change the color for user formats
			NSFont *thisFont = popUp.font;
			NSAttributedString *attTitle = [[[NSAttributedString alloc] initWithString:fl.name attributes:@{NSFontAttributeName : thisFont, NSForegroundColorAttributeName : [NSColor colorWithDeviceRed:0.0 green:0.0 blue:0.7 alpha:1.0]}] autorelease];
			[popUp lastItem].attributedTitle = attTitle;
		}
        NSMenuItem *thisItem = [popUp lastItem];
        [thisItem setRepresentedObject:fl];
        thisItem.toolTip = [NSString stringWithFormat:@"%@: %@", fl.name, fl.formatDescription];
		if (selectedName && [fl.name compare:selectedName] == NSOrderedSame) {
			[formatListPopUp selectItem:thisItem];
		}
		
	}
    
}
- (void) refreshAddToQueueButton: (NSNotification *) notification {
if ([tiVoManager.downloadQueue count] > 0) {
    addToQueueButton.title =@"Add to Queue";
    } else {
     addToQueueButton.title =@"Download";
   }
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
	for (MTTiVo *ts in tiVoManager.tiVoList) {
		[tiVoListPopUp addItemWithTitle:ts.tiVo.name];
        [[tiVoListPopUp lastItem] setRepresentedObject:ts];
        NSMenuItem *thisItem = [tiVoListPopUp lastItem];
        if (!ts.isReachable) {
            NSFont *thisFont = [NSFont systemFontOfSize:13];
            NSString *thisTitle = [NSString stringWithFormat:@"%@ offline",ts.tiVo.name];
            NSAttributedString *aTitle = [[[NSAttributedString alloc] initWithString:thisTitle attributes:[NSDictionary dictionaryWithObjectsAndKeys:[NSColor redColor], NSForegroundColorAttributeName, thisFont, NSFontAttributeName, nil]] autorelease];
            [thisItem setAttributedTitle:aTitle];

        }
		if ([ts.tiVo.name compare:_selectedTiVo] == NSOrderedSame) {
			[tiVoListPopUp selectItem:thisItem];
		}
		
	}
    if (tiVoManager.tiVoList.count == 1) {
		MTTiVo *ts = tiVoManager.tiVoList[0];
        [tiVoListPopUp selectItem:[tiVoListPopUp lastItem]];
        [tiVoListPopUp setHidden:YES];
        tiVoListPopUpLabel.stringValue = [NSString stringWithFormat:@"TiVo: %@",ts.tiVo.name];
        if (!ts.isReachable) {
            NSFont *thisFont = [NSFont systemFontOfSize:13];
            NSString *thisTitle = [NSString stringWithFormat:@"TiVo: %@ offline",ts.tiVo.name];
            NSAttributedString *aTitle = [[[NSAttributedString alloc] initWithString:thisTitle attributes:[NSDictionary dictionaryWithObjectsAndKeys:[NSColor redColor], NSForegroundColorAttributeName, thisFont, NSFontAttributeName, nil]] autorelease];
            [tiVoListPopUpLabel setAttributedStringValue:aTitle];
			
        }
    } else {
        [tiVoListPopUp addItemWithTitle:kMTAllTiVos];
        if ([kMTAllTiVos compare:_selectedTiVo] == NSOrderedSame) {
            [tiVoListPopUp selectItem:[tiVoListPopUp lastItem]];
        }
        [tiVoListPopUp setHidden:NO];
        [tiVoListPopUpLabel setHidden:NO];
        tiVoListPopUpLabel.stringValue = @"Filter TiVo:";
    }
}

#pragma mark - UI Actions

-(IBAction)selectFormat:(id)sender
{
    if (sender == formatListPopUp) {
        NSPopUpButton *thisButton = (NSPopUpButton *)sender;
        tiVoManager.selectedFormat = [[thisButton selectedItem] representedObject];
        [[NSUserDefaults standardUserDefaults] setObject:tiVoManager.selectedFormat.name forKey:kMTSelectedFormat];
    } else {
        MTPopUpButton *thisButton = (MTPopUpButton *)sender;
        if ([thisButton.owner class] == [MTSubscription class]) {
            MTSubscription * subscription = (MTSubscription *) thisButton.owner;
            
            subscription.encodeFormat = [tiVoManager findFormat:[thisButton selectedItem].title];
            [tiVoManager.subscribedShows saveSubscriptions];
       } else if ([thisButton.owner class] == [MTTiVoShow class]) {
            MTTiVoShow * show = (MTTiVoShow *) thisButton.owner;
           if([show.downloadStatus intValue] == kMTStatusNew) {
                show.encodeFormat = [tiVoManager findFormat:[thisButton selectedItem].title];
            }
          [[NSNotificationCenter defaultCenter] postNotificationName: kMTNotificationDownloadStatusChanged object:nil];
       }
     }
}

-(IBAction)changeSubDirectories:(id)sender
{
    MTCheckBox *checkbox = sender;
    if (sender == subDirectoriesButton) {
        [[NSUserDefaults standardUserDefaults] setBool:(checkbox.state == NSOnState) forKey:kMTMakeSubDirs];
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
    [myOpenPanel setCanCreateDirectories:YES];
    [myOpenPanel setTitle:@"Choose Directory for Download of Videos"];
    [myOpenPanel setPrompt:@"Choose"];
	NSInteger ret = [myOpenPanel runModal];
	if (ret == NSFileHandlingPanelOKButton) {
		tiVoManager.downloadDirectory = myOpenPanel.URL.path;
	}
}

-(IBAction)changeSimultaneous:(id)sender
{
    MTCheckBox *checkbox = sender;
    if (sender == simultaneousEncodeButton) {
        [[NSUserDefaults standardUserDefaults] setBool:(checkbox.state == NSOnState) forKey:kMTSimultaneousEncode];
		tiVoManager.simultaneousEncode = checkbox.state == NSOnState;
    
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
        [[NSUserDefaults standardUserDefaults] setBool:(checkbox.state == NSOnState) forKey:kMTiTunesEncode];
		tiVoManager.addToItunes = checkbox.state == NSOnState;

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
    }
	return YES;
}



@end
