//
//  MTFormatEditorController.m
//  cTiVo
//
//  Created by Scott Buchanan on 1/12/13.
//  Copyright (c) 2013 Scott Buchanan. All rights reserved.
//

#import "MTFormatEditorController.h"
#import "MTTiVoManager.h"

#define tiVoManager [MTTiVoManager sharedTiVoManager]

@interface MTFormatEditorController ()

@end

@implementation MTFormatEditorController

- (id)initWithWindow:(NSWindow *)window
{
    self = [super initWithWindow:window];
    if (self) {
        // Initialization code here.
    }
    
    return self;
}

- (void)windowDidLoad
{
    [super windowDidLoad];
	//Deepcopy array so we have new object
	self.formatList = [NSMutableArray array];

	for (MTFormat *f in tiVoManager.formatList) {
		MTFormat *newFormat = [[f copy] autorelease];
		[_formatList addObject:newFormat];
		if ([tiVoManager.selectedFormat.name compare:newFormat.name] == NSOrderedSame) {
			self.currentFormat = newFormat;
		}
	}
//	self.formatList = [NSMutableArray arrayWithArray:tiVoManager.formatList];
//	self.currentFormat = [tiVoManager.selectedFormat copy];
 	[self refreshFormatPopUp:nil];
	self.shouldSave = [NSNumber numberWithBool:NO];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(checkShouldSave) name:kMTNotificationFormatChanged object:nil];
   
    // Implement this method to handle any initialization after your window controller's window has been loaded from its nib file.
}

- (BOOL)windowShouldClose:(id)sender
{
	if ([self.shouldSave boolValue]) {
		saveOrCancelAlert = [NSAlert alertWithMessageText:@"You have edited the formats.  Closed the window will discard your changes.  Do you want to save your changes?" defaultButton:@"Save" alternateButton:@"Close Window" otherButton:@"Don't Close Window" informativeTextWithFormat:@""];
		[saveOrCancelAlert beginSheetModalForWindow:self.window modalDelegate:self didEndSelector:@selector(alertDidEnd:returnCode:contextInfo:) contextInfo:nil];
		return NO;
	} else {
		if (!sender) {
			[self.window close];
		}
		return YES;

	}
}


-(void)showWindow:(id)sender
{
	//Deepcopy array so we have new object
    if (formatPopUpButton) {  //Clumsy way of refreshing popup selection after dismissal and re-show of window.  Need better connection
        for (MTFormat *f in _formatList) {
            if ([tiVoManager.selectedFormat.name compare:f.name] == NSOrderedSame) {
                self.currentFormat = f;
            }
        }
        //	self.formatList = [NSMutableArray arrayWithArray:tiVoManager.formatList];
        //	self.currentFormat = [tiVoManager.selectedFormat copy];
        [self refreshFormatPopUp:nil];
        self.shouldSave = [NSNumber numberWithBool:NO];
    }
	[super showWindow:sender];
}

#pragma mark - Utility Methods

-(NSString *)checkFormatName:(NSString *)name
{
	//Make sure the title isn't the same and if it is add a -1 modifier
    for (MTFormat *f in _formatList) {
		if ([name caseInsensitiveCompare:f.name] == NSOrderedSame) {
            NSRegularExpression *ending = [NSRegularExpression regularExpressionWithPattern:@"(.*)-([0-9]+)$" options:NSRegularExpressionCaseInsensitive error:nil];
            NSTextCheckingResult *result = [ending firstMatchInString:name options:NSMatchingWithoutAnchoringBounds range:NSMakeRange(0, name.length)];
            if (result) {
                int n = [[f.name substringWithRange:[result rangeAtIndex:2]] intValue];
                name = [[name substringWithRange:[result rangeAtIndex:1]] stringByAppendingFormat:@"-%d",n+1];
            } else {
                name = [name stringByAppendingString:@"-1"];
            }
            [self checkFormatName:name];
        }
    }
	return name;
}

#pragma mark - UI Actions

-(IBAction)cancelFormatEdit:(id)sender
{
	[self windowShouldClose:nil];
}

-(IBAction)selectFormat:(id)sender
{
        NSPopUpButton *thisButton = (NSPopUpButton *)sender;
        self.currentFormat = [[thisButton selectedItem] representedObject];
	
}

-(IBAction)deleteFormat:(id)sender
{
	deleteAlert = [NSAlert alertWithMessageText:[NSString stringWithFormat:@"Do you want to delete the format %@",_currentFormat.name] defaultButton:@"Yes" alternateButton:@"No" otherButton:nil informativeTextWithFormat:@"This cannot be undone"];
	[deleteAlert beginSheetModalForWindow:self.window modalDelegate:self didEndSelector:@selector(alertDidEnd:returnCode:contextInfo:) contextInfo:nil];
	
}

-(IBAction)saveFormats:(id)sender
{
	NSMutableArray *userFormats = [NSMutableArray array];
	[tiVoManager.formatList removeAllObjects];
	for (MTFormat *f in _formatList) {
		MTFormat *newFormat = [[f copy] autorelease];
		[tiVoManager.formatList addObject:newFormat];
		if (![newFormat.isFactoryFormat boolValue]) {
			[userFormats addObject:[newFormat toDictionary]];
		}
	}
	[[NSUserDefaults standardUserDefaults] setObject:userFormats forKey:@"formats"];
	[[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationFormatListUpdated object:nil];
	[self checkShouldSave];
}

- (void) alertDidEnd:(NSAlert *)alert returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo;
{
	if (alert == deleteAlert) {
		if (returnCode == 1) {
			[self.formatList removeObject:_currentFormat];
			self.currentFormat = _formatList[0];
			[self refreshFormatPopUp:nil];
			[self checkShouldSave];
		}
	}
	if (alert == saveOrCancelAlert) {
		switch (returnCode) {
			case 1:
				//Save changes here
				[self saveFormats:nil];
				[self.window close];
				break;
			case 0:
				//Cancel Changes here and dismiss
				[self.window close];
				break;
			case -1:
				//Don't Close the window
				break;
			default:
				break;
		}
	}
}

-(IBAction)newFormat:(id)sender
{
	
	MTFormat *newFormat = [[MTFormat new] autorelease];
	newFormat.name = [self checkFormatName:@"New Format"];
	[self.formatList addObject:newFormat];
	[self refreshFormatPopUp:nil];
	[formatPopUpButton selectItemWithTitle:newFormat.name];
	self.currentFormat = [[formatPopUpButton selectedItem] representedObject];
	[self checkShouldSave];
	
}

-(void)checkShouldSave
{
	BOOL result = NO;
	for (MTFormat *f in _formatList) {
		MTFormat *foundFormat = [tiVoManager findFormat:f.name];
		if (!foundFormat) { //We have a new format so we should be able to save/cancel
			result = YES;
			break;
		}
        if (![foundFormat isSame:f]) { //We found a format that exisit but is different.
            result = YES;
			break;
        }
	}
	self.shouldSave = [NSNumber numberWithBool:result];
}

-(IBAction)duplicateFormat:(id)sender
{
	MTFormat *newFormat = [[_currentFormat copy] autorelease];
	newFormat.name = [self checkFormatName:newFormat.name];
	newFormat.isFactoryFormat = [NSNumber numberWithBool:NO];
	[self.formatList addObject:newFormat];
	[self refreshFormatPopUp:nil];
	[formatPopUpButton selectItemWithTitle:newFormat.name];
	self.currentFormat = [[formatPopUpButton selectedItem] representedObject];
	[self checkShouldSave];
}

-(void)refreshFormatPopUp:(NSNotification *)notification
{
    //Created Sorted List
    NSSortDescriptor *user = [NSSortDescriptor sortDescriptorWithKey:@"isFactoryFormat" ascending:YES];
    NSSortDescriptor *title = [NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES selector:@selector(caseInsensitiveCompare:)];
    NSArray *sortDescriptors = [NSArray arrayWithObjects:user,title, nil];
    NSMutableArray *tmpArray = [NSMutableArray arrayWithArray:_formatList];
    [tmpArray  sortUsingDescriptors:sortDescriptors];
    
	[formatPopUpButton removeAllItems];
    BOOL isFactory = YES;
	for (MTFormat *f in tmpArray) {
        if ([formatPopUpButton numberOfItems] == 0 && ![f.isFactoryFormat boolValue]) {
            [formatPopUpButton addItemWithTitle:@"    User Formats"];
            [[formatPopUpButton lastItem] setEnabled:NO];
            [[formatPopUpButton lastItem] setTarget:nil];
            
        }
        if ([f.isFactoryFormat boolValue] && isFactory) { //This is a changeover from user input to factory input (if any
            NSMenuItem *separator = [NSMenuItem separatorItem];
            [[formatPopUpButton menu] addItem:separator];
            [formatPopUpButton addItemWithTitle:@"    Built In Formats"];
            [[formatPopUpButton lastItem] setEnabled:NO];
            [[formatPopUpButton lastItem] setTarget:nil];
            isFactory = NO;
        }
		[formatPopUpButton addItemWithTitle:f.name];
		NSColor * formatColor = [NSColor colorWithDeviceRed:0.0
													  green:0.0
													   blue:([f.isFactoryFormat boolValue] ? 0.7: 0.0)
													  alpha:[f.isHidden boolValue] ? 0.5: 1.0];
		NSAttributedString *attTitle = [[NSAttributedString alloc] initWithString: f.name
																	   attributes: @{NSFontAttributeName : formatPopUpButton.font,
																		   NSForegroundColorAttributeName: formatColor}];
		[formatPopUpButton lastItem].attributedTitle = attTitle;
		
		[formatPopUpButton lastItem].toolTip = f.description;
		[[formatPopUpButton lastItem] setRepresentedObject:f];
	}
	[formatPopUpButton selectItemWithTitle:_currentFormat.name];
	self.currentFormat = [[formatPopUpButton selectedItem] representedObject];
}

-(void)dealloc
{
	self.currentFormat = nil;
	[super dealloc];
}

@end
