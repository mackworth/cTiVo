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
	[[NSUserDefaults standardUserDefaults] addObserver:self forKeyPath:kMTTiVos options:NSKeyValueObservingOptionOld context:nil];
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
        int typeOfChange = 0;
        NSArray *oldValues = change[NSKeyValueChangeOldKey];
        NSArray *newValues = [[NSUserDefaults standardUserDefaults] objectForKey:kMTTiVos];
        if (oldValues.count != newValues.count) {
            typeOfChange = 1;
        }
        int newValuesEnabled = 0;
        for (NSDictionary *tivo in newValues) {
            if ([tivo[kMTTiVoEnabled] boolValue]) {
                newValuesEnabled++;
            }
        }
        switch (typeOfChange) {
            case 0:
//                if (newValuesEnabled == 0) {
//                    [[NSUserDefaults standardUserDefaults] setObject:newValues forKey:kMTTiVos];
//                }
                break;
            case 1:
                if (newValuesEnabled == 0) {
                    NSMutableArray *changedNewValues = [NSMutableArray arrayWithArray:newValues];
                    NSMutableDictionary *firstValue = [NSMutableDictionary dictionaryWithDictionary:changedNewValues[0]];
                    firstValue[kMTTiVoEnabled] = @YES;
                    [changedNewValues replaceObjectAtIndex:0 withObject:firstValue];
                    [[NSUserDefaults standardUserDefaults] setObject:changedNewValues forKey:kMTTiVos];
                }
                break;
                
                
            default:
                break;
        }
        [self loadContent:manualTiVoArrayController];
        [self loadContent:networkTiVoArrayController];
        [tiVoManager loadManualTiVos];
        DDLogDetail(@"manual tivos %@",[manualTiVoArrayController.arrangedObjects maskMediaKeys]);
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
    NSMutableArray *tiVos = [NSMutableArray new];
    if ([[NSUserDefaults standardUserDefaults] objectForKey:kMTTiVos]) {
        tiVos = [NSMutableArray arrayWithArray:[[NSUserDefaults standardUserDefaults] objectForKey:kMTTiVos]];
    }
	if (((NSArray *)manualTiVoArrayController.arrangedObjects).count == 0) { //No template to check
		[tiVos addObject:@{@"enabled" : [NSNumber numberWithBool:NO], kMTTiVoUserName : @"TiVo Name", kMTTiVoIPAddress : @"0.0.0.0", kMTTiVoUserPort : @"80", kMTTiVoUserPortSSL : @"443", kMTTiVoID : @1, kMTTiVoManualTiVo : @YES, kMTTiVoMediaKey : @""} ];
	} else {
        NSMutableArray *manualTiVos = manualTiVoArrayController.arrangedObjects;
		NSSortDescriptor *idDescriptor = [NSSortDescriptor sortDescriptorWithKey:kMTTiVoID ascending:NO];
		NSArray *sortedByID = [manualTiVos sortedArrayUsingDescriptors:@[idDescriptor]];
		NSNumber *newID = [NSNumber numberWithInt:[[sortedByID[0] objectForKey:kMTTiVoID] intValue]+1];
        [tiVos addObject:@{@"enabled" : [NSNumber numberWithBool:NO], kMTTiVoUserName : @"TiVo Name", kMTTiVoIPAddress : @"0.0.0.0", kMTTiVoUserPort : @"80", kMTTiVoUserPortSSL : @"443", kMTTiVoID : newID, kMTTiVoManualTiVo : @YES, kMTTiVoMediaKey : @""}];
    }
    [[NSUserDefaults standardUserDefaults] setValue:tiVos forKeyPath:kMTTiVos];
}


-(void)dealloc
{
	[[NSUserDefaults standardUserDefaults] removeObserver:self forKeyPath:kMTManualTiVos];
}

@end
