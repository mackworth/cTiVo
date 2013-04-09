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

- (id)initWithCoder:(NSCoder *)aDecoder
{
    self = [super initWithCoder:aDecoder];
    if (self) {
        // Initialization code here.
    }
    
    return self;
}

-(BOOL)windowShouldClose:(id)sender
{
	[self.view.window makeFirstResponder:self.view]; //This closes out handing editing.
	return YES;
}

- (void)awakeFromNib	
{
	[[NSUserDefaults standardUserDefaults] addObserver:self forKeyPath:kMTManualTiVos options:NSKeyValueObservingOptionNew context:nil];
    
    // Implement this method to handle any initialization after your window controller's window has been loaded from its nib file.
}

-(void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
	if ([keyPath compare:kMTManualTiVos] == NSOrderedSame) {
		[tiVoManager loadManualTiVos];
	}
}

-(IBAction)add:(id)sender
{
	if (((NSArray *)arrayController.content).count == 0) { //No template to check
		[[NSUserDefaults standardUserDefaults] setObject:@[@{@"enabled" : [NSNumber numberWithBool:NO], @"userName" : @"TiVo Name", @"iPAddress" : @"0.0.0.0", @"userPort" : @"80", @"userPortSSL" : @"443"}] forKey:kMTManualTiVos];
	} else {
        NSMutableArray *manualTiVos = [NSMutableArray arrayWithArray:[[NSUserDefaults standardUserDefaults] objectForKey:kMTManualTiVos]];
        [manualTiVos addObject:@{@"enabled" : [NSNumber numberWithBool:NO], @"userName" : @"TiVo Name", @"iPAddress" : @"0.0.0.0", @"userPort" : @"80", @"userPortSSL" : @"443"}];
		[[NSUserDefaults standardUserDefaults] setObject:manualTiVos forKey:kMTManualTiVos];
	}
}

-(void)dealloc
{
	[[NSUserDefaults standardUserDefaults] removeObserver:self forKeyPath:kMTManualTiVos];
}

@end
