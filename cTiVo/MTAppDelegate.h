//
//  MTAppDelegate.h
//  myTivo
//
//  Created by Scott Buchanan on 12/6/12.
//  Copyright (c) 2012 Scott Buchanan. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "MTNetworkTivos.h"
#import "MTProgramList.h"
#import "MTDownloadList.h"
#import "MTMainWindowController.h"

@interface MTAppDelegate : NSObject <NSApplicationDelegate> {
//	IBOutlet NSPopUpButton *tivoList;
    IBOutlet MTProgramList *programList;
	IBOutlet MTDownloadList *downloadList;
//	IBOutlet NSProgressIndicator *downloadingProgress, *decryptingProgress, *encodingProgress;
//	IBOutlet NSTextField *downloadingLabel, *decriptingLabel, *encodingLabel;
	IBOutlet MTNetworkTivos *myTiVos;
	 MTMainWindowController *mainWindowController;
}

@property (assign) IBOutlet NSWindow *window;

@property (readonly, strong, nonatomic) NSPersistentStoreCoordinator *persistentStoreCoordinator;
@property (readonly, strong, nonatomic) NSManagedObjectModel *managedObjectModel;
@property (readonly, strong, nonatomic) NSManagedObjectContext *managedObjectContext;

@end
