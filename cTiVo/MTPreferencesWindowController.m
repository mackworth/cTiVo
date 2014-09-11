//
//  MTPreferencesControllerWindowController.m
//  cTiVo
//
//  Created by Scott Buchanan on 1/26/13.
//  Copyright (c) 2013 Scott Buchanan. All rights reserved.
//

#import "MTPreferencesWindowController.h"
#import "MTManualTiVoEditorController.h"
#import "MTFormatEditorController.h"

@interface MTPreferencesWindowController ()

@end

@implementation MTPreferencesWindowController

- (id)initWithWindow:(NSWindow *)window
{
    self = [super initWithWindow:window];
    if (self) {
        // Initialization code here.
		_startingTabIdentifier = @"";
    }
    
    return self;
}

- (void)windowDidLoad
{
    [super windowDidLoad];
	_ignoreTabItemSelection = YES;
	NSArray *tabViewItems = [_myTabView tabViewItems];
	for (MTTabViewItem *tabViewItem in tabViewItems) {
		NSViewController *thisController = (NSViewController *)tabViewItem.windowController;
		NSRect tabViewFrame = ((NSView *)tabViewItem.view).frame;
		NSRect editorViewFrame = thisController.view.frame;
		[thisController.view setFrameOrigin:NSMakePoint((tabViewFrame.size.width - editorViewFrame.size.width)/2.0, tabViewFrame.size.height - editorViewFrame.size.height)];
		[tabViewItem.view addSubview:thisController.view];
	}
	
//	NSTabViewItem *tabViewItem = [tabView tabViewItemAtIndex:[tabView indexOfTabViewItemWithIdentifier:@"TiVos"]];
//	NSRect tabViewFrame = ((NSView *)tabViewItem.view).frame;
//	NSRect editorViewFrame = manualTiVoEditorController.view.frame;
//	[manualTiVoEditorController.view setFrameOrigin:NSMakePoint((tabViewFrame.size.width - editorViewFrame.size.width)/2.0, tabViewFrame.size.height - editorViewFrame.size.height)];
//	[tabViewItem.view addSubview:manualTiVoEditorController.view];
//
//	tabViewItem = [tabView tabViewItemAtIndex:[tabView indexOfTabViewItemWithIdentifier:@"Formats"]];
//	tabViewFrame = ((NSView *)tabViewItem.view).frame;
//	editorViewFrame = formatEditorController.view.frame;
//	[formatEditorController.view setFrameOrigin:NSMakePoint((tabViewFrame.size.width - editorViewFrame.size.width)/2.0, tabViewFrame.size.height - editorViewFrame.size.height)];
//
//	[tabViewItem.view addSubview:formatEditorController.view];
	
	if (_startingTabIdentifier && _startingTabIdentifier.length) {
		NSTabViewItem *itemToSelect = [_myTabView tabViewItemAtIndex:[_myTabView indexOfTabViewItemWithIdentifier:_startingTabIdentifier]];
		if (itemToSelect) {
			[_myTabView selectTabViewItem:itemToSelect];
		}
	}

	MTTabViewItem *tabViewItem = (MTTabViewItem *)[_myTabView selectedTabViewItem];
	[self.window setFrame:[self getNewWindowRect:tabViewItem] display:NO];
	_ignoreTabItemSelection = NO;
}

-(void)setStartingTabIdentifier:(NSString *)startingTabIdentifier
{
	if (!(_startingTabIdentifier == startingTabIdentifier)) {
		_startingTabIdentifier = startingTabIdentifier;
		if (_startingTabIdentifier && _startingTabIdentifier.length) {
			NSTabViewItem *itemToSelect = [_myTabView tabViewItemAtIndex:[_myTabView indexOfTabViewItemWithIdentifier:_startingTabIdentifier]];
			if (itemToSelect) {
				[_myTabView selectTabViewItem:itemToSelect];
			}
		}
	}
}

-(void)awakeFromNib
{
}

-(IBAction)shouldCloseSheet:(id)sender
{
	MTTabViewItem *selectedItem = (MTTabViewItem *)[_myTabView selectedTabViewItem];
	BOOL shouldClose = YES;
	if ([selectedItem.windowController respondsToSelector:@selector(windowShouldClose:)]) {
		shouldClose = [selectedItem.windowController windowShouldClose:@{@"Target" : self , @"Argument" : @"", @"Selector" : @"closeSheet:"}];
	}
	if (shouldClose) {
		[NSApp endSheet:self.window];
		[self.window orderOut:nil];
	}
}



-(IBAction)closeSheet:(id)sender
{
	[NSApp endSheet:self.window];
	[self.window orderOut:nil];
}

-(NSRect)getNewWindowRect:(MTTabViewItem *)tabViewItem
{
	NSSize viewSize = ((NSViewController *)tabViewItem.windowController).view.frame.size;
	NSSize newSize = NSMakeSize(viewSize.width+40, viewSize.height + 100);
	NSRect frame = self.window.frame;
	double newXOrigin = frame.origin.x + (frame.size.width - newSize.width)/2.0;
	double newYOrigin = frame.origin.y + frame.size.height - newSize.height;
	return NSMakeRect(newXOrigin, newYOrigin, newSize.width, newSize.height);
}

#pragma mark - Tab View Delegate

-(BOOL)tabView:(NSTabView *)tabView shouldSelectTabViewItem:(NSTabViewItem *)tabViewItem
{
	MTTabViewItem *selectedItem = (MTTabViewItem *)[tabView selectedTabViewItem];
	if ([selectedItem.windowController respondsToSelector:@selector(windowShouldClose:)]) {
		return [selectedItem.windowController windowShouldClose:@{@"Target" : tabView , @"Argument" : tabViewItem, @"Selector" : @"selectTabViewItem:"}];
	} else {
		return YES;
	}
}

-(void)tabView:(NSTabView *)tabView willSelectTabViewItem:(NSTabViewItem *)tabViewItem
{
	if (!_ignoreTabItemSelection) {
		[[self.window animator] setFrame:[self getNewWindowRect:(MTTabViewItem *)tabViewItem] display:NO];
	}
}

-(void)tabView:(NSTabView *)tabView didSelectTabViewItem:(NSTabViewItem *)tabViewItem
{
//	NSRect frame = self.window.frame;
//	NSLog(@"Actual new window size is %f %f %f %f",frame.origin.x,frame.origin.y, frame.size.width, frame.size.height);
	
}

-(void)dealloc
{
	self.startingTabIdentifier = nil;
}

@end
