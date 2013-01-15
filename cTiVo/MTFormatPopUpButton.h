//
//  MTPopUpButton.h
//  cTiVo
//
//  Created by Scott Buchanan on 1/4/13.
//  Copyright (c) 2013 Scott Buchanan. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "MTTiVoManager.h"

@interface MTFormatPopUpButton : NSPopUpButton

@property (retain) id owner;
@property (nonatomic, retain) NSArray * formatList;
@property (nonatomic, assign) BOOL showHidden;

-(void) refreshMenu;
-(MTFormat *) selectFormatNamed: (NSString *) newName;

@end
