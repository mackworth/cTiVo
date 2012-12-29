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


- (id)initWithWindow:(NSWindow *)window
{
    self = [super initWithWindow:window];
    if (self) {
        // Initialization code here.
        _selectedFormat = nil;
    }
    
    return self;
}

- (void)windowDidLoad
{
    [super windowDidLoad];
    
    // Implement this method to handle any initialization after your window controller's window has been loaded from its nib file.
	[tiVoListPopUp removeAllItems];
	[tiVoListPopUp addItemWithTitle:@"Searching for TiVos..."];
    tiVoShowTable.tiVoShows = _myTiVos.tiVoShows;  //Connect display to data source
    downloadQueueTable.downloadQueue = _myTiVos.downloadQueue;  //Connect display to data source
    subscriptionTable.subscribedShows = _myTiVos.subscribedShows;  //Connect display to data source
    downloadDirectory.stringValue = _myTiVos.downloadDirectory;
    _selectedFormat = _myTiVos.selectedFormat;
    _selectedTiVo = _myTiVos.selectedTiVo;
    self.formatList = _myTiVos.formatList;
    self.tiVoList = _myTiVos.tiVoList;
    [addToiTunesButton setState:NSOffState];
    [simultaneousEncodeButton setState:NSOnState];
 	_myTiVos.tiVoShowTableView = tiVoShowTable;
   [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshTiVoListPopup) name:kMTNotificationTiVoListUpdated object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshFormatListPopup) name:kMTNotificationFormatListUpdated object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:tiVoShowTable selector:@selector(reloadData) name:kMTNotificationTiVoShowsUpdated object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:downloadQueueTable selector:@selector(reloadData) name:kMTNotificationDownloadQueueUpdated object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(checkSubscription:) name: kMTNotificationDetailsLoaded object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:loadingProgramListIndicator selector:@selector(startAnimation:) name:kMTNotificationShowListUpdating object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:loadingProgramListIndicator selector:@selector(stopAnimation:) name:kMTNotificationShowListUpdated object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(tableSelectionChanged:) name:NSTableViewSelectionDidChangeNotification object:nil];
    [_myTiVos addObserver:self forKeyPath:@"programLoadingString" options:0 context:nil];
    [_myTiVos addObserver:self forKeyPath:@"selectedFormat" options:0 context:nil];
	BOOL canSimulEncode = ![[_myTiVos.selectedFormat objectForKey:@"mustDownloadFirst"] boolValue];
	simultaneousEncodeButton.state = NSOffState;
	if (canSimulEncode) {
		simultaneousEncodeButton.state = NSOnState;
	}

    
}

-(void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if ([keyPath compare:@"programLoadingString"] == NSOrderedSame) {
        loadingProgramListLabel.stringValue = _myTiVos.programLoadingString;
    }
    if ([keyPath compare:@"selectedFormat"] == NSOrderedSame) {
        _selectedFormat = _myTiVos.selectedFormat;
        BOOL caniTune = [[_selectedFormat objectForKey:@"iTunes"] boolValue];
        BOOL canSimulEncode = ![[_selectedFormat objectForKey:@"mustDownloadFirst"] boolValue];
        [addToiTunesButton setEnabled:YES];
        if (!caniTune) {
            [addToiTunesButton setState:NSOffState];
            [addToiTunesButton setEnabled:NO];
        }
        [simultaneousEncodeButton setEnabled:YES];
        [simultaneousEncodeButton setState:NSOnState];
        if (!canSimulEncode) {
            [simultaneousEncodeButton setState:NSOffState];
            [simultaneousEncodeButton setEnabled:NO];
        }
    }
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
	if([subscriptionTable isSubscribed:show] && (show.downloadStatus == kMTStatusNew)) {
		[self downloadthisShow:show];
		[[NSNotificationCenter defaultCenter ] postNotificationName:  kMTNotificationDownloadQueueUpdated object:self];
	}
}

-(void) checkSubscription: (NSNotification *) notification {
	[self checkSubscriptionShow: (MTTiVoShow *) notification.object];
}

-(void) checkSubscriptionsAll {
	for (MTTiVoShow * show in _myTiVos.tiVoShows) {
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
    for (int i = 0; i < _myTiVos.tiVoShows.count; i++) {
        if([tiVoShowTable isRowSelected:i]) {
            [self downloadthisShow:[_myTiVos.tiVoShows objectAtIndex:i]];
        }
    }
	[tiVoShowTable deselectAll:nil];
	[downloadQueueTable deselectAll:nil];
    [tiVoShowTable reloadData];
	[[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationDownloadQueueUpdated object:nil];
}

-(IBAction)removeFromDownloadQueue:(id)sender
{
	NSMutableArray *itemsToRemove = [NSMutableArray array];
    for (int i = 0; i <  _myTiVos.downloadQueue.count; i++) {
        if ([downloadQueueTable isRowSelected:i]) {
            MTTiVoShow *programToRemove = [_myTiVos.downloadQueue objectAtIndex:i];
            if ([programToRemove cancel]) {
                [itemsToRemove addObject:programToRemove];
            }
       }
    }
	for (id i in itemsToRemove) {
        ((MTTiVoShow *)i).isQueued = NO;
		[_myTiVos.downloadQueue removeObject:i];
	}
    [tiVoShowTable reloadData];
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
    if (checkbox.owner.simultaneousEncode) {
        checkbox.owner.simultaneousEncode = NO;
    } else {
        checkbox.owner.simultaneousEncode = YES;
    }
}

-(IBAction)changeiTunes:(id)sender
{     
    MTCheckBox *checkbox = sender;
    if (checkbox.owner.addToiTunesWhenEncoded) {
        checkbox.owner.addToiTunesWhenEncoded = NO;
    } else {
        checkbox.owner.addToiTunesWhenEncoded = YES;
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
