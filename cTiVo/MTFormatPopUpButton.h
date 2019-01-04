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

@property (weak) id owner;
@property (nonatomic, strong) NSArray * formatList;
@property (nonatomic, assign) BOOL showHidden;

-(MTFormat *) selectFormat: (MTFormat *) format;

@end
