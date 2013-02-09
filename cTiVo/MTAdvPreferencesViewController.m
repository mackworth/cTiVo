//
//  MTAdvPreferencesViewController.m
//  cTiVo
//
//  Created by Hugh Mackworth on 2/7/13.
//  Copyright (c) 2013 Scott Buchanan. All rights reserved.
//

#import "MTAdvPreferencesViewController.h"
#import "DDLog.h"

@interface MTAdvPreferencesViewController ()
@property (nonatomic, retain) NSArray * debugClasses;
@property (nonatomic, retain) NSMutableArray * popups;
@end

@implementation MTAdvPreferencesViewController

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
  self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        // Initialization code here.
    }
	
    return self;
}

-(NSTextField *) newTextField: (NSRect) frame {
	NSTextField *textField;
	
    textField = [[NSTextField alloc] initWithFrame:frame];
    [textField setBezeled:NO];
    [textField setDrawsBackground:NO];
    [textField setEditable:NO];
    [textField setSelectable:NO];
	[textField setAlignment: NSRightTextAlignment ];
	[textField setFont:[NSFont systemFontOfSize:[NSFont systemFontSizeForControlSize:NSSmallControlSize]]];
	[textField setAutoresizingMask: NSViewMinXMargin | NSViewWidthSizable | NSViewMaxXMargin | NSViewMinYMargin | NSViewHeightSizable | NSViewMaxYMargin];
	return textField;
}

-(void) addMenuTo:(NSPopUpButton*) cell withCurrentLevel: (NSInteger) currentLevel{

	NSArray * debugNames = @[@"None",@"Normal" ,@"Major" ,@"Detail" , @"Verbose"];
	int debugLevels[] = {LOG_LEVEL_OFF, LOG_LEVEL_REPORT, LOG_LEVEL_MAJOR, LOG_LEVEL_DETAIL, LOG_LEVEL_VERBOSE};

	[cell addItemsWithTitles: debugNames];
	for (int index = 0; index < cell.numberOfItems; index++) {
		//	for (NSMenuItem * item in [cell itemArray]) {
		NSMenuItem * menu = [cell itemAtIndex:index];
		menu.tag = debugLevels[index];
		if (menu.tag == currentLevel) {
			[cell selectItem:menu];
		}
	}
}

-(void) resetAllPopups: (int) newVal {
}

-(void) awakeFromNib {
	
	self.debugClasses = [DDLog registeredClasses] ;
	self.popups= [NSMutableArray arrayWithCapacity:self.debugClasses.count ];
	
//	NSInteger const  kNumColumns = 1;
	int numItems = (int)[self.debugClasses count];
//	NSInteger numRows = numItems / kNumColumns;
//	NSInteger row, col;
	[self addMenuTo:self.masterDebugLevel withCurrentLevel:[[NSUserDefaults standardUserDefaults] integerForKey:kMTDebugLevel]];
	for (int item =0;item < numItems; item++) {
		NSString * className =  NSStringFromClass(self.debugClasses [item]);
		const int vertBase = 120;
		const int labelWidth = 150;
		const int popupHeight = 25;
		const int popupWidth = 80;
		const int vertMargin = 5;
		const int horizMargin = 10;
		const int columnWidth = labelWidth+vertMargin+popupWidth+vertMargin*4;
		int columNum = (item < numItems/2)? 0:1;
		int rowNum = (item < numItems/2) ? item: item-numItems/2;
		
		NSRect labelFrame = NSMakeRect(columNum*columnWidth,rowNum*(popupHeight+vertMargin)-4+vertBase,labelWidth,popupHeight);
		NSTextField * label = [[self newTextField:labelFrame] autorelease];
		[label setStringValue:[NSString stringWithFormat:@"%@:",className]];
		
		NSRect frame = NSMakeRect(columNum*columnWidth+labelWidth+horizMargin,rowNum*(popupHeight+vertMargin)+vertBase,popupWidth,popupHeight);
		
		NSPopUpButton * cell = [[NSPopUpButton alloc] initWithFrame:frame pullsDown:NO];
		
		cell.title = className;
		cell.font= 	[NSFont systemFontOfSize:[NSFont systemFontSizeForControlSize:NSSmallControlSize]];

		[self addMenuTo:cell withCurrentLevel: [DDLog logLevelForClass:self.debugClasses [item]]];
		cell.target = self;
		cell.action = @selector(newValue:);
		
		[self.debugLevelView addSubview:label];
		[self.debugLevelView addSubview:cell];
		[self.popups addObject: cell];
	}
	
//	for (row = 0; row < numRows; row++) {
//		for ( col = 0; col < kNumColumns; col++) {
//			NSInteger itemNum = row*kNumColumns +col;
//			NSCell * cell = [self.debugLevelForm cellAtRow:row column:col];
//			if (itemNum < numItems) {
//				cell.title = NSStringFromClass([self.debugClasses objectAtIndex:itemNum]);
//			}
//		}
//	}

}

-(IBAction) newMasterValue:(id) sender {
	NSPopUpButton * cell =  (NSPopUpButton *) sender;
	
	int newVal = (int) cell.selectedItem.tag;
	for (Class class in [DDLog registeredClasses]) {
		[class ddSetLogLevel:newVal];
	}
	for (NSPopUpButton * cell in self.popups) {
		[cell selectItemWithTag:newVal];
	}
	[DDLog writeAllClassesLogLevelToUserDefaults];
}

-(IBAction) newValue:(id) sender {
	NSPopUpButton * cell =  (NSPopUpButton *) sender;
	NSInteger whichPopup = [self.popups indexOfObject:sender];
	Class class = self.debugClasses[whichPopup];
	
	int newVal = (int) cell.selectedItem.tag;
	
	[DDLog setLogLevel:newVal forClass:class];
	[DDLog writeAllClassesLogLevelToUserDefaults];
}
@end
