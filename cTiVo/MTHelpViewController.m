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

@interface NSAttributedString (replace)

-(NSAttributedString *) replace:(NSString *) oldString with:(NSString *) newString;

@end

@implementation NSAttributedString (replace)
-(NSAttributedString *) replace:(NSString *) oldString with:(NSString *) newString {
	NSMutableAttributedString * string = [self mutableCopy];
	NSRange range = [string.string rangeOfString:oldString options:NSLiteralSearch];
	while (range.location != NSNotFound) {
		[string replaceCharactersInRange:range withString:newString];
		NSInteger start = range.location+ newString.length;
		NSRange newRange = NSMakeRange( start,string.length-start) ;
		range = [string.string rangeOfString:oldString options:NSLiteralSearch range:newRange];
	}
	return [string copy];

}

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
	NSAttributedString *attrHelpText = nil;
	NSURL *helpFile = [[NSBundle mainBundle] URLForResource:rtfFile withExtension:@"rtf"];
	if (helpFile) {
		attrHelpText= [[NSAttributedString alloc] initWithRTF:[NSData dataWithContentsOfURL:helpFile] documentAttributes:NULL];
	} else {
		//Must be a rtfd
		helpFile = [[NSBundle mainBundle] URLForResource:rtfFile withExtension:@"rtfd"];
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
	}
#ifdef MAC_APP_STORE
	attrHelpText = [attrHelpText replace:@"cTiVo" with:@"cTV"];
#endif
	self.attributedString = attrHelpText;
					
}

@end
