//
//  MTAppDelegate.h
//  myTivo
//
//  Created by Scott Buchanan on 12/6/12.
//  Copyright (c) 2012 Scott Buchanan. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "MTTiVoManager.h"
@class MTRemoteWindowController;

@interface MTAppDelegate : NSObject <NSApplicationDelegate, NSTableViewDataSource, NSTableViewDelegate, NSPopoverDelegate, NSOpenSavePanelDelegate> 

@property (nonatomic, strong) MTRemoteWindowController  *remoteControlWindowController;

-(BOOL)checkForExit;

-(NSArray <MTTiVoShow*> *)currentSelectedShows; //used for test purposes
-(void) promptForNewDirectory:(NSString *) oldDir withMessage: (NSString *) message isProblem: (BOOL) problem isTempDir:(BOOL) temp; //used by Preferences

@end
