//
//  MTHelpViewController.h
//  cTiVo
//
//  Created by Scott Buchanan on 1/14/13.
//  Copyright (c) 2013 Scott Buchanan. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "MTTabViewItem.h"

@interface MTHelpViewController : NSViewController <MTTabViewItemControllerDelegate>

@property (atomic, assign) CGSize preferredContentSize;

//context can come either by setting text or by loading from an RTF file in resources
@property (nonatomic) NSAttributedString * attributedString;
@property (nonatomic) NSString * text;

-(void) loadResource: (NSString *) rtfFile;

-(void) checkLinks; //marks any URLS in text 
-(void) pointToView:(NSView *) view preferredEdge: (NSRectEdge) edge;

@end
