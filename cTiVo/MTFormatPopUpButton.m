//
//  MTPopUpButton.m
//  cTiVo
//
//  Created by Scott Buchanan on 1/4/13.
//  Copyright (c) 2013 Scott Buchanan. All rights reserved.
//

#import "MTFormatPopUpButton.h"
#import "MTTiVoManager.h"
@interface MTFormatPopUpButton () {
	
}
@property (nonatomic, strong) NSArray *sortDescriptors;
@property (nonatomic, strong) NSString *preferredFormatName;
@end

@implementation MTFormatPopUpButton

-(void) sharedInit {
    self.preferredFormatName = @"";
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(formatMayHaveChanged) name:kMTNotificationFormatListUpdated object:nil];
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

-(void) formatMayHaveChanged {
    self.formatList = nil;
}

-(NSArray *) sortDescriptors {
	if (!_sortDescriptors){
        NSSortDescriptor *notDeprecated = [NSSortDescriptor sortDescriptorWithKey:@"isDeprecated" ascending:YES];
        NSSortDescriptor *user = [NSSortDescriptor sortDescriptorWithKey:@"isFactoryFormat" ascending:YES];
		NSSortDescriptor *title = [NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES selector:@selector(caseInsensitiveCompare:)];
		_sortDescriptors = [NSArray arrayWithObjects:notDeprecated,user,title, nil];
	}
	return _sortDescriptors;

}
-(void)setFormatList:(NSArray *)formatList {
	if (formatList != _formatList) {
		_formatList = formatList;
        [self refreshMenu];
	}
}

-(void) setShowHidden:(BOOL)showHidden {
	if (showHidden != _showHidden) {
		_showHidden = showHidden;
		[self refreshMenu];
	}
}

-(MTFormat *) selectFormat: (MTFormat *) format {
    NSString * newName = format.name;
    if (!newName) return nil;
    self.preferredFormatName = newName;
    [self selectItemWithTitle:newName];
    MTFormat *menuFormat = (MTFormat *)self.selectedItem.representedObject;
    MTFormat * newFormat = [tiVoManager findFormat:newName];
    if (![menuFormat isKindOfClass:[MTFormat class]] || ![menuFormat.name isEqualToString:newFormat.name]) {
       [self refreshMenu];
    }
    return newFormat;
}

-(IBAction)formatHelp:(id)sender {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://github.com/mackworth/cTiVo/wiki/Video-Formats"]];
    [self selectItemWithTitle:self.preferredFormatName];
}

-(void) refreshMenu {
    if (!self.formatList) _formatList = [tiVoManager formatList];
	NSArray *tmpArray = [self.formatList  sortedArrayUsingDescriptors:self.sortDescriptors];
	[self removeAllItems];
    int  sectionNum = 0;   //0= user; 1 = factory;  2 = deprecated
	for (MTFormat *f in tmpArray) {
		if (self.showHidden ||
            [f.name isEqualToString:self.preferredFormatName] ||
            (![f.isHidden boolValue] && [f pathForExecutable])) {
			if ( self.numberOfItems == 0 && ![f.isFactoryFormat boolValue]) {
				[self addItemWithTitle:@"    User Formats"];
				[[self lastItem] setEnabled:NO];
				[[self lastItem] setTarget:nil];
			}
            if (f.isDeprecated  && sectionNum < 2) { //This is a changeover from factory to deprecated input
                if ( self.numberOfItems > 0) {
                    NSMenuItem *separator = [NSMenuItem separatorItem];
                    [[self menu] addItem:separator];
                }
                [self addItemWithTitle:@"    Not Recommended"];
                [[self lastItem] setEnabled:NO];
                [[self lastItem] setTarget:nil];
                sectionNum = 2;
            }
			if ([f.isFactoryFormat boolValue] && sectionNum == 0) { //This is a changeover from user input (if any) to factory input
				if ( self.numberOfItems > 0) {
					NSMenuItem *separator = [NSMenuItem separatorItem];
					[[self menu] addItem:separator];
				}
				[self addItemWithTitle:@"    Built-In Formats"];
				[[self lastItem] setEnabled:NO];
				[[self lastItem] setTarget:nil];
				sectionNum = 1;
			}
            [self addItemWithTitle:f.name];
			NSMenuItem *thisItem = [self lastItem];
			thisItem.attributedTitle = [f attributedFormatStringForFont: self.font];
			
			thisItem.toolTip = [NSString stringWithFormat:@"%@: %@", f.name, f.formatDescription];
			thisItem.representedObject = f;

		}
	}
    //Add Format Help item
    NSMenuItem *separator = [NSMenuItem separatorItem];
    [[self menu] addItem:separator];

    [self addItemWithTitle:@"Help With Formats"];
    [[self lastItem] setTarget:self];
    [[self lastItem] setAction:@selector(formatHelp:)];

    [self selectItemWithTitle:self.preferredFormatName];
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];

	 _formatList = nil;
}
@end
