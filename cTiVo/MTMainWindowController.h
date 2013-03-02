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
    IBOutlet NSButton *addToQueueButton, *removeFromQueueButton, *subscribeButton;
	IBOutlet NSTextField *loadingProgramListLabel, *downloadDirectory, *tiVoListPopUpLabel, *pausedLabel;
	IBOutlet NSProgressIndicator *loadingProgramListIndicator, *searchingTiVosIndicator;
	IBOutlet MTDownloadTableView *downloadQueueTable;
	IBOutlet MTProgramTableView  *tiVoShowTable;
	IBOutlet MTSubscriptionTableView  *subscriptionTable;
	IBOutlet NSDrawer *showDetailDrawer;
	NSPoint menuCursorPosition;
	NSInteger menuTableRow;
	NSMutableArray *loadingTiVos;
}

@property (nonatomic, assign) MTDownloadTableView *downloadQueueTable;
@property (nonatomic, assign) MTProgramTableView *tiVoShowTable;
@property (nonatomic, assign) MTSubscriptionTableView *subscriptionTable;
@property (nonatomic, retain) NSString *selectedTiVo;
@property (nonatomic, retain) MTTiVoShow *showForDetail;
@property (nonatomic, readonly) MTTiVoManager *myTiVoManager;
@property (nonatomic, assign) NSMenuItem *showInFinderMenuItem, *playVideoMenuItem;
@property (nonatomic, retain) IBOutlet NSView *cancelQuitView;
@property (nonatomic, retain) IBOutlet NSView * drawerVariableFields;

-(IBAction)selectFormat:(id)sender;
-(IBAction)subscribe:(id) sender;
-(BOOL) selectionContainsCompletedShows;
-(IBAction) revealInFinder:(id) sender;
-(IBAction) playVideo: (id) sender;
-(void) playTrashSound;

-(IBAction)downloadSelectedShows:(id)sender;
-(IBAction)removeFromDownloadQueue:(id)sender;
-(IBAction)getDownloadDirectory:(id)sender;
-(IBAction)changeSimultaneous:(id)sender;
-(IBAction)changeiTunes:(id)sender;
-(IBAction)dontQuit:(id)sender;


@end
