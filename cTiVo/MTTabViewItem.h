//
//  MTTabViewItem.h
//  cTiVo
//
//  Created by Scott Buchanan on 1/27/13.
//  Copyright (c) 2013 Scott Buchanan. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@protocol MTTabViewItemControllerDelegate <NSObject>

@optional

-(BOOL)windowShouldClose:(id)sender;

@end


@interface MTTabViewItem : NSTabViewItem

@property (nonatomic, retain) IBOutlet id<MTTabViewItemControllerDelegate> windowController;

@end
