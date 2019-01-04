//
//  MTHelpViewController.m
//  cTiVo
//
//  Created by Scott Buchanan on 1/14/13.
//  Copyright (c) 2013 Scott Buchanan. All rights reserved.
//

#import "MTHelpViewController.h"

@interface MTHelpViewController () {
	CGSize myPreferredSize;
}
@property (nonatomic, strong) NSPopover * popover;
@property (nonatomic, strong) IBOutlet NSTextView *displayMessage;

@end

@implementation MTHelpViewController

-(id) init {
	self = [super initWithNibName: @"MTHelpViewController" bundle:nil];
	return self;
}

-(void) setPreferredContentSize:(NSSize)preferredContentSize {
	myPreferredSize = preferredContentSize;
	if (self.popover) {
		self.popover.contentSize = preferredContentSize;
	}
}

-(CGSize) preferredContentSize {
		return myPreferredSize;
}

-(void) checkLinks {
	if (self.view) nil; //ensure it's loaded.
	[self.displayMessage setEditable:YES];
	[self.displayMessage setAutomaticLinkDetectionEnabled:YES];
	[self.displayMessage checkTextInDocument:nil];
}

-(void) pointToView:(NSView *) view preferredEdge: (NSRectEdge) edge {
	if (self.view && !self.popover) {
		self.popover = [[NSPopover alloc] init];
		self.popover.behavior = NSPopoverBehaviorTransient;
		self.popover.contentViewController = self;
		self.popover.contentSize = myPreferredSize;
	}
	[self.popover showRelativeToRect:view.bounds ofView:view preferredEdge:edge];
}

-(void) setAttributedString:(NSAttributedString *)text {
	if (self.view) { //ensures view is loaded.
		[self.displayMessage.textStorage setAttributedString:  text];
	}
}

-(NSAttributedString *) attributedString {
	return self.displayMessage.textStorage ;
}

-(void) setText:(NSString *)text {
	self.attributedString = [[NSAttributedString alloc] initWithString:text];
}

-(NSString *) text {
	return self.attributedString.string;
}

-(void) loadResource:(NSString *)rtfFile {
	//Looks for RTF resource; first as rtf then as rtfd.
	//if dark Mode, either finds rtfFileDark or auto-converts text to Textcolor
	BOOL darkMode = NO;
	BOOL autoDarkMode = NO;
	if (@available(macOS 10.14, *) ) {
		darkMode = [self.view.effectiveAppearance.name isEqualToString:NSAppearanceNameDarkAqua];
	}
	NSAttributedString *attrHelpText = nil;
	NSURL *helpFile = nil;
	if (darkMode) {
		helpFile = [[NSBundle mainBundle] URLForResource:[rtfFile stringByAppendingString:@"Dark"] withExtension:@"rtf"];
	}
	if (!helpFile) {
		helpFile = [[NSBundle mainBundle] URLForResource:rtfFile withExtension:@"rtf"];
		if (helpFile){
			if (darkMode) autoDarkMode = YES;
		}
	}
	if (helpFile) {
		 attrHelpText= [[NSAttributedString alloc] initWithRTF:[NSData dataWithContentsOfURL:helpFile] documentAttributes:NULL];
		if (autoDarkMode) {
			
		}
	} else {
		//Must be a rtfd
		if (darkMode) {
			helpFile = [[NSBundle mainBundle] URLForResource:[rtfFile stringByAppendingString:@"Dark"] withExtension:@"rtfd"];
		}
		if (!helpFile) {
			helpFile = [[NSBundle mainBundle] URLForResource:rtfFile withExtension:@"rtfd"];
			if (darkMode) autoDarkMode = YES;
		}
		if (helpFile) {
			NSError * error = nil;
			NSFileWrapper * rtfdDirectory = [[NSFileWrapper alloc] initWithURL:helpFile options:0 error:&error];
			if (rtfdDirectory && !error){
				attrHelpText = [[NSAttributedString alloc] initWithRTFDFileWrapper:rtfdDirectory  documentAttributes:NULL];
			}
		}
	}
	if (!attrHelpText) {
		attrHelpText = [[NSAttributedString alloc] initWithString:
					[NSString stringWithFormat:@"Can't find help text for %@ at path %@", rtfFile, helpFile]];
		if (darkMode) autoDarkMode = YES;
	}
	if (autoDarkMode) {
		NSMutableAttributedString * temp = [[NSMutableAttributedString alloc] initWithAttributedString:attrHelpText];
		[temp setAttributes:@{NSForegroundColorAttributeName : [NSColor textColor] } range:NSMakeRange(0, temp.length)];
		attrHelpText = [[NSAttributedString alloc] initWithAttributedString:temp];
	}
	self.attributedString = attrHelpText;
}

@end
