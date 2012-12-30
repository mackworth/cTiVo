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
#import "MTSubscriptionList.h"

@interface MTAppDelegate : NSObject <NSApplicationDelegate> {
	MTNetworkTivos *myTiVos;
	MTMainWindowController *mainWindowController;
}

@property (assign) IBOutlet NSWindow *window;

@end
