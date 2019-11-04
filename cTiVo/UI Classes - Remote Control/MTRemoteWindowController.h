//
//  MTRemoteWindowController
//  cTiVo
//
//  Created by Hugh Mackworth on 2/6/18.
//  Copyright © 2018 cTiVo. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <MTTiVo.h>
@interface MTRemoteWindowController <NSWindowDelegate> : NSWindowController

@property (nonatomic, readonly) NSArray <MTTiVo *> * tiVoList;

-(IBAction)buttonPressed:(NSButton *)sender;
-(IBAction)netflixButton:(NSButton *) sender;

@end
