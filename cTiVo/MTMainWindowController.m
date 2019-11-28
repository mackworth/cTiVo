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
#import "MTSubscriptionList.h"
#import "MTHelpViewController.h"
#import "MTShowFolder.h"
#import "MTAppDelegate.h"
#import "NSArray+Map.h"

#import "MTFormatPopUpButton.h"
#import "MTCheckBox.h"
#import "MTTiVo.h"
#import "MTTVDB.h"
#import "NSArray+Map.h"

#import <Quartz/Quartz.h>

@implementation NSView (HS)

-(NSView *)insertVibrancyView {
    if (@available(macOS 10.10, *)) {
        if (NSClassFromString(@"NSVisualEffectView") ) { //should always be supported
            NSVisualEffectView *vibrant=[[NSVisualEffectView alloc] initWithFrame:self.bounds];
            [vibrant setAutoresizingMask:NSViewWidthSizable|NSViewHeightSizable];
            [vibrant setBlendingMode:NSVisualEffectBlendingModeBehindWindow];
            [self addSubview:vibrant positioned:NSWindowBelow relativeTo:nil];
            return vibrant;
        }
    }
    return self;
}

@end

@interface MTMainWindowController () {
	IBOutlet NSPopUpButton *tiVoListPopUp;
	IBOutlet MTFormatPopUpButton *formatListPopUp;
	IBOutlet NSTextField *loadingProgramListLabel,  *tiVoListPopUpLabel, *pausedLabel;
	IBOutlet NSProgressIndicator *loadingProgramListIndicator, *searchingTiVosIndicator;
	
	IBOutlet MTDownloadTableView *__weak downloadQueueTable;
	IBOutlet MTProgramTableView  *__weak tiVoShowTable;
	IBOutlet MTSubscriptionTableView  *__weak subscriptionTable;
	IBOutlet NSDrawer *showDetailDrawer;
}

@property (nonatomic, weak) MTDownloadTableView *downloadQueueTable;
@property (nonatomic, weak) MTProgramTableView *tiVoShowTable;
@property (nonatomic, weak) MTSubscriptionTableView *subscriptionTable;
@property (nonatomic, strong) NSString *selectedTiVo;
@property (nonatomic, strong) MTTiVoShow *showForDetail;
@property (weak, nonatomic, readonly) MTTiVoManager *myTiVoManager;
@property (nonatomic, weak) NSMenuItem *showInFinderMenuItem, *playVideoMenuItem;
@property (nonatomic, strong) IBOutlet NSView *cancelQuitView;
@property (nonatomic, weak) IBOutlet NSImageView * icon;

-(IBAction)selectFormat:(id)sender;
-(IBAction)subscribe:(id) sender;
-(IBAction) revealInFinder:(id) sender;
-(IBAction) playVideo: (id) sender;

-(IBAction)downloadSelectedShows:(id)sender;
-(IBAction)getDownloadDirectory:(id)sender;
//-(IBAction)changeSimultaneous:(id)sender;
-(IBAction)changeiTunes:(id)sender;
-(IBAction)dontQuit:(id)sender;


@property (nonatomic, strong) NSSound *trashSound;
@property (nonatomic, strong) NSCountedSet *loadingTiVos;
@property (nonatomic, strong) NSCountedSet *commercialingTiVos;

@end

@implementation MTMainWindowController

__DDLOGHERE__

@synthesize tiVoShowTable,subscriptionTable, downloadQueueTable;

-(id)initWithWindowNibName:(NSString *)windowNibName
{
    DDLogDetail(@"creating Main Window");
	self = [super initWithWindowNibName:windowNibName];
	if (self) {
		_loadingTiVos = [NSCountedSet new];
		_commercialingTiVos = [NSCountedSet new];
        self.selectedTiVo = nil;
        _myTiVoManager = tiVoManager;
	}
    [self refreshFormatListPopup];

	return self;
}

- (void)windowDidLoad
{
    [super windowDidLoad];
    
	DDLogDetail(@"MainWindow windowDidLoad");
    // Implement this method to handle any initialization after your window controller's window has been loaded from its nib file.
    
    [self.window.contentView insertVibrancyView];
#ifdef MAC_APP_STORE
	self.icon.image = [NSApp applicationIconImage];
#endif
	self.window.title = kcTiVoName;
    [[NSBundle mainBundle] loadNibNamed:@"MTMainWindowDrawer" owner:self topLevelObjects:nil];
	showDetailDrawer.parentWindow = self.window;
	
	NSNotificationCenter *defaultCenter = [NSNotificationCenter defaultCenter];
	[defaultCenter addObserver:self selector:@selector(refreshTiVoListPopup:) name:kMTNotificationTiVoListUpdated object:nil];
	[defaultCenter addObserver:self selector:@selector(buildColumnMenuForTables) name:kMTNotificationTiVoListUpdated object:nil];
	[defaultCenter addObserver:self selector:@selector(refreshTiVoListPopup:) name:kMTNotificationTiVoShowsUpdated object:nil];
    [defaultCenter addObserver:self selector:@selector(refreshFormatListPopup) name:kMTNotificationFormatListUpdated object:nil];
	
	//Spinner Progress Handling 
    [defaultCenter addObserver:self selector:@selector(manageLoadingIndicator:) name:kMTNotificationTiVoUpdating object:nil];
    [defaultCenter addObserver:self selector:@selector(manageLoadingIndicator:) name:kMTNotificationTiVoUpdated object:nil];
	[defaultCenter addObserver:self selector:@selector(manageLoadingIndicator:) name:kMTNotificationTiVoCommercialing object:nil];
	[defaultCenter addObserver:self selector:@selector(manageLoadingIndicator:) name:kMTNotificationTiVoCommercialed object:nil];
    [defaultCenter addObserver:self selector:@selector(networkChanged:) name:kMTNotificationNetworkChanged object:nil];
	
    [defaultCenter addObserver:self selector:@selector(columnOrderChanged:) name:NSTableViewColumnDidMoveNotification object:nil];
	[tiVoManager addObserver:self forKeyPath:@"selectedFormat" options:NSKeyValueObservingOptionInitial context:nil];
	[[NSUserDefaults standardUserDefaults] addObserver:self forKeyPath:kMTIfSuccessDeleteFromTiVo options:NSKeyValueObservingOptionInitial context:nil];

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

-(void) showCancelQuitView:(BOOL) show {
	self.cancelQuitView.hidden = !show;
}

-(void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
	if ([keyPath compare:@"selectedFormat"] == NSOrderedSame) {
        [formatListPopUp selectFormat:[tiVoManager selectedFormat]];
	} else if ([keyPath compare:kMTIfSuccessDeleteFromTiVo] == NSOrderedSame) {
		//Always show Del After columns if user enables DeleteFromTiVo
		BOOL deleteAfter =[[NSUserDefaults standardUserDefaults] boolForKey:kMTIfSuccessDeleteFromTiVo];
		NSTableColumn * downloadDeleteAfter = [self.downloadQueueTable tableColumnWithIdentifier: @"Delete"];
		if (downloadDeleteAfter.isHidden == deleteAfter) {
			downloadDeleteAfter.hidden = !deleteAfter;
			if ([self.downloadQueueTable respondsToSelector:@selector(columnChanged:)]) {
				[self.downloadQueueTable performSelector:@selector(columnChanged:) withObject:downloadDeleteAfter];
			}
			[self buildColumnMenuForTable: downloadQueueTable];
		}
		NSTableColumn * subDeleteAfter = [self.subscriptionTable tableColumnWithIdentifier: @"Delete"];
		if (subDeleteAfter.isHidden == deleteAfter) {
			subDeleteAfter.hidden = !deleteAfter;
			if ([self.subscriptionTable respondsToSelector:@selector(columnChanged:)]) {
				[self.subscriptionTable performSelector:@selector(columnChanged:) withObject:subDeleteAfter];
			}
			[self buildColumnMenuForTable: subscriptionTable];
		}
	} else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

-(void)networkChanged:(NSNotification *)notification
{
	DDLogMajor(@"MainWindow network Changed");
	[[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationTiVoListUpdated object:_selectedTiVo];
	[[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationTiVoShowsUpdated object:nil];
	
}

-(NSMutableAttributedString *) stringForDisplay: (NSSet <MTTiVo *> *) set forCommercials: (BOOL) commercials {
	NSString * path = commercials ? @"skipModeStatus" : @"tiVo.name";
	NSColor * red =  [NSColor redColor];
	if (@available(macOS 10.10, *)) red = [NSColor systemRedColor];
	NSDictionary <NSAttributedStringKey,id> * attribs = commercials ? @{NSForegroundColorAttributeName:red}  : @{};
	NSMutableArray * names = [[[set allObjects] valueForKeyPath: path] mutableCopy];
	[names removeObjectIdenticalTo:[NSNull null]];
	[names sortUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
	NSString * list = [names componentsJoinedByString:@", "];
 return [[NSMutableAttributedString alloc] initWithString: list attributes:attribs];
}

-(void)manageLoadingIndicator:(NSNotification *)notification
{
	if (!notification) { //Don't accept nil notifications
		return;  
	}
    MTTiVo * tivo = (MTTiVo *) notification.object;
    if (tivo) {
		DDLogDetail(@"LoadingIndicator: %@ for %@",notification.name, tivo.tiVo.name);
		if ([notification.name  compare:kMTNotificationTiVoUpdating] == NSOrderedSame) {
			[self.loadingTiVos addObject:tivo];
		} else if ([notification.name compare:kMTNotificationTiVoUpdated] == NSOrderedSame) {
			[self.loadingTiVos removeObject:tivo];
		} else if ([notification.name compare:kMTNotificationTiVoCommercialing] == NSOrderedSame) {
			[self.commercialingTiVos addObject:tivo];
		} else if ([notification.name compare:kMTNotificationTiVoCommercialed] == NSOrderedSame) {
			[self.commercialingTiVos removeObject:tivo];
		}
	}// else just update the current string
	if (self.loadingTiVos.count + self.commercialingTiVos.count > 0) {
        [loadingProgramListIndicator startAnimation:nil];
		NSMutableAttributedString *message =  [[NSMutableAttributedString alloc] init];
		if (self.loadingTiVos.count > 0) {
			[message appendAttributedString:[[NSMutableAttributedString alloc] initWithString:@"Updating "]];
			[message appendAttributedString:[self stringForDisplay:self.loadingTiVos forCommercials:NO]];
			if (self.commercialingTiVos.count > 0) {
				[message appendAttributedString:[[NSMutableAttributedString alloc] initWithString:@", "]];
			}
		}
		if (self.commercialingTiVos.count > 0) {
			NSColor * red =  [NSColor redColor];
			if (@available(macOS 10.10, *)) red = [NSColor systemRedColor];
			[message appendAttributedString:[[NSMutableAttributedString alloc] initWithString:@"Getting SkipMode for "
																				   attributes:@{NSForegroundColorAttributeName:red} ]];
			[message appendAttributedString:[self stringForDisplay:self.commercialingTiVos forCommercials:YES]];
		}
		[loadingProgramListLabel setAttributedStringValue: message];
    } else {
        [loadingProgramListIndicator stopAnimation:nil];
        loadingProgramListLabel.stringValue = @"";
    }
}

#pragma mark - Notification Responsders

-(void)refreshFormatListPopup {
	formatListPopUp.showHidden = NO;
    tiVoManager.selectedFormat = [formatListPopUp selectFormat:tiVoManager.selectedFormat];
	formatListPopUp.formatList =  tiVoManager.formatList;

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
			NSColor * red =  [NSColor redColor];
			if (@available(macOS 10.10, *)) red = [NSColor systemRedColor];
			NSAttributedString *aTitle = [[NSAttributedString alloc] initWithString:thisTitle attributes:@ { NSForegroundColorAttributeName: red, NSFontAttributeName:  thisFont}];
            [thisItem setAttributedTitle:aTitle];

        }
		if ([ts.tiVo.name compare:self.selectedTiVo] == NSOrderedSame) {
			[tiVoListPopUp selectItem:thisItem];
		}
		
	}
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(popupHelpIfNotTiVosAfterInterval) object:nil];
   if (tiVoManager.tiVoList.count == 0) {
		[tiVoListPopUp setHidden:YES];
		tiVoListPopUpLabel.stringValue = @"Searching for TiVos...";
		tiVoListPopUpLabel.hidden = NO;
		[searchingTiVosIndicator startAnimation:nil];
        [self performSelector:@selector(popupHelpIfNotTiVosAfterInterval) withObject:Nil afterDelay:kMTTimeToHelpIfNoTiVoFound];
	} else if (tiVoManager.tiVoList.count == 1) {
        [searchingTiVosIndicator stopAnimation:nil];
		MTTiVo *ts = tiVoManager.tiVoList[0];
        [tiVoListPopUp selectItem:[tiVoListPopUp lastItem]];
		[tiVoListPopUpLabel setHidden:NO];
		[tiVoListPopUp setHidden:YES];
        tiVoListPopUpLabel.stringValue = [NSString stringWithFormat:@"TiVo: %@ (%ld)",ts.tiVo.name,ts.shows.count];
        if (!ts.isReachable) {
            NSFont *thisFont = [NSFont systemFontOfSize:13];
            NSString *thisTitle = [NSString stringWithFormat:@"TiVo: %@ offline",ts.tiVo.name];
			NSColor * red =  [NSColor redColor];
			if (@available(macOS 10.10, *)) red = [NSColor systemRedColor];
			NSAttributedString *aTitle = [[NSAttributedString alloc] initWithString:thisTitle attributes:@ { NSForegroundColorAttributeName: red, NSFontAttributeName:  thisFont}];
            [tiVoListPopUpLabel setAttributedStringValue:aTitle];
			
        }
    } else if (tiVoManager.tiVoList.count > 1){
        [searchingTiVosIndicator stopAnimation:nil];
        [tiVoListPopUp.menu addItem:[NSMenuItem separatorItem]];
        [tiVoListPopUp addItemWithTitle:[NSString stringWithFormat:@"%@ (%d shows)",kMTAllTiVos,tiVoManager.totalShows]];
        if ([kMTAllTiVos compare:_selectedTiVo] == NSOrderedSame) {
            [tiVoListPopUp selectItem:[tiVoListPopUp lastItem]];
        }
        [tiVoListPopUp setHidden:NO];
        [tiVoListPopUpLabel setHidden:NO];
        tiVoListPopUpLabel.stringValue = @"Select TiVo:";
    }
}

-(void)popupHelpIfNotTiVosAfterInterval {
	//Get help text for Finding TiVos
	MTHelpViewController *helpController = [[MTHelpViewController alloc] init];
	[helpController loadResource:@"FindTiVoHelpFile"];
	[helpController pointToView:searchingTiVosIndicator preferredEdge: NSMaxXEdge];
}

#pragma mark - UI Actions

-(IBAction)selectFormat:(id)sender
{
    if (sender == formatListPopUp) {
        MTFormatPopUpButton *thisButton = (MTFormatPopUpButton *)sender;
        [tiVoManager setValue:[[thisButton selectedItem] representedObject] forKey:@"selectedFormat"];
    } else {
        MTFormatPopUpButton *thisButton = (MTFormatPopUpButton *)sender;
        if ([thisButton.owner class] == [MTSubscription class]) {
            MTSubscription * subscription = (MTSubscription *) thisButton.owner;
            
            subscription.encodeFormat = [tiVoManager findFormat:[thisButton selectedItem].title];
			[[NSNotificationCenter defaultCenter] postNotificationName: kMTNotificationSubscriptionChanged object:subscription];
       } else if ([thisButton.owner class] == [MTDownload class]) {
            MTDownload * download = (MTDownload *) thisButton.owner;
           if(download.isNew) {
                download.encodeFormat = [tiVoManager findFormat:[thisButton selectedItem].title];
            }
          [[NSNotificationCenter defaultCenter] postNotificationName: kMTNotificationDownloadRowChanged object:download];
       }
     }
}

#pragma mark - Menu Delegate

-(BOOL)validateMenuItem:(NSMenuItem *)menuItem {
	if ([menuItem action]==@selector(copy:) ||
		[menuItem action]==@selector(subscribe:) ||
		[menuItem action]==@selector(showDetails:) ||
		[menuItem action]==@selector(reloadAllInfo:) ||
		[menuItem action]==@selector(downloadSelectedShows:)) {
		
		MTProgramTableView * table = self.tiVoShowTable; //default; could also be download or subscribe; must have actionItems property
		if ([self.window.firstResponder isKindOfClass:[NSTableView class]]) table = (MTProgramTableView *) self.window.firstResponder;
		return (table.actionItems.count > 0);
	}
	if ([menuItem action]==@selector(revealInNowPlaying:)) {
		NSArray <MTDownload *> * downloads = self.downloadQueueTable.actionItems;
		for (MTDownload * download in downloads) {
			if (download.downloadStatus.intValue != kMTStatusDeleted) {
				return YES;
			}
		}
		return NO;
	}
	BOOL deleteItem =  menuItem.action == @selector(deleteOnTiVo:);
	BOOL playItem =  menuItem.action == @selector(playOnTiVo:);
	BOOL stopItem =    menuItem.action == @selector(stopRecordingOnTiVo:);
	BOOL getSkipItem = menuItem.action == @selector(skipInfoFromTiVo:);
	if (deleteItem ||playItem || stopItem || getSkipItem) {
		if (deleteItem) menuItem.title = @"Delete from TiVo"; //alternates with remove from Queue
		NSArray	*selectedShows = [self selectedShows ];
		for (MTTiVoShow * show in selectedShows) {
			if (show.rpcData && show.tiVo.rpcActive && ! [show.imageString isEqualToString:@"Deleted"]) {
				if (stopItem) {
					if (show.inProgress.boolValue) return YES;
				} else if (getSkipItem) {
					if (show.hasSkipModeInfo && !show.hasSkipModeList && !show.skipModeFailed) return YES;
				} else {
					return YES;
				}
			}
		}
		return NO;
	} else if (menuItem.action == @selector(revealInFinder:) ||
			   menuItem.action == @selector(playVideo:)) {
        return [self selectionContainsCompletedShows];
	} else if ([menuItem.title rangeOfString:@"refresh" options:NSCaseInsensitiveSearch].location != NSNotFound) {
		if (tiVoManager.tiVoList.count > 1) {
			menuItem.title = @"Refresh this TiVo";
		} else {
			menuItem.title = @"Refresh TiVo";
		}
	} else 	if (menuItem.action == @selector(reportTiVoInfo:)) {
		return (tiVoManager.tiVoList.count >= 1);
	}

    return YES;
}

- (void) openDrawer:(MTTiVoShow *) show {
	if (show) {		
		self.showForDetail = show;
		[showDetailDrawer open];
    }
}

-(IBAction) reportTiVoInfo: (NSView *) sender {
	if (tiVoManager.tiVoList.count >= 1) return;
	
	MTTiVo * candidate = tiVoManager.tiVoList[0];
	if (tiVoManager.tiVoList.count > 1 &&
		![self.selectedTiVo isEqualToString:kMTAllTiVos]) {
		for (MTTiVo *targetTiVo in tiVoManager.tiVoList) {
			if ([targetTiVo.tiVo.name isEqualToString: self.selectedTiVo] ) {
				candidate = targetTiVo;
				break;
			}
		}
	}
	if (!candidate.rpcActive)  return;
	
	__weak NSProgressIndicator * weakSpinner = loadingProgramListIndicator;
	__weak __typeof__(self) weakSelf = self;

	[weakSpinner startAnimation:nil];

	[candidate tiVoInfoWithCompletion:^(NSString *status) {
		__typeof__(self) strongSelf = weakSelf;
		if (strongSelf.loadingTiVos.count + strongSelf.commercialingTiVos.count == 0) {
			//otherwise our regular process will turn off.
			[weakSpinner stopAnimation:nil];
		}
		if (status) {
			NSAlert *alert = [[NSAlert alloc] init];
			NSString * name = candidate.tiVo.name ?:@"Unknown name";
			[alert setMessageText:name];
			[alert setInformativeText:status];
			[alert addButtonWithTitle:@"OK"];
			[alert setAlertStyle:NSAlertStyleInformational];

			[alert beginSheetModalForWindow:strongSelf.window completionHandler:^(NSModalResponse returnCode) {
				}];
		}
	}];
}

-(NSArray <MTTiVoShow *> *) showsForDownloads:(NSArray <MTDownload *> *) downloads includingDone: (BOOL) includeDone {
    NSMutableArray <MTTiVoShow *> * shows = [NSMutableArray array];
    for (MTDownload * download in downloads) {
		if ((includeDone || !download.isCompletelyDone) && ![shows containsObject:download.show]) {
			[shows addObject:download.show];
		}
    }
    return [shows copy];
}

-(NSArray <MTTiVoShow *> *) selectedShows {
	if (self.window.firstResponder == self.downloadQueueTable) {
		return [self showsForDownloads:downloadQueueTable.actionItems includingDone:YES];
	} else {
		return [self.tiVoShowTable actionItems];
	}
}

-(IBAction) stopRecordingOnTiVo: (id) sender {
	NSArray <MTTiVoShow *> * theseShows  = [self selectedShows];
	NSArray * recordingShows =  [theseShows mapObjectsUsingBlock:^id(MTTiVoShow * show, NSUInteger idx) {
		if (show.inProgress.boolValue) {
			return show;
		} else {
			return nil;
		}
	}];
	if (recordingShows.count == 0) return;
	if ([self confirmBehavior:@"stop recording" preposition:@"on" forShows:recordingShows]) {
		[tiVoManager stopRecordingShows:recordingShows];
	}
}

-(IBAction) deleteOnTiVo: (id) sender {
	NSArray <MTTiVoShow *> * theseShows  = [self selectedShows];
	if (theseShows.count == 0) return;
	if ([self confirmBehavior:@"delete" preposition: @"from" forShows:theseShows]) {
		[tiVoManager deleteTivoShows:theseShows];
	}
}

-(IBAction) playOnTiVo: (id) sender {
	NSArray <MTTiVoShow *> * theseShows = [self selectedShows];
	NSArray <MTTiVoShow *> * videoShows =  [theseShows mapObjectsUsingBlock:^id(MTTiVoShow * show, NSUInteger idx) {
		if (show.rpcData) {
			return show;
		} else {
			return nil;
		}
	}];

	if (videoShows.count  == 0) return;
	[videoShows[0].tiVo playShow:videoShows[0]];
}

-(IBAction)skipInfoFromTiVo:(id)sender {
	BOOL programTable = self.window.firstResponder != downloadQueueTable;
	NSString * object = programTable ? @"show" : @"download";
	NSArray <MTTiVoShow *>* selectedObjects = [[self selectedShows] mapObjectsUsingBlock:^MTTiVoShow *(MTTiVoShow * show, NSUInteger idx) {
		if (show.hasSkipModeInfo && !show.hasSkipModeList && !show.skipModeFailed) {
			return show;
		} else {
			return nil;
		}
	}];
	if (selectedObjects.count == 0) return;
	NSString * mainText = @"Warning: retrieving SkipMode data will temporarily interrupt current viewing on your TiVo!";
	NSString * infoText = selectedObjects.count > 1 ?
			[NSString stringWithFormat:@"Hit Ok to retrieve SkipMode data for %d %@s, or hit Cancel to cancel request.", (int) selectedObjects.count, object] :
			[NSString stringWithFormat:@"Hit Ok to retrieve SkipMode data for %@, or hit Cancel to cancel request.", selectedObjects[0].seriesTitle];
	NSAlert *myAlert = [NSAlert alertWithMessageText: mainText defaultButton:@"Ok" alternateButton:@"Cancel" otherButton:nil informativeTextWithFormat:@"%@", infoText];
	myAlert.alertStyle = NSCriticalAlertStyle;
	NSInteger result = [myAlert runModal];
	if (result == NSAlertAlternateReturn) return;

	NSArray <MTTiVoShow *> * shows = nil;
	if (result == NSAlertDefaultReturn) {
		shows = selectedObjects;
	}
	if (shows.count) [tiVoManager skipModeRetrieval:shows interrupting:YES];
}

-(IBAction)expireDateOnTiVo:(id)sender {
	DDLogReport(@"XXX NOT IMPLEMENTED YET");
}

-(IBAction)showDetails:(id)sender {
	NSArray <MTTiVoShow *> * theseShows  = [self selectedShows];
	if (theseShows.count  == 0) return;
	MTTiVoShow * thisShow = theseShows[0];
	[self openDrawer:thisShow];
}

-(IBAction)reloadAllInfo:(id)sender {
	for (MTTiVoShow * show in [self selectedShows]) {
		[show resetSourceInfo:YES];
	}
	NSIndexSet * columns = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0,self.tiVoShowTable.numberOfColumns)];
	[self.tiVoShowTable reloadDataForRowIndexes:[tiVoShowTable selectedRowIndexes] columnIndexes:columns];
}

-(IBAction)revealInFinder: (id) sender {
	if (self.window.firstResponder == downloadQueueTable) {
		[tiVoManager revealInFinderDownloads:self.downloadQueueTable.actionItems];
	} else {
		[tiVoManager revealInFinderShows:self.tiVoShowTable.actionItems];
	}
}

-(IBAction)revealInNowPlaying:(id)sender {
	NSArray <MTTiVoShow *> * shows = [tiVoManager showsForDownloads:self.downloadQueueTable.actionItems includingDone:YES];
	if (shows.count > 0) {
		[self.tiVoShowTable selectShows:shows];
		[self.window makeFirstResponder:self.tiVoShowTable];
	}
}

-(IBAction)playVideo: (id) sender {
	NSArray <MTTiVoShow *> * theseShows  = [self selectedShows];
	NSArray * videoShows =  [theseShows mapObjectsUsingBlock:^id(MTTiVoShow * show, NSUInteger idx) {
		if (show.isOnDisk) {
			return show;
		} else {
			return nil;
		}
	}];
	
	if (videoShows.count  == 0) return;
	[videoShows[0] playVideo];
}

-(IBAction)copy: (id) sender {
	NSArray	*selectedShows = [self selectedShows ];
	if (selectedShows.count > 0) {
		MTTiVoShow * firstShow = selectedShows[0];
		NSPasteboard * pboard = [NSPasteboard generalPasteboard];
		[pboard declareTypes:[firstShow writableTypesForPasteboard:pboard] owner:nil];
		[[NSPasteboard generalPasteboard] writeObjects:selectedShows];
	}
}

-(IBAction)delete:(id)sender {
	NSArray	<MTTiVoShow *> *selectedShows = [self selectedShows ];
	if (selectedShows.count > 0)
		if ([self confirmBehavior:@"delete" preposition: @"from" forShows:selectedShows]) {
			[tiVoManager deleteTivoShows:selectedShows];
		}
}

-(BOOL) confirmBehavior: (NSString *) behavior preposition:(NSString *) prep forShows:(NSArray <MTTiVoShow *> *) shows {
    NSString * msg = nil;
    if (shows.count == 1) {
        msg = [NSString stringWithFormat:@"Are you sure you want to %@ '%@' %@ TiVo %@?", behavior, shows[0].showTitle, prep, shows[0].tiVoName ];
    } else if (shows.count == 2) {
        msg = [NSString stringWithFormat:@"Are you sure you want to %@ '%@' and '%@' %@ your TiVo?",behavior, shows[0].showTitle, shows[1].showTitle, prep ];
    } else {
        msg = [NSString stringWithFormat:@"Are you sure you want to %@ '%@' and %d others %@ your TiVo?", behavior, shows[0].showTitle, (int)shows.count -1, prep ];
    }

    NSAlert *myAlert = [NSAlert alertWithMessageText:msg defaultButton:@"No" alternateButton:@"Yes" otherButton:nil informativeTextWithFormat:@"This cannot be undone from " kcTiVoName @"."];
    myAlert.alertStyle = NSCriticalAlertStyle;
    NSInteger result = [myAlert runModal];
    return (result == NSAlertAlternateReturn);
}

-(IBAction)doubleClickForDetails:(id)input {
	if (input==tiVoShowTable) {
		NSInteger rowNumber = [tiVoShowTable clickedRow];
		if (rowNumber != -1) {
			MTTiVoShow *thisShow = [tiVoShowTable itemAtRow:rowNumber];
			if ([thisShow isKindOfClass:[MTShowFolder class]]) {
				thisShow = ((MTShowFolder *)thisShow).folder[0];
			}
			[self openDrawer:thisShow];
		}
	}else if (input==downloadQueueTable) {
		NSInteger rowNumber = [downloadQueueTable clickedRow];
		if (rowNumber != -1) {
			MTDownload * download = [[downloadQueueTable sortedDownloads] objectAtIndex:rowNumber];
			[self openDrawer:download.show];
			if (!download.show.protectedShow.boolValue) {
				[tiVoManager revealInFinderDownloads:@[download]];
				[download playVideo];
			}
		}
	}
}

-(BOOL) selectionContainsCompletedShows {
	if ([self.window.firstResponder respondsToSelector:@selector(selectionContainsCompletedShows)]) {
		return [(MTProgramTableView *) self.window.firstResponder selectionContainsCompletedShows];
	} else{
		return NO;
	}
}

-(void) playTrashSound {
	if (!self.trashSound) {
		self.trashSound = [[NSSound alloc] initWithContentsOfFile:@"/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/dock/drag to trash.aif" byReference:YES];
	}
	[self.trashSound play];
}

#pragma mark - Subscription Buttons

-(IBAction)subscribe:(id) sender {
	[tiVoManager.subscribedShows addSubscriptionsShows:[self selectedShows]];
}

#pragma mark - Download Buttons

-(IBAction)downloadSelectedShows:(id)sender {
	[tiVoManager downloadShowsWithCurrentOptions:[tiVoShowTable actionItems] beforeDownload:nil];
    
	[downloadQueueTable deselectAll:nil];
}

-(IBAction)dontQuit:(id)sender {
	DDLogDetail(@"User canceled Quit after processing");
    [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationUserCanceledQuit object:nil ];
}

-(IBAction)getDownloadDirectory:(id)sender {
	[(MTAppDelegate *)[NSApplication sharedApplication].delegate promptForNewDirectory:tiVoManager.downloadDirectory
																		   withMessage:@"Choose Directory for Download of Videos"
																			 isProblem:NO
																			 isTempDir:NO];
}

#pragma mark - Download Options

-(IBAction)changeSkip:(id)sender {
    MTCheckBox *checkbox = sender;
	if ([checkbox.owner isKindOfClass:[MTDownload class]]){
		MTDownload *download = (MTDownload *)(checkbox.owner);
        download.skipCommercials = ! download.skipCommercials;
        [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationDownloadRowChanged object:download];
    } else if ([checkbox.owner isKindOfClass:[MTSubscription class]]){
        MTSubscription *sub = (MTSubscription *)(checkbox.owner);
		sub.skipCommercials = @( ! sub.skipCommercials.boolValue);
		[[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationSubscriptionChanged object:sub];
    }
}

-(IBAction)changeUseTS:(id)sender {
	MTCheckBox *checkbox = sender;
	if ([checkbox.owner isKindOfClass:[MTDownload class]]){
		MTDownload *download = (MTDownload *)(checkbox.owner);
		download.useTransportStream = @(! download.useTransportStream.boolValue);
		[[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationDownloadRowChanged object:download];
	}
}

-(IBAction)changeMark:(id)sender {
    MTCheckBox *checkbox = sender;
	if ([checkbox.owner isKindOfClass:[MTDownload class]]){
		MTDownload *download = (MTDownload *)(checkbox.owner);
        download.markCommercials = ! download.markCommercials;
        [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationDownloadRowChanged object:download];
    } else if ([checkbox.owner isKindOfClass:[MTSubscription class]]){
        MTSubscription *sub = (MTSubscription *)(checkbox.owner);
		sub.markCommercials = @( ! [sub.markCommercials boolValue]);
		[[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationSubscriptionChanged object:sub];
    }
}
-(IBAction)changeUseSkipMode:(id)sender
{
	MTCheckBox *checkbox = sender;
	if ([checkbox.owner isKindOfClass:[MTDownload class]]){
		MTDownload *download = (MTDownload *)(checkbox.owner);
		download.useSkipMode = ! download.useSkipMode;
		[[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationDownloadRowChanged object:download];
	} else if ([checkbox.owner isKindOfClass:[MTSubscription class]]){
		MTSubscription *sub = (MTSubscription *)(checkbox.owner);
		sub.useSkipMode = @(! sub.useSkipMode.boolValue);
		[[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationSubscriptionChanged object:sub];
	}
}

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

-(IBAction)changeDelete:(id)sender
{
	MTCheckBox *checkbox = sender;
	if ([checkbox.owner isKindOfClass:[MTDownload class]]){
		//updating an individual show in download queue
		MTDownload * download = (MTDownload *)checkbox.owner;
		NSNumber *newVal = @( ! download.deleteAfterDownload.boolValue);
		download.deleteAfterDownload = newVal;
	} else if ([checkbox.owner isKindOfClass:[MTSubscription class]]){
		MTSubscription *sub = (MTSubscription *)(checkbox.owner);
		NSNumber *newVal = @( ! sub.deleteAfterDownload.boolValue );
		sub.deleteAfterDownload = newVal;
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
            [item setRepresentedObject:column];
            [item setState:column.isHidden?NSOffState: NSOnState];
        }
	}
}


- (void)contextMenuSelected:(id)sender {
	NSMenuItem * menuItem = (NSMenuItem *) sender;
    NSTableColumn *column = [menuItem representedObject];
	BOOL wasOn = ([menuItem state] == NSOnState);
	if (wasOn &&
		column == self.tiVoShowTable.outlineTableColumn &&
		[[NSUserDefaults standardUserDefaults] boolForKey:kMTShowFolders]) {
		//apparently user wants to switch outline columns

		NSTableColumn * combo = [self.tiVoShowTable tableColumnWithIdentifier: @"Programs"];
		NSTableColumn * series = [self.tiVoShowTable tableColumnWithIdentifier: @"Series"];
		if (column == series) {
			combo.hidden = NO;
			self.tiVoShowTable.outlineTableColumn = combo;
		} else {
			series.hidden = NO;
			self.tiVoShowTable.outlineTableColumn = series;
		}
		NSMenu * thisMenu = [menuItem menu];
		NSInteger outlineIndex = [thisMenu indexOfItemWithRepresentedObject:self.tiVoShowTable.outlineTableColumn];
	    if (outlineIndex != NSNotFound) {
			NSMenuItem * outlineMenuItem = [thisMenu itemAtIndex:outlineIndex];
			[outlineMenuItem setState:NSOnState];
		}
	}
	[column setHidden:wasOn];
	if(wasOn) {
		[menuItem setState: NSOffState ];
	} else {
		[menuItem setState: NSOnState];
	}
    if ([[column tableView] respondsToSelector:@selector(columnChanged:)]) {
        [[column tableView] performSelector:@selector(columnChanged:) withObject:column];
    }
}

#pragma mark - Memory Management

-(void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [tiVoManager removeObserver:self forKeyPath:@"selectedFormat"];
	[[NSUserDefaults standardUserDefaults] removeObserver:self forKeyPath:kMTIfSuccessDeleteFromTiVo];
}


#pragma mark - Split View Delegate
- (CGFloat)splitView:(NSSplitView *)splitView constrainMinCoordinate:(CGFloat)proposedMin ofSubviewAt:(NSInteger)dividerIndex {
	//all three tables have same minimum
	return proposedMin + 120;
}

- (CGFloat)splitView:(NSSplitView *)splitView constrainMaxCoordinate:(CGFloat)proposedMaximumPosition ofSubviewAt:(NSInteger)dividerIndex
{
    return proposedMaximumPosition - 120;
}
@end
