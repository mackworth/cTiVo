//
//  MTSubscriptionList.h
//  myTivo
//
//  Created by Scott Buchanan on 12/7/12.
//  Copyright (c) 2012 Scott Buchanan. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "MTNetworkTivos.h"

@interface MTSubscriptionList : NSTableView <NSTableViewDataSource, NSTableViewDelegate> {
    IBOutlet NSWindowController *myController;
}


-(BOOL) isSubscribed:(MTTiVoShow *) tivoShow;

-(void) addSubscription:(MTTiVoShow *) tivoShow;
//-(void) removeSubscription:(NSString *) seriesName;

-(IBAction) unsubscribeSelectedItems:(id) sender;

@property (nonatomic, assign) NSMutableArray *subscribedShows;
@property (assign) IBOutlet NSButton *unsubscribeButton;

@end
