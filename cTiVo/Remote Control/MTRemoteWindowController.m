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
@property (nonatomic, readonly) MTTiVo * selectedTiVo;
@property (nonatomic, weak) IBOutlet NSImageView * tivoRemote;
@end

@implementation MTRemoteWindowController

-(instancetype) init {
	if ((self = [self initWithWindowNibName:@"MTRemoteWindowController"])) {
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateTiVoList) name:kMTNotificationTiVoListUpdated object:nil];
        self.window.contentAspectRatio = self.tivoRemote.image.size;
    };
	return self;
}

-(MTTiVo *) selectedTiVo {
	MTTiVo* tivo = nil;
	if (self.tiVoList.count > 0) {
		NSInteger index = MIN(MAX(self.tivoListPopup.indexOfSelectedItem,0), ((NSInteger) self.tiVoList.count)-1);
		tivo = self.tiVoList[index];
	}
	return tivo;
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

-(IBAction)netflixButton:(NSButton *) sender {
	[self.selectedTiVo sendURL: @"x-tivo:netflix:netflix"];
}


-(IBAction)buttonPressed:(NSButton *)sender {
	if (!sender.title) return;
	[self.selectedTiVo sendKeyEvent: sender.title];
}

-(void) dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
