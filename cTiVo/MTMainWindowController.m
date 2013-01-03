//
//  MTMainWindowController.m
//  cTiVo
//
//  Created by Scott Buchanan on 12/13/12.
//  Copyright (c) 2012 Scott Buchanan. All rights reserved.
//

#import "MTMainWindowController.h"
#import "MTCheckBox.h"

@interface MTMainWindowController ()

@end

@implementation MTMainWindowController

@synthesize tiVoShowTable,subscriptionTable, downloadQueueTable;

-(id)initWithWindowNibName:(NSString *)windowNibName withNetworkTivos:(MTNetworkTivos *)myTiVos
{
	self = [super initWithWindowNibName:windowNibName];
	if (self) {
		self.myTiVos = myTiVos;
		_selectedFormat = _myTiVos.selectedFormat;
		_selectedTiVo = _myTiVos.selectedTiVo;
		_formatList = _myTiVos.formatList;
		_tiVoList = _myTiVos.tiVoList;
	}
	return self;
}

-(void)awakeFromNib
{
//Connect displays to data sources
    tiVoShowTable.tiVoShows = _myTiVos.tiVoShows; 
    downloadQueueTable.downloadQueue = _myTiVos.downloadQueue; 
    subscriptionTable.subscribedShows = _myTiVos.subscribedShows;
	[self refreshFormatListPopup];
	
}

- (void)windowDidLoad
{
    [super windowDidLoad];
    
    // Implement this method to handle any initialization after your window controller's window has been loaded from its nib file.
	[tiVoListPopUp removeAllItems];
	[tiVoListPopUp addItemWithTitle:@"Searching for TiVos..."];
    downloadDirectory.stringValue = _myTiVos.downloadDirectory;
 	_myTiVos.tiVoShowTableView = tiVoShowTable;
   [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshTiVoListPopup) name:kMTNotificationTiVoListUpdated object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshFormatListPopup) name:kMTNotificationFormatListUpdated object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reloadProgramData) name:kMTNotificationTiVoShowsUpdated object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:downloadQueueTable selector:@selector(updateTable) name:kMTNotificationDownloadQueueUpdated object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:downloadQueueTable selector:@selector(updateProgress) name:kMTNotificationProgressUpdated object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(checkSubscription:) name: kMTNotificationDetailsLoaded object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:subscriptionTable selector:@selector(updateSubscriptionWithDate:) name:kMTNotificationEncodeDidFinish object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:loadingProgramListIndicator selector:@selector(startAnimation:) name:kMTNotificationShowListUpdating object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:loadingProgramListIndicator selector:@selector(stopAnimation:) name:kMTNotificationShowListUpdated object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(tableSelectionChanged:) name:NSTableViewSelectionDidChangeNotification object:nil];
    [_myTiVos addObserver:self forKeyPath:@"programLoadingString" options:0 context:nil];
    [_myTiVos addObserver:self forKeyPath:@"selectedFormat" options:NSKeyValueObservingOptionInitial context:nil];
    

}

-(void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if ([keyPath compare:@"programLoadingString"] == NSOrderedSame) {
        loadingProgramListLabel.stringValue = _myTiVos.programLoadingString;
    }
    if ([keyPath compare:@"selectedFormat"] == NSOrderedSame) {
        _selectedFormat = _myTiVos.selectedFormat;
        BOOL caniTune = [[_selectedFormat objectForKey:@"iTunes"] boolValue];
        [addToiTunesButton setEnabled:caniTune];
        if (caniTune) {
            BOOL wantsiTunes = [[NSUserDefaults standardUserDefaults] boolForKey:kMTiTunesEncode];
            if (wantsiTunes) {
                [addToiTunesButton setState:NSOnState];
            } else {
                [addToiTunesButton setState:NSOffState];
            }
       } else {
           [addToiTunesButton setState:NSOffState];
        }

        BOOL canSimulEncode = ![[_selectedFormat objectForKey:@"mustDownloadFirst"] boolValue];
        [simultaneousEncodeButton setEnabled:canSimulEncode];
        if (canSimulEncode) {
            BOOL wantsSimul = [[NSUserDefaults standardUserDefaults] boolForKey:kMTSimultaneousEncode];
            if (wantsSimul) {
                [simultaneousEncodeButton setState:NSOnState];
            } else {
                [simultaneousEncodeButton setState:NSOffState];
            }
        } else {
            [simultaneousEncodeButton setState:NSOffState];
        }
    }
}

-(void)reloadProgramData
{
	tiVoShowTable.tiVoShows = _myTiVos.tiVoShows;
	[tiVoShowTable reloadData];
}

-(void)setFormatList:(NSMutableArray *)formatList
{
	_formatList = formatList;
    [self refreshFormatListPopup];
}


-(void)setTiVoList:(NSMutableArray *)tiVoList
{
	_tiVoList = tiVoList;
}


#pragma mark - Notification Responsders

-(void)refreshFormatListPopup
{
	[formatListPopUp removeAllItems];
//    if (_selectedFormat) {
//        mediaKeyLabel.stringValue = [[NSUserDefaults standardUserDefaults] stringForKey:[_selectedFormat objectForKey:@"name"]];
//    }
	for (NSDictionary *fl in _formatList) {
		[formatListPopUp addItemWithTitle:[fl objectForKey:@"name"]];
        [[formatListPopUp lastItem] setRepresentedObject:fl];
		if (_selectedFormat && [[fl objectForKey:@"name"] compare:[_selectedFormat objectForKey:@"name"]] == NSOrderedSame) {
			[formatListPopUp selectItem:[formatListPopUp lastItem]];
		}
		
	}
}

-(void)refreshTiVoListPopup
{
    NSString *selectedTiVoName = @"";
    if (!_selectedTiVo) {
        selectedTiVoName = [[NSUserDefaults standardUserDefaults] objectForKey:kMTSelectedTiVo];
    } else {
        selectedTiVoName = _selectedTiVo.name;
    }
	[tiVoListPopUp removeAllItems];
	for (NSNetService *ts in _tiVoList) {
		[tiVoListPopUp addItemWithTitle:ts.name];
        [[tiVoListPopUp lastItem] setRepresentedObject:ts];
		if ([ts.name compare:selectedTiVoName] == NSOrderedSame) {
			[tiVoListPopUp selectItem:[tiVoListPopUp lastItem]];
//            _myTiVos.selectedTiVo = ts;
            _selectedTiVo = ts;
		}
		
	}
    if (_selectedTiVo) {
		[mediaKeyLabel setEnabled:YES];
        mediaKeyLabel.stringValue = [[[NSUserDefaults standardUserDefaults]  objectForKey:kMTMediaKeys] objectForKey:_selectedTiVo.name];
        [_myTiVos fetchVideoListFromHost:_selectedTiVo];
    }
}

#pragma mark - UI Actions

-(IBAction)selectTivo:(id)sender
{
    NSPopUpButton *thisButton = (NSPopUpButton *)sender;
    _selectedTiVo = [[thisButton selectedItem] representedObject];
//    _myTiVos.selectedTiVo = _selectedTiVo;
    mediaKeyLabel.enabled =  (_selectedTiVo != nil);
    //mediaKeyLabel.stringValue = @"";
    NSString * possibleKey =[[[NSUserDefaults standardUserDefaults]  objectForKey:kMTMediaKeys] objectForKey:_selectedTiVo.name];
	if (possibleKey) {
		mediaKeyLabel.stringValue = possibleKey;
	}
	[[NSUserDefaults standardUserDefaults] setObject:_selectedTiVo.name forKey:kMTSelectedTiVo];
	[_myTiVos fetchVideoListFromHost:_selectedTiVo];
}

-(IBAction)selectFormat:(id)sender
{
    NSPopUpButton *thisButton = (NSPopUpButton *)sender;
    _myTiVos.selectedFormat = [[thisButton selectedItem] representedObject];
//    _selectedFormat = _myTiVos.selectedFormat;
	[[NSUserDefaults standardUserDefaults] setObject:[_selectedFormat objectForKey:@"name"] forKey:kMTSelectedFormat];
	
}

#pragma mark - Subscription Management
-(void) checkSubscriptionShow:(MTTiVoShow *) show {
	if([subscriptionTable isSubscribed:show] && ([show.downloadStatus intValue] == kMTStatusNew)) {
		[self downloadthisShow:show];
		[[NSNotificationCenter defaultCenter ] postNotificationName:  kMTNotificationDownloadQueueUpdated object:self];
	}
}

-(void) checkSubscription: (NSNotification *) notification {
	[self checkSubscriptionShow: (MTTiVoShow *) notification.object];
}

-(void) checkSubscriptionsAll {
	for (MTTiVoShow * show in _myTiVos.tiVoShows.reverseObjectEnumerator) {
		[self checkSubscriptionShow:show];
	}
}

-(IBAction)subscribe:(id) sender {
	BOOL anySubscribed = NO;
    for (int i = 0; i < _myTiVos.tiVoShows.count; i++) {
        if ([tiVoShowTable isRowSelected:i]) {
			anySubscribed = YES;
			MTTiVoShow *thisShow = [_myTiVos.tiVoShows objectAtIndex:i];
			[subscriptionTable addSubscription:thisShow];
		}
	}
	if (anySubscribed) {
		[self checkSubscriptionsAll];
		[[NSNotificationCenter defaultCenter ] postNotificationName:  kMTNotificationDownloadQueueUpdated object:self];
		[subscriptionTable reloadData];
	}
}

-(void) downloadthisShow:(MTTiVoShow*) thisShow {
	thisShow.addToiTunesWhenEncoded = NO;
	if (addToiTunesButton.state == NSOnState && [[_selectedFormat objectForKey:@"iTunes"] boolValue]) {
		thisShow.addToiTunesWhenEncoded  = YES;
	}
	thisShow.simultaneousEncode = YES;
	if (simultaneousEncodeButton.state == NSOffState) {
		thisShow.simultaneousEncode = NO;
	}
	thisShow.isQueued = YES;
     [_myTiVos addProgramToDownloadQueue:thisShow];
}

-(IBAction)downloadSelectedShows:(id)sender
{
	NSIndexSet *selectedRows = [tiVoShowTable selectedRowIndexes];
    for (int i = 0; i < _myTiVos.tiVoShows.count; i++) {
        if([selectedRows containsIndex:i]) {
            [self downloadthisShow:[_myTiVos.tiVoShows objectAtIndex:i]];
        }
    }
	[tiVoShowTable deselectAll:nil];
	[downloadQueueTable deselectAll:nil];
//    [tiVoShowTable reloadData];
	[[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationDownloadQueueUpdated object:nil];
}

-(IBAction)removeFromDownloadQueue:(id)sender
{
	NSIndexSet *selectedRows = [downloadQueueTable selectedRowIndexes];
	NSMutableArray *itemsToRemove = [NSMutableArray array];
    for (int i = 0; i <  _myTiVos.downloadQueue.count; i++) {
        if ([selectedRows containsIndex:i]) {
            MTTiVoShow *programToRemove = [_myTiVos.downloadQueue objectAtIndex:i];
            if ([programToRemove cancel]) {
                [itemsToRemove addObject:programToRemove];
            }
       }
    }
	for (id i in itemsToRemove) {
        ((MTTiVoShow *)i).isQueued = NO;
		[_myTiVos.downloadQueue removeObject:i];
        [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationTiVoShowsUpdated object:nil];
	}
//    [tiVoShowTable reloadData];
	[tiVoShowTable deselectAll:nil];
	[downloadQueueTable deselectAll:nil];
	[[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationDownloadQueueUpdated object:nil];
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
        _myTiVos.downloadDirectory = dir;
		[[NSUserDefaults standardUserDefaults] setValue:dir forKey:kMTDownloadDirectory];
        downloadDirectory.toolTip = dir;
	}
}

-(IBAction)changeSimultaneous:(id)sender
{
    MTCheckBox *checkbox = sender;
    if (sender == simultaneousEncodeButton) {
        [[NSUserDefaults standardUserDefaults] setBool:checkbox.state forKey:kMTSimultaneousEncode];
    } else {
        if (checkbox.owner.simultaneousEncode) {
            checkbox.owner.simultaneousEncode = NO;
        } else {
            checkbox.owner.simultaneousEncode = YES;
        }
    }
}

-(IBAction)changeiTunes:(id)sender
{     
    MTCheckBox *checkbox = sender;
    if (sender == addToiTunesButton) {
        [[NSUserDefaults standardUserDefaults] setBool:checkbox.state forKey:kMTiTunesEncode];
    } else {
        //updating an individual show in download queue
        if (checkbox.owner.addToiTunesWhenEncoded) {
            checkbox.owner.addToiTunesWhenEncoded = NO;
        } else {
            checkbox.owner.addToiTunesWhenEncoded = YES;
        }
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
    [[NSNotificationCenter defaultCenter] removeObserver:self];
	[super dealloc];
}



#pragma mark - Text Editing Delegate

-(BOOL)control:(NSControl *)control textShouldEndEditing:(NSText *)fieldEditor
{
    if (control == mediaKeyLabel) {
        NSString *newMAK = control.stringValue;
        NSMutableDictionary *mediaKeys = [NSMutableDictionary dictionaryWithDictionary:[[NSUserDefaults standardUserDefaults] objectForKey:kMTMediaKeys]];
        [mediaKeys setObject:newMAK forKey:_selectedTiVo.name];
        [[NSUserDefaults standardUserDefaults] setObject:mediaKeys forKey:kMTMediaKeys];
        [_myTiVos fetchVideoListFromHost:_selectedTiVo];
    }
    if (control == downloadDirectory) {
        _myTiVos.downloadDirectory = control.stringValue;
		[[NSUserDefaults standardUserDefaults] setValue:control.stringValue forKey:kMTDownloadDirectory];
    }
	return YES;
}



@end
