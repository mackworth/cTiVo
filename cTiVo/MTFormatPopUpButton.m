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

@end

@implementation MTFormatPopUpButton

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
	}
	[self refreshMenu];  //outside as it may be due to adding item to array
}

-(void) setShowHidden:(BOOL)showHidden {
	if (showHidden != _showHidden) {
		_showHidden = showHidden;
		[self refreshMenu];
	}
}

-(MTFormat *) selectFormatNamed: (NSString *) newName {
	NSString * oldName = [(MTFormat *) self.selectedItem.representedObject name];
	[self selectItemWithTitle: newName];
	NSString * foundName = [(MTFormat *) self.selectedItem.representedObject name];
	if ([newName compare:foundName ] != NSOrderedSame) {
		//hmm, must have deleted this one during editing.
		[self selectItemWithTitle: oldName];
	}
	return self.selectedItem.representedObject;

}

-(IBAction)formatHelp:(id)sender {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://github.com/dscottbuch/cTiVo/wiki/Video-Formats"]];
}

-(void) refreshMenu {
	NSString * currSelection = [(MTFormat *)self.selectedItem.representedObject name];
	NSArray *tmpArray = [self.formatList  sortedArrayUsingDescriptors:self.sortDescriptors];
	[self removeAllItems];
    int  sectionNum = 0;   //0= user; 1 = factory;  2 = deprecated
	for (MTFormat *f in tmpArray) {
		if(self.showHidden || !([f.isHidden boolValue] || ![f pathForExecutable])) {
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
            NSString * title = f.name;
            if (f.isDeprecated) title = [@"Old " stringByAppendingString:f.name];
            [self addItemWithTitle:f.name];
			NSMenuItem *thisItem = [self lastItem];
			thisItem.attributedTitle = [f attributedFormatStringForFont: self.font];
			
			thisItem.toolTip = [NSString stringWithFormat:@"%@: %@", f.name, f.formatDescription];
			thisItem.representedObject = f;
			
			if ( [currSelection compare: f.name] == NSOrderedSame) {
				[self selectItem:thisItem];
				currSelection = nil;
			}

		}
	}
    //Add Format Help item
    NSMenuItem *separator = [NSMenuItem separatorItem];
    [[self menu] addItem:separator];

    [self addItemWithTitle:@"Help With Formats"];
    [[self lastItem] setTarget:self];
    [[self lastItem] setAction:@selector(formatHelp:)];


	if (currSelection) {
		//no longer in list
		[self selectItemAtIndex:1]; //just beyond the first label.
	}
	
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];

	 _formatList = nil;
}
@end
