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
	[super awakeFromNib];
    [manualTiVoArrayController setFilterPredicate:[NSPredicate predicateWithBlock:^BOOL(id item, NSDictionary *bindings){
        NSDictionary *tiVo = (NSDictionary *)item;
        return [tiVo[kMTTiVoManualTiVo] boolValue];
    }]];
    [networkTiVoArrayController setFilterPredicate:[NSPredicate predicateWithBlock:^BOOL(id item, NSDictionary *bindings){
        NSDictionary *tiVo = (NSDictionary *)item;
        return ![tiVo[kMTTiVoManualTiVo] boolValue];
    }]];
    [[NSUserDefaults standardUserDefaults] addObserver:self forKeyPath:kMTTiVos options:NSKeyValueObservingOptionOld context:nil];

}

-(void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if ([keyPath compare:kMTTiVos] == NSOrderedSame) {
        [self loadContent:manualTiVoArrayController];
        [self loadContent:networkTiVoArrayController];
        DDLogDetail(@"manual tivos %@",[manualTiVoArrayController.arrangedObjects maskMediaKeys]);
        [manualTiVoArrayController rearrangeObjects];
        [networkTiVoArrayController rearrangeObjects];
   } else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

-(void)loadContent:(NSArrayController *)dest
{
    NSArray *def = [tiVoManager savedTiVos];
    NSMutableArray *newdef = [NSMutableArray new];
    for (NSDictionary *tivo in def) {
        [newdef addObject:[NSMutableDictionary dictionaryWithDictionary:tivo]];
    }
    [dest setContent:newdef];
}

-(IBAction)addManual:(id)sender
{
    NSArray * existingTivos = tiVoManager.savedTiVos;
    NSMutableArray *tiVos = [NSMutableArray new];
    if (existingTivos) {
        tiVos = [NSMutableArray arrayWithArray:existingTivos];
    }
    NSInteger newID = [tiVoManager nextManualTiVoID]; 
    [tiVos addObject:@{@"enabled" : @NO, kMTTiVoUserName : @"TiVo Name", kMTTiVoIPAddress : @"0.0.0.0", kMTTiVoUserPort : @"80", kMTTiVoUserPortSSL : @"443", kMTTiVoUserPortRPC: @"1413", kMTTiVoID : @(newID), kMTTiVoTSN : @"", kMTTiVoManualTiVo : @YES, kMTTiVoMediaKey : @""}];
   [[NSUserDefaults standardUserDefaults] setValue:tiVos forKeyPath:kMTTiVos];
}


-(void)dealloc
{
	[[NSUserDefaults standardUserDefaults] removeObserver:self forKeyPath:kMTTiVos];
}

@end
