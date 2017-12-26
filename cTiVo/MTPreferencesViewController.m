//
//  MTPreferencesViewController.m
//  cTiVo
//
//  Created by Scott Buchanan on 1/27/13.
//  Copyright (c) 2013 Scott Buchanan. All rights reserved.
//

#import "MTPreferencesViewController.h"
#import "MTTiVoManager.h"

@interface MTPreferencesViewController ()
@property (weak, nonatomic) IBOutlet NSPopUpButton *directoryFormatPopup;
@property (weak, nonatomic) IBOutlet NSButton * helpButton;

@end

@implementation MTPreferencesViewController

-(void)awakeFromNib {
	[super awakeFromNib];
	if (!self.directoryFormatPopup) return;
	NSArray <NSMenuItem *> *formats = 	self.directoryFormatPopup.menu.itemArray;
	if (formats.count < 4) return;
	formats[0].representedObject = kMTcTiVoDefault;
	formats[1].representedObject = kMTcTiVoFolder;
	formats[2].representedObject = kMTPlexFolder;
	formats[3].representedObject = nil;
	[self.directoryFormatPopup.menu setAutoenablesItems:NO];
	formats[3].enabled = NO;
	[[NSUserDefaults standardUserDefaults] addObserver:self forKeyPath:kMTFileNameFormat options:NSKeyValueObservingOptionInitial context:nil];
}

-(IBAction)setDebugLevel:(id)sender {
	[DDLog setAllClassesLogLevelFromUserDefaults: kMTDebugLevel];
}

-(BOOL) validateMenuItem:(NSMenuItem *)menuItem {
    if ([menuItem.title isEqualToString: @"TiVo"]) {
        for (MTTiVo *tiVo in tiVoManager.tiVoList) {
            if (tiVo.supportsRPC) return YES;
        }
        return NO;
    }
    return YES;
}

-(void) selectDirectoryFormat {
	NSString * format = [[NSUserDefaults standardUserDefaults] stringForKey:kMTFileNameFormat];
	if (!format.length) return;
	NSArray <NSMenuItem *> *formats = 	self.directoryFormatPopup.menu.itemArray;
	[self.directoryFormatPopup selectItemAtIndex:formats.count -1 ];

	for (NSUInteger i = 0; i < formats.count-1;  i++ ) {
		 if ([format isEqual: formats[i].representedObject]){
			 [self.directoryFormatPopup selectItemAtIndex:i];
		 }
	 }
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey, id> *)change context:(void *)context {
	if ([kMTFileNameFormat isEqualToString:keyPath]) {
		[self selectDirectoryFormat];
	}
}

-(IBAction) directoryFormatSelected:(id)sender {
	NSPopUpButton * cell =  (NSPopUpButton *) sender;
	NSString * format = [cell.selectedItem representedObject];
	if (format) {
		[[NSUserDefaults standardUserDefaults] setObject:format forKey:kMTFileNameFormat];
	}
}

-(IBAction) help:(id)sender {
	[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString: @"https://github.com/dscottbuch/cTiVo/wiki/Configuration#settings-in-preferences-screen"]];
}

-(void) dealloc {
	[[NSUserDefaults standardUserDefaults] removeObserver:self forKeyPath: kMTFileNameFormat ];
}

@end

