//
//  MTPopUpButton.h
//  cTiVo
//
//  Created by Scott Buchanan on 1/4/13.
//  Copyright (c) 2013 Scott Buchanan. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "MTTiVoManager.h"

@interface MTChannelPopUpButton : NSPopUpButton

@property (weak) id owner;
@property (nonatomic, strong) NSDictionary <NSString *, NSDictionary <NSString *, NSString *> *>  * channelList;
@property (nonatomic, strong) MTTiVo * selectedTiVo;

-(void) selectChannel: (NSString *) channel;

@end
