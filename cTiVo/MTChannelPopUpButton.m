//
//  MTPopUpButton.m
//  cTiVo
//
//  Created by Scott Buchanan on 1/4/13.
//  Copyright (c) 2013 Scott Buchanan. All rights reserved.
//

#import "MTChannelPopUpButton.h"
@interface MTChannelPopUpButton () {
	
}
@property (nonatomic, strong) NSArray *sortDescriptors;
@property (nonatomic, strong) NSString *preferredChannelName;
@end

@implementation MTChannelPopUpButton


-(void) sharedInit {
    self.preferredChannelName = @"";
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(channelMayHaveChanged) name:kMTNotificationChannelsChanged object:nil];
	[self channelMayHaveChanged];
}

-(instancetype) init {
    if ((self = [super init])) {
        [self sharedInit];
    }
    return self;
}

-(instancetype) initWithFrame:(NSRect)frameRect pullsDown:(BOOL)flag {
    if ((self = [super initWithFrame:frameRect pullsDown:flag])) {
        [self sharedInit];
    }
    return self;
}

-(void) awakeFromNib {
	[super awakeFromNib];
    [self sharedInit];
}

-(void) channelMayHaveChanged {
	if (self.selectedTiVo) {
		self.channelList = self.selectedTiVo.channelList;
	} else {
    	self.channelList =  [tiVoManager channelList ];
	}
	[self refreshMenu];
}

-(void)setChannelList:(NSDictionary <NSString *, NSDictionary <NSString *, NSString *> *>  *) channelList {
	if (![channelList isEqual:_channelList]) {
		_channelList = channelList;
        [self refreshMenu];
	}
}

-(void) selectChannel: (NSString *) channel {
    if (!channel) channel = @"";
	[self selectItem:nil];
    self.preferredChannelName = channel;
	if (channel.length == 0) {
		[self selectItemAtIndex:0];
	} else {
		for (NSMenuItem * item in self.itemArray) {
			if ([channel isEqualToString:item.representedObject]) {
				[self selectItem:item];
				break;
			}
		}
	}
	if (!self.selectedItem) {
		[self addItemWithTitle:channel];
		[self selectItem:self.lastItem];
	}

}

-(void) refreshMenu {
	NSArray <NSString *> * sortedKeys = [[self.channelList allKeys] sortedArrayUsingSelector: @selector(caseInsensitiveCompare:)];
	
	NSArray <NSDictionary <NSString *, NSString *> *> * channels = [self.channelList objectsForKeys: sortedKeys notFoundMarker: @{}];

	[self removeAllItems];
	
	NSString * currSelection = (NSString *)self.selectedItem.representedObject;
	if (!currSelection) currSelection = self.preferredChannelName;
	[self removeAllItems];
	
	[self addItemWithTitle:@"Any Channel"];
	NSMenuItem * anyTivo = [self lastItem];
	anyTivo.representedObject = @"";
	if (currSelection.length == 0) {
		[self selectItemAtIndex:0];
	}
	NSMenuItem *separator = [NSMenuItem separatorItem];
	[[self menu] addItem:separator];

	for (NSDictionary <NSString *, NSString *> *channel in channels) {
		NSString * fullName = channel[@"affiliate"];
		NSString * callSign = channel[@"callSign"];
		NSString * channelNumber = channel [@"channelNumber"];
		[self addItemWithTitle:[NSString stringWithFormat:@"%@ (%@)",callSign, channelNumber]];
		NSMenuItem * thisItem = self.lastItem;
		thisItem.toolTip = fullName;
		thisItem.representedObject = callSign;
		if ([callSign isEqualToString:currSelection]) {
			[self selectItem:thisItem];
		}
	}
	if (self.selectedItem == nil) { //just in case
		[self addItemWithTitle:currSelection];
		[self selectItem:self.lastItem];
	}
}

-(void) dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
