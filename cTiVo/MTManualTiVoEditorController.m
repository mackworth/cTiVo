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

__DDLOGHERE__

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
	[[NSUserDefaults standardUserDefaults] addObserver:self forKeyPath:kMTTiVos options:NSKeyValueObservingOptionNew context:nil];
    // Implement this method to handle any initialization after your window controller's window has been loaded from its nib file.
    [manualTiVoArrayController setFilterPredicate:[NSPredicate predicateWithBlock:^BOOL(id item, NSDictionary *bindings){
        NSDictionary *tiVo = (NSDictionary *)item;
        return [tiVo[kMTTiVoManualTiVo] boolValue];
    }]];
    [networkTiVoArrayController setFilterPredicate:[NSPredicate predicateWithBlock:^BOOL(id item, NSDictionary *bindings){
        NSDictionary *tiVo = (NSDictionary *)item;
        return ![tiVo[kMTTiVoManualTiVo] boolValue];
    }]];
    
}

-(void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
	if ([keyPath compare:kMTTiVos] == NSOrderedSame) {
        [self loadContent:manualTiVoArrayController];
        [self loadContent:networkTiVoArrayController];
		[tiVoManager loadManualTiVos];
        DDLogDetail(@"manual tivos %@",manualTiVoArrayController.arrangedObjects);
        [manualTiVoArrayController rearrangeObjects];
        [networkTiVoArrayController rearrangeObjects];
	}
}

-(void)loadContent:(NSArrayController *)dest
{
    NSArray *def = [[NSUserDefaults standardUserDefaults] objectForKey:kMTTiVos];
    NSMutableArray *newdef = [NSMutableArray new];
    for (NSDictionary *tivo in def) {
        [newdef addObject:[NSMutableDictionary dictionaryWithDictionary:tivo]];
    }
    [dest setContent:newdef];
}

-(IBAction)addManual:(id)sender
{
    NSMutableArray *tiVos = [NSMutableArray arrayWithArray:[[NSUserDefaults standardUserDefaults] objectForKey:kMTTiVos]];
	if (!tiVos) tiVos = [NSMutableArray new];
	
	[tiVos addObject:@{@"enabled" : [NSNumber numberWithBool:NO], kMTTiVoUserName : @"TiVo Name", kMTTiVoIPAddress : @"0.0.0.0", kMTTiVoUserPort : @"80", kMTTiVoUserPortSSL : @"443", kMTTiVoID : @([tiVoManager nextManualTiVoID]), kMTTiVoManualTiVo : @YES, kMTTiVoMediaKey : @""}];
    [[NSUserDefaults standardUserDefaults] setValue:tiVos forKeyPath:kMTTiVos];
}


@end
