//
//  MTMainWindowController.h
//  cTiVo
//
//  Created by Scott Buchanan on 12/13/12.
//  Copyright (c) 2012 Scott Buchanan. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "MTTiVoManager.h"
#import "MTFormatEditorController.h"

@class MTDownloadTableView;
@class MTProgramTableView;
@class MTSubscriptionTableView;
@class MTFormatPopUpButton;

@interface MTMainWindowController : NSWindowController <NSMenuDelegate> {
	IBOutlet NSPopUpButton *tiVoListPopUp;
	IBOutlet MTFormatPopUpButton *formatListPopUp;
	IBOutlet NSTextField *loadingProgramListLabel, *downloadDirectory, *tiVoListPopUpLabel, *pausedLabel;
	IBOutlet NSProgressIndicator *loadingProgramListIndicator, *searchingTiVosIndicator;
	IBOutlet MTDownloadTableView *__weak downloadQueueTable;
	IBOutlet MTProgramTableView  *__weak tiVoShowTable;
	IBOutlet MTSubscriptionTableView  *__weak subscriptionTable;
	IBOutlet NSDrawer *showDetailDrawer;
	NSPoint menuCursorPosition;
	NSInteger menuTableRow;
	NSMutableArray *loadingTiVos;
}

@property (nonatomic, weak) MTDownloadTableView *downloadQueueTable;
@property (nonatomic, weak) MTProgramTableView *tiVoShowTable;
@property (nonatomic, weak) MTSubscriptionTableView *subscriptionTable;
@property (nonatomic, strong) NSString *selectedTiVo;
@property (nonatomic, strong) MTTiVoShow *showForDetail;
@property (weak, nonatomic, readonly) MTTiVoManager *myTiVoManager;
@property (nonatomic, weak) NSMenuItem *showInFinderMenuItem, *playVideoMenuItem;
@property (nonatomic, strong) IBOutlet NSView *cancelQuitView;

-(IBAction)selectFormat:(id)sender;
-(IBAction)subscribe:(id) sender;
-(BOOL) selectionContainsCompletedShows;
-(IBAction) revealInFinder:(id) sender;
-(IBAction) playVideo: (id) sender;
-(void) playTrashSound;

-(IBAction)downloadSelectedShows:(id)sender;
-(IBAction)removeFromDownloadQueue:(id)sender;
-(IBAction)getDownloadDirectory:(id)sender;
//-(IBAction)changeSimultaneous:(id)sender;
-(IBAction)changeiTunes:(id)sender;
-(IBAction)dontQuit:(id)sender;


@end
