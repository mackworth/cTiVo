//
//  MTManualTiVoEditor.m
//  cTiVo
//
//  Created by Scott Buchanan on 1/25/13.
//  Copyright (c) 2013 Scott Buchanan. All rights reserved.
//

#import "MTManualTiVoEditorController.h"
#import "MTTiVoManager.h"

@interface MTManualTiVoEditorController ()

@end

@implementation MTManualTiVoEditorController

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
	[[NSUserDefaults standardUserDefaults] addObserver:self forKeyPath:@"ManualTiVos" options:NSKeyValueObservingOptionNew context:nil];
    
    // Implement this method to handle any initialization after your window controller's window has been loaded from its nib file.
}

-(void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
	if ([keyPath compare:@"ManualTiVos"] == NSOrderedSame) {
		[tiVoManager loadManualTiVos];
	}
}

-(IBAction)add:(id)sender
{
	if (((NSArray *)arrayController.content).count == 0) { //No template to check
		[[NSUserDefaults standardUserDefaults] setObject:@[@{@"enabled" : [NSNumber numberWithBool:YES], @"userName" : @"TiVo Name", @"iPAddress" : @"0.0.0.0", @"userPort" : @"0"}] forKey:kMTManualTiVos];
	} else {
		[arrayController add:sender];
	}
}

-(void)dealloc
{
	[[NSUserDefaults standardUserDefaults] removeObserver:self forKeyPath:@"ManualTiVos"];
	[super dealloc];
}

-(IBAction)logArray:(id)sender
{
	NSLog(@"array contains %@",arrayController.arrangedObjects);
}

@end
