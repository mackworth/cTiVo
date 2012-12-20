//
//  MTMainWindowController.m
//  cTiVo
//
//  Created by Scott Buchanan on 12/13/12.
//  Copyright (c) 2012 Scott Buchanan. All rights reserved.
//

#import "MTMainWindowController.h"

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
    tiVoShowTable.tiVoShows = _myTiVos.tiVoShows;  //Connect display to data source
    downloadQueueTable.downloadQueue = _myTiVos.downloadQueue;  //Connect display to data source
    downloadDirectory.stringValue = _myTiVos.downloadDirectory;
    _selectedFormat = _myTiVos.selectedFormat;
    _selectedTiVo = _myTiVos.selectedTiVo;
    self.formatList = _myTiVos.formatList;
    self.tiVoList = _myTiVos.tiVoList;
    [addToiTunesButton setState:NSOffState];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshTiVoListPopup) name:kMTNotificationTiVoListUpdated object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshFormatListPopup) name:kMTNotificationFormatListUpdated object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:tiVoShowTable selector:@selector(reloadData) name:kMTNotificationTiVoShowsUpdated object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:downloadQueueTable selector:@selector(reloadData) name:kMTNotificationDownloadQueueUpdated object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:loadingProgramListIndicator selector:@selector(startAnimation:) name:kMTNotificationShowListUpdating object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:loadingProgramListIndicator selector:@selector(stopAnimation:) name:kMTNotificationShowListUpdated object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(tableSelectionChanged:) name:NSTableViewSelectionDidChangeNotification object:nil];
    [_myTiVos addObserver:self forKeyPath:@"programLoadingString" options:0 context:nil];
    [_myTiVos addObserver:self forKeyPath:@"selectedFormat" options:0 context:nil];
    
}

-(void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if ([keyPath compare:@"programLoadingString"] == NSOrderedSame) {
        loadingProgramListLabel.stringValue = _myTiVos.programLoadingString;
    }
    if ([keyPath compare:@"selectedFormat"] == NSOrderedSame) {
        _selectedFormat = _myTiVos.selectedFormat;
        BOOL caniTune = [[_selectedFormat objectForKey:@"iTunes"] boolValue];
        [addToiTunesButton setEnabled:YES];
        if (!caniTune) {
            [addToiTunesButton setState:NSOffState];
            [addToiTunesButton setEnabled:NO];
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
    mediaKeyLabel.stringValue = @"";
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
            _myTiVos.selectedTiVo = ts;
            _selectedTiVo = ts;
		}
		
	}
    if (_selectedTiVo) {
        mediaKeyLabel.stringValue = [[[NSUserDefaults standardUserDefaults]  objectForKey:kMTMediaKeys] objectForKey:_selectedTiVo.name];
        [_myTiVos fetchVideoListFromHost];
    }
}

#pragma mark - UI Actions

-(IBAction)selectTivo:(id)sender
{
    NSPopUpButton *thisButton = (NSPopUpButton *)sender;
    _myTiVos.selectedTiVo = [[thisButton selectedItem] representedObject];
    _selectedTiVo = _myTiVos.selectedTiVo;
    mediaKeyLabel.stringValue = @"";
	if ([[[NSUserDefaults standardUserDefaults]  objectForKey:kMTMediaKeys] objectForKey:_selectedTiVo.name]) {
		mediaKeyLabel.stringValue = [[[NSUserDefaults standardUserDefaults]  objectForKey:kMTMediaKeys] objectForKey:_selectedTiVo.name];
	}
	[[NSUserDefaults standardUserDefaults] setObject:_selectedTiVo.name forKey:kMTSelectedTiVo];
    [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationTiVoChanged object:nil];
}

-(IBAction)selectFormat:(id)sender
{
    NSPopUpButton *thisButton = (NSPopUpButton *)sender;
    _myTiVos.selectedFormat = [[thisButton selectedItem] representedObject];
//    _selectedFormat = _myTiVos.selectedFormat;
	[[NSUserDefaults standardUserDefaults] setObject:[_selectedFormat objectForKey:@"name"] forKey:kMTSelectedFormat];
	
}
-(IBAction)updateDownloadQueue:(id)sender
{
    for (int i = 0; i < _myTiVos.tiVoShows.count; i++) {
        if([tiVoShowTable isRowSelected:i]) {
            MTTiVoShow *thisShow = [_myTiVos.tiVoShows objectAtIndex:i];
            thisShow.addToiTunesWhenEncoded = NO;
            if (addToiTunesButton.state == NSOnState && [[_selectedFormat objectForKey:@"iTunes"] boolValue]) {
                thisShow.addToiTunesWhenEncoded  = YES;
            }
            [_myTiVos addProgramToDownloadQueue:[_myTiVos.tiVoShows objectAtIndex:i]];
        }
    }
	[tiVoShowTable deselectAll:nil];
	[downloadQueueTable deselectAll:nil];
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
		[_myTiVos.downloadQueue removeObject:i];
	}
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
	}
}

#pragma mark - Table View Notification Handling

-(void)tableSelectionChanged:(NSNotification *)notification
{
    [addToQueueButton setEnabled:NO];
    [removeFromQueueButton setEnabled:NO];
    if ([downloadQueueTable numberOfSelectedRows]) {
        [removeFromQueueButton setEnabled:YES];
    }
    if ([tiVoShowTable numberOfSelectedRows]) {
        [addToQueueButton setEnabled:YES];
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
        [_myTiVos fetchVideoListFromHost];
    }
    if (control == downloadDirectory) {
        _myTiVos.downloadDirectory = control.stringValue;
		[[NSUserDefaults standardUserDefaults] setValue:control.stringValue forKey:kMTDownloadDirectory];
    }
	return YES;
}



@end
