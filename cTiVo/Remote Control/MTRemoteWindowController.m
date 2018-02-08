//
//  NSViewController.m
//  cTiVo
//
//  Created by Hugh Mackworth on 2/6/18.
//  Copyright © 2018 cTiVo. All rights reserved.
//

#import "MTRemoteWindowController.h"
#import "MTTiVoManager.h"
#import "NSNotificationCenter+Threads.h"

@interface MTRemoteWindowController ()
@property (nonatomic, weak) IBOutlet NSPopUpButton * tivoListPopup;
@property (nonatomic, strong) NSArray <MTTiVo *> * tiVoList;

@end

@implementation MTRemoteWindowController

-(instancetype) init {
	if ((self = [self initWithWindowNibName:@"MTRemoteWindowController"])) {
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateTiVoList) name:kMTNotificationTiVoListUpdated object:nil];
			};
	return self;
}

-(void) updateTiVoList {
	NSMutableArray * newList = [NSMutableArray array];
	for (MTTiVo * tivo in [tiVoManager tiVoList]) {
		if (tivo.enabled && tivo.rpcActive) {
			[newList addObject:tivo];
		}
	}
	self.tiVoList = [newList copy];
}


-(IBAction)buttonPressed:(NSButton *)sender {
	MTTiVo* tivo = nil;
	if (self.tiVoList.count == 0) {
		return;
	} else {
		NSInteger index = MIN(MAX(self.tivoListPopup.indexOfSelectedItem,0), ((NSInteger) self.tiVoList.count)-1);
		tivo = self.tiVoList[index];
	}
	if (!sender.title) return;
	[tivo sendKeyEvents:@[sender.title]];
}

-(void) dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
