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
@property (weak) IBOutlet NSTableView *manualTiVosTableView;
@property (weak) IBOutlet NSTableView *networkTiVosTableView;
@property (weak) IBOutlet NSProgressIndicator *tiVoLoadingSpinner;

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
	[self.tiVoLoadingSpinner stopAnimation:nil];
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
    [tiVos addObject:@{@"enabled" : @NO, kMTTiVoUserName : @"TiVo Default", kMTTiVoIPAddress : @"0.0.0.0", kMTTiVoUserPort : @"80", kMTTiVoUserPortSSL : @"443", kMTTiVoUserPortRPC: @"1413", kMTTiVoID : @(newID), kMTTiVoTSN : @"", kMTTiVoManualTiVo : @YES, kMTTiVoMediaKey : kMTTiVoNullKey}];
   [[NSUserDefaults standardUserDefaults] setValue:tiVos forKeyPath:kMTTiVos];
}

-(IBAction) help:(id)sender {
	[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString: @"https://github.com/mackworth/cTiVo/wiki/Advanced-Topics#manual-tivos"]];
}

-(BOOL) validateMenuItem:(NSMenuItem *)menuItem {
	if (menuItem.action == @selector(reportTiVoInfo:)) {
		NSTableView * tableView = (NSTableView *) [self.view.window firstResponder];
		if (![tableView isKindOfClass: [NSTableView class] ]) return NO;
		NSDictionary * tiVoDescription = [self selectedTiVo:tableView];
		if (!tiVoDescription) return NO;
		BOOL enabled = ((NSNumber *) tiVoDescription[kMTTiVoEnabled]).boolValue;
		return enabled;
	} else {
		return YES;
	}
}

-(IBAction) reportTiVoInfo: (NSView *) sender {
	[self doubleClickTable:(NSTableView *) [self.view.window firstResponder]];
}

-(NSDictionary *) selectedTiVo: (NSTableView *) tableView  {
	NSArrayController * controller = nil;
	if (tableView == self.networkTiVosTableView  ) {
		controller = networkTiVoArrayController;
	} else if (tableView == self.manualTiVosTableView) {
		controller = manualTiVoArrayController;
	} else {
		return nil;
	}
	NSArray * selected = [controller selectedObjects];
	if (selected.count == 0) return nil;
	return [selected firstObject];
}
								 
-(IBAction) doubleClickTable:(NSTableView *) tableView {
	if (![tableView isKindOfClass: [NSTableView class] ]) return;

	NSDictionary * tiVoDescription = [self selectedTiVo:tableView] ;
	if (!tiVoDescription) return;
	
	NSArray * allTiVos = [[tiVoManager tiVoList] arrayByAddingObjectsFromArray:[tiVoManager tiVoMinis]];
	for (MTTiVo * candidate in allTiVos) {
		if ([candidate isEqualToDescription:tiVoDescription]) {
			if (candidate.rpcActive) {
				[self.tiVoLoadingSpinner startAnimation:nil];
				[candidate tiVoInfoWithCompletion:^(NSString *status) {
					[self.tiVoLoadingSpinner stopAnimation:nil];
					if (status) {
						NSAlert *alert = [[NSAlert alloc] init];
						NSString * name = candidate.tiVo.name ?:@"Unknown name";
						[alert setMessageText:name];
						[alert setInformativeText:status];
						[alert addButtonWithTitle:@"OK"];
						[alert setAlertStyle:NSAlertStyleInformational];

						[alert beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse returnCode) {
							}];
					}
				}];
			}
			return;
		}
	}
	NSAlert *alert = [[NSAlert alloc] init];
	[alert setMessageText: tiVoDescription[@"userName"] ?: @"Unnamed TiVo"];
	[alert setInformativeText:@"TiVo not found?"];
	[alert addButtonWithTitle:@"OK"];
	[alert setAlertStyle:NSAlertStyleInformational];

	[alert beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse returnCode) {
	}];
	
}

-(void)dealloc
{
	[[NSUserDefaults standardUserDefaults] removeObserver:self forKeyPath:kMTTiVos];
}

@end
