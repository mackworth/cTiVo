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

#import "MTFormatPopUpButton.h"
#import "MTCheckBox.h"
#import "MTTiVo.h"
#import "MTTVDB.h"

#import <Quartz/Quartz.h>

//All this mess is just to avoid the error msg that "Drawer cannot have first responder of MTProgramTableView"
//remove if we move from Drawer to splitView or expanded Row concept
@interface NSWindow (FirstResponding)
-(void)_setFirstResponder:(NSResponder *)responder;
@end
@interface NSDrawerWindow : NSWindow
@end
@implementation NSDrawerWindow (avoidWarning)

-(void) _setFirstResponder:(NSView *) view {
	if (![view isKindOfClass:[NSTableView class]]) {
		[super _setFirstResponder:view];
	}
}
@end

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

@interface MTMainWindowController ()

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
	if ([keyPath compare:@"selectedFormat"] == NSOrderedSame) {
        [formatListPopUp selectFormat:[tiVoManager selectedFormat]];
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
-(NSMutableAttributedString *) stringForDisplay: (NSSet <MTTiVo *> *) set withAttributes: (nullable NSDictionary<NSAttributedStringKey,id> *) attribs {
	NSString * list = [[[[set allObjects] valueForKeyPath:@"tiVo.name" ] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)] componentsJoinedByString:@", "];
 return [[NSMutableAttributedString alloc] initWithString: list
attributes:attribs];
}

-(void)manageLoadingIndicator:(NSNotification *)notification
{
	if (!notification) { //Don't accept nil notifications
		return;  
	}
    MTTiVo * tivo = (MTTiVo *) notification.object;
    if (!tivo) return;
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
	if (self.loadingTiVos.count + self.commercialingTiVos.count > 0) {
        [loadingProgramListIndicator startAnimation:nil];
		NSMutableAttributedString *message =  [[NSMutableAttributedString alloc] init];
		if (self.loadingTiVos.count > 0) {
			[message appendAttributedString:[[NSMutableAttributedString alloc] initWithString:@"Updating "]];
			[message appendAttributedString:[self stringForDisplay:self.loadingTiVos withAttributes:@{}]];
			if (self.commercialingTiVos.count > 0) {
				[message appendAttributedString:[[NSMutableAttributedString alloc] initWithString:@", "]];
			}
		}
		if (self.commercialingTiVos.count > 0) {
			NSDictionary *redAttrs    = @{NSForegroundColorAttributeName:[NSColor redColor]};
			[message appendAttributedString:[[NSMutableAttributedString alloc] initWithString:@"Getting SkipMode for " attributes:redAttrs ]];
			 [message appendAttributedString:[self stringForDisplay:self.commercialingTiVos withAttributes:redAttrs]];
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
            NSAttributedString *aTitle = [[NSAttributedString alloc] initWithString:thisTitle attributes:[NSDictionary dictionaryWithObjectsAndKeys:[NSColor redColor], NSForegroundColorAttributeName, thisFont, NSFontAttributeName, nil]];
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
            NSAttributedString *aTitle = [[NSAttributedString alloc] initWithString:thisTitle attributes:[NSDictionary dictionaryWithObjectsAndKeys:[NSColor redColor], NSForegroundColorAttributeName, thisFont, NSFontAttributeName, nil]];
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
       } else if ([thisButton.owner class] == [MTDownload class]) {
            MTDownload * download = (MTDownload *) thisButton.owner;
           if(download.isNew) {
                download.encodeFormat = [tiVoManager findFormat:[thisButton selectedItem].title];
            }
          [[NSNotificationCenter defaultCenter] postNotificationName: kMTNotificationDownloadStatusChanged object:download];
       }
     }
}

#pragma mark - Menu Delegate

-(BOOL)validateMenuItem:(NSMenuItem *)menuItem {
	if (menuItem == _showInFinderMenuItem || menuItem == _playVideoMenuItem) {
        return [self selectionContainsCompletedShows];
	} else if ([menuItem.title rangeOfString:@"refresh" options:NSCaseInsensitiveSearch].location != NSNotFound) {
		if (tiVoManager.tiVoList.count > 1) {
			menuItem.title = @"Refresh this TiVo";
		} else {
			menuItem.title = @"Refresh TiVo";
		}
	}
    return YES;
}

-(void)menuWillOpen:(NSMenu *)menu
{
	menuCursorPosition = [self.window mouseLocationOutsideOfEventStream];
	NSTableView *workingTable = nil;
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
		if (menuTableRow < 0) { //disable row/RPC functions  Row based functions have tag=1 or 2; ROC 3 or 4
			for (NSMenuItem *mi in [menu itemArray]) {
				if (mi.tag >= 1 && mi.tag <= 4) {
					[mi setAction:NULL];
				}
			}
		} else {
			if (![[workingTable selectedRowIndexes] containsIndex:menuTableRow] ) {
				[workingTable selectRowIndexes:[NSIndexSet indexSetWithIndex:menuTableRow] byExtendingSelection:NO];
			}
			if (workingTable == downloadQueueTable) {
				MTDownload *thisDownload = downloadQueueTable.sortedDownloads[menuTableRow];
				//disable menu items that depend on having a completed show tag = 2
				if (!thisDownload.canPlayVideo) {
					for (NSMenuItem *mi in [menu itemArray]) {
						if (mi.tag == 2 ) {
							[mi setAction:NULL];
						}
					}
				}
			}
			if (workingTable == tiVoShowTable) {
				MTTiVoShow *thisShow = [tiVoShowTable itemAtRow:menuTableRow];
				if ([thisShow isKindOfClass:[MTShowFolder class]]) {
					thisShow = ((MTShowFolder *)thisShow).folder[0];
				}
				//diasble menu items that depend on having a completed show tag = 2
				if (!thisShow.isOnDisk) {
					for (NSMenuItem *mi in [menu itemArray]) {
						if (mi.tag == 2 ) {
							[mi setAction:NULL];
						}
					}
				}
                if (! thisShow.tiVo.rpcActive || !thisShow.rpcData) {
                    //RPC tags = 3 or 4
                    for (NSMenuItem *mi in [menu itemArray]) {
                        if (mi.tag == 3 || mi.tag == 4) {
                            [mi setAction:NULL];
                        }
                    }
                }
                if (!thisShow.inProgress.boolValue ) {
                    for (NSMenuItem *mi in [menu itemArray]) {
                        //In progress required = 4 (stop recording)
                        if (mi.tag == 4 ) {
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
    }
}

-(NSArray <MTTiVoShow *> *) showsForDownloads:(NSArray <MTDownload *> *) downloads {
    NSMutableArray <MTTiVoShow *> * shows = [NSMutableArray array];
    for (MTDownload * download in downloads) {
		if (!download.isCompletelyDone) {
			[shows addObject:download.show];
		}
    }
    return [shows copy];
}

-(void) confirmSkipModeRetrieval: (BOOL) programTable {
    NSString * object = programTable ? @"show" : @"download";
    NSArray * selectedObjects = programTable ? [self.tiVoShowTable selectedShows] : [self.downloadQueueTable.sortedDownloads objectsAtIndexes: self.downloadQueueTable.selectedRowIndexes];
    NSString * plural = selectedObjects.count > 1 ? @"s" : @"";
    NSAlert *myAlert = [NSAlert alertWithMessageText:[NSString stringWithFormat:@"Warning: pulling SkipMode information from TiVo will temporarily interrupt current viewing on your TiVo!"] defaultButton:@"Selected" alternateButton:@"Cancel" otherButton:@"All" informativeTextWithFormat:@"Press Selected to continue with Selected %@%@, All to continue for ALL %@s, or Cancel to cancel request.", object, plural, object];
    myAlert.alertStyle = NSCriticalAlertStyle;
    NSInteger result = [myAlert runModal];
    NSArray <MTTiVoShow *> * shows = nil;
    if (result == NSAlertAlternateReturn) return;
    if (result == NSAlertDefaultReturn) {
        if (programTable) {
            shows = selectedObjects;
        } else {
            shows = [self showsForDownloads: selectedObjects] ;
        }
    } else if (result == NSAlertOtherReturn) {
        if (programTable) {
            shows = self.tiVoShowTable.displayedShows;
        } else {
           shows =  [self showsForDownloads: self.downloadQueueTable.sortedDownloads];
        }
    }
    if (shows.count) [tiVoManager skipModeRetrieval:shows interrupting:YES];
}

-(IBAction)programMenuHandler:(NSMenuItem *)menu
{
	if ([menu.title caseInsensitiveCompare:@"Download"] == NSOrderedSame) {
		[self downloadSelectedShows:menu];
	} else if ([menu.title caseInsensitiveCompare:@"Subscribe to series"] == NSOrderedSame) {
		[self subscribe:menu];
    } else if ([menu.title caseInsensitiveCompare:@"Reload TVDB Info"] == NSOrderedSame) {
        for (MTTiVoShow * show in [tiVoShowTable selectedShows]) {
            [show resetSourceInfo:YES];
        }
        NSIndexSet * columns = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0,self.tiVoShowTable.numberOfColumns)];
        [self.tiVoShowTable reloadDataForRowIndexes:[tiVoShowTable selectedRowIndexes] columnIndexes:columns];
	} else if ([menu.title caseInsensitiveCompare:@"Find SkipMode Points"] == NSOrderedSame) {
		[self confirmSkipModeRetrieval:YES];
    } else if (menuTableRow >= 0 && //somehow happens
               menuTableRow < tiVoShowTable.numberOfRows) {
		MTTiVoShow *thisShow = [tiVoShowTable itemAtRow:menuTableRow];
		NSArray <MTTiVoShow *> * theseShows = @[thisShow];
		if ([thisShow isKindOfClass:[MTShowFolder class]]) {
			theseShows = ((MTShowFolder *)thisShow).folder;
			if (theseShows.count) {
				thisShow = theseShows[0];
			} else {
				return;
			}
		}
       if ([menu.title caseInsensitiveCompare:@"Show Details"] == NSOrderedSame) {
            [self openDrawer:thisShow];
        } else if ([menu.title caseInsensitiveCompare:@"Play Video"] == NSOrderedSame) {
            //Eventually if more than 1 download present will open up choice alert (or extend menu with a right pull)
            //For now just play the first
            if (thisShow.isOnDisk) {
                [thisShow playVideo:[thisShow copiesOnDisk][0]];
            }
        } else if ([menu.title caseInsensitiveCompare:@"Show in Finder"] == NSOrderedSame) {
            if (thisShow.isOnDisk) {
                [thisShow revealInFinder:[thisShow copiesOnDisk]];
            }
        } else if ([menu.title caseInsensitiveCompare:@"Delete From TiVo"] == NSOrderedSame) {
            if ([self confirmBehavior:@"delete" preposition: @"from" forShows:theseShows]) {
                [tiVoManager deleteTivoShows:theseShows];
            }
        } else if ([menu.title caseInsensitiveCompare:@"Stop Recording"] == NSOrderedSame) {
            if ([self confirmBehavior:@"stop recording" preposition:@"on" forShows:theseShows]) {
                [tiVoManager stopRecordingShows:theseShows];
            }
        }
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

    NSAlert *myAlert = [NSAlert alertWithMessageText:msg defaultButton:@"No" alternateButton:@"Yes" otherButton:nil informativeTextWithFormat:@"This cannot be undone."];
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
				[download revealInFinder];
				[download playVideo];
			}
		}
	}
}


-(IBAction)downloadMenuHandler:(NSMenuItem *)menu
{
	DDLogMajor(@"User specified to %@",menu.title);
	if ([menu.title caseInsensitiveCompare:@"Remove from Queue"] == NSOrderedSame) {
		[self removeFromDownloadQueue:menu];
	} else if ([menu.title caseInsensitiveCompare:@"Reschedule"] == NSOrderedSame) {
		NSIndexSet *selectedRows = [downloadQueueTable selectedRowIndexes];
		NSArray *itemsToReschedule = [downloadQueueTable.sortedDownloads objectsAtIndexes:selectedRows];
		if ([tiVoManager.processingPaused boolValue]) {
			for (MTDownload *download in itemsToReschedule) {
                if (!download.show.protectedShow.boolValue && download.downloadStatus.intValue != kMTStatusDeleted) {
					[download prepareForDownload:YES];
                }
			}
		} else {
			//Can't reschedule items that haven't loaded yet or have been deleted.
			NSMutableArray * realItemsToReschedule = [NSMutableArray arrayWithArray:itemsToReschedule];
			for (MTDownload *download in itemsToReschedule) {
				if (download.show.protectedShow.boolValue || download.downloadStatus.intValue == kMTStatusDeleted) {
					//A proxy DL waiting for "real" show
					[download prepareForDownload:YES];
					[realItemsToReschedule removeObject:download];
				}
			}
			[tiVoManager deleteFromDownloadQueue:realItemsToReschedule];
			[tiVoManager addToDownloadQueue:realItemsToReschedule beforeDownload:nil];
		}
	} else if ([menu.title caseInsensitiveCompare:@"Subscribe to series"] == NSOrderedSame) {
		NSArray * selectedDownloads = [downloadQueueTable.sortedDownloads objectsAtIndexes:downloadQueueTable.selectedRowIndexes];
		[tiVoManager.subscribedShows addSubscriptionsDL:selectedDownloads];
    } else if ([menu.title caseInsensitiveCompare:@"Find SkipMode Points"] == NSOrderedSame) {
        [self confirmSkipModeRetrieval:NO];
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
	if (self.window.firstResponder == self.tiVoShowTable) {
		return [self.tiVoShowTable selectionContainsCompletedShows ] ;
	} else if (self.window.firstResponder == self.downloadQueueTable) {
    	return [self.downloadQueueTable selectionContainsCompletedShows ] ;
	} else {
		return NO;
	}
}

-(IBAction)revealInFinder: (id) sender {
	if (self.window.firstResponder == self.tiVoShowTable) {
		[self.tiVoShowTable revealInFinder];
	} else {
		[self.downloadQueueTable revealInFinder];
	}
}

-(IBAction)playVideo: (id) sender {
	if (self.window.firstResponder == self.tiVoShowTable) {
		[self.tiVoShowTable playVideo];
	} else {
		[self.downloadQueueTable playVideo];
	}
}

-(void) playTrashSound {
	if (!self.trashSound) {
		self.trashSound = [[NSSound alloc] initWithContentsOfFile:@"/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/dock/drag to trash.aif" byReference:YES];
	}
	[self.trashSound play];
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
	[tiVoManager.subscribedShows addSubscriptionsShows:[tiVoShowTable selectedShows]];
}

#pragma mark - Download Buttons

-(IBAction)downloadSelectedShows:(id)sender
{
	[tiVoManager downloadShowsWithCurrentOptions:[tiVoShowTable selectedShows] beforeDownload:nil];
    
	[downloadQueueTable deselectAll:nil];
}

-(IBAction)dontQuit:(id)sender {
	DDLogDetail(@"User canceled Quit after processing");
    [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationUserCanceledQuit object:nil ];
}

-(BOOL) confirmCancel:(NSString *) title {
    NSAlert *myAlert = [NSAlert alertWithMessageText:[NSString stringWithFormat:@"Do you want to cancel active download of '%@'?",title] defaultButton:@"No" alternateButton:@"Yes" otherButton:nil informativeTextWithFormat:@" "];
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
        if ((download.isInProgress || download.downloadStatus.intValue == kMTStatusSkipModeWaitEnd) && download.downloadStatus.intValue != kMTStatusWaiting) {
            //if just waiting on TiVo, go ahead w/o confirmation
            if( ![self confirmCancel:download.show.showTitle]) {
                //if any cancelled, cancel the whole group
                return;
            }
        }
    }
	for (MTDownload * download in itemsToRemove) {
		if (download.isInProgress) [download cancel];
	}
	[tiVoManager deleteFromDownloadQueue:itemsToRemove];
	if (itemsToRemove.count)[self playTrashSound];

 	[downloadQueueTable deselectAll:nil];
}

-(IBAction)getDownloadDirectory:(id)sender {
	[(MTAppDelegate *)[NSApplication sharedApplication].delegate promptForNewDirectory:tiVoManager.downloadDirectory
																		   withMessage:@"Choose Directory for Download of Videos"
																			 isProblem:NO
																			 isTempDir:NO];
}

#pragma mark - Download Options

-(IBAction)changeSkip:(id)sender
{
    MTCheckBox *checkbox = sender;
	if ([checkbox.owner isKindOfClass:[MTDownload class]]){
		MTDownload *download = (MTDownload *)(checkbox.owner);
        download.skipCommercials = ! download.skipCommercials;
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
		[[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationSubscriptionChanged object:sub];
                
    }
}

-(IBAction)changeMark:(id)sender
{
    MTCheckBox *checkbox = sender;
	if ([checkbox.owner isKindOfClass:[MTDownload class]]){
		MTDownload *download = (MTDownload *)(checkbox.owner);
        download.markCommercials = ! download.markCommercials;
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
