//
//  MTManualTiVoEditor.h
//  cTiVo
//
//  Created by Scott Buchanan on 1/25/13.
//  Copyright (c) 2013 Scott Buchanan. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface MTManualTiVoEditorController : NSWindowController {
	IBOutlet NSArrayController *arrayController;
}

@property (nonatomic, retain) NSMutableArray *manualTiVoList;

-(IBAction)logArray:(id)sender;

@end
