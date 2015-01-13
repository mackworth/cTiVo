//
//  MTTivoPopUpButton
//  cTiVo
//
//  Created by Hugh Mackworth on 1/4/13.
//  Copyright (c) 2013 Hugh Mackworth. All rights reserved.
//

#import "MTTiVoPopUpButton.h"
#import "MTTiVoManager.h"
@interface MTTiVoPopUpButton () {
	
}
@property (nonatomic, strong) NSArray *sortDescriptors;

@end

@implementation MTTiVoPopUpButton

-(MTTiVoPopUpButton *) initWithFrame:(NSRect) rect pullsDown:(BOOL)flag {
	if ((self = [super initWithFrame:rect pullsDown:flag])) {
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshMenu) name:kMTNotificationTiVoListUpdated object:nil];

	}
	return self;
}

-(void) setCurrentTivo: (NSString *) currentTivo {
	_currentTivo = currentTivo;
	[self selectItemWithTitle: currentTivo];
	[self refreshMenu];
}

-(void) refreshMenu {
	NSString * currSelection = (NSString *)self.selectedItem.representedObject;
	if (!currSelection) currSelection = _currentTivo;
	[self removeAllItems];
	[self addItemWithTitle:@"Any TiVo"];
	NSMenuItem * anyTivo = [self lastItem];
	anyTivo.RepresentedObject = @"";
	NSMenuItem *separator = [NSMenuItem separatorItem];
	[[self menu] addItem:separator];


	for (MTTiVo * tiVo in tiVoManager.tiVoList) {
		NSString * tiVoName = tiVo.tiVo.name;
		[self addItemWithTitle:tiVoName];
		NSMenuItem *thisItem = [self lastItem];
		
		thisItem.RepresentedObject = tiVoName;
		
		if ( [currSelection isEqualToString: tiVoName]) {
			[self selectItem:thisItem];
			currSelection = nil;
		}
	}
	if (currSelection) {
		if (currSelection.length == 0 || [currSelection isEqualToString:@"Any TiVo"]) {
			//name of @"" => any tivo
			[self selectItem:anyTivo]; 
		} else {
			//no longer in list, but it needs to be...
			[self addItemWithTitle:currSelection];
			NSMenuItem *thisItem = [self lastItem];
			thisItem.RepresentedObject = currSelection;
			[self selectItem:thisItem];
		}
	}
}

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];

}
@end
