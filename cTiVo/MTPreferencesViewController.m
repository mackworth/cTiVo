//
//  MTPreferencesViewController.m
//  cTiVo
//
//  Created by Scott Buchanan on 1/27/13.
//  Copyright (c) 2013 Scott Buchanan. All rights reserved.
//

#import "MTPreferencesViewController.h"
#import "MTTiVoManager.h"
#import "MTHelpViewController.h"

@interface MTPreferencesViewController ()
@property (weak, nonatomic) IBOutlet NSPopUpButton *directoryFormatPopup;
@property (weak, nonatomic) IBOutlet NSMenuItem *perModuleMenuItem;
@property (weak, nonatomic) IBOutlet NSMenuItem *tiVoArtworkItem;
@property (weak) IBOutlet NSButton *addToiTunes;
@property (weak) IBOutlet NSButton *deleteFromItunes;
@property (weak) IBOutlet NSButton *AutoSynciTunes;
@property (weak) IBOutlet NSTextField *iTunesSection;

@end

@implementation MTPreferencesViewController

-(void)changeButtonToAppleTV: (NSButton *) button {
    button.title = [button.title stringByReplacingOccurrencesOfString:@"iTunes" withString:@"TV" ];
    button.toolTip = [button.toolTip stringByReplacingOccurrencesOfString:@"iTunes" withString:@"Apple's TV app" ];
    [button sizeToFit];
}
                         
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
	if (@available(macOS 10.15, *)) {
        self.iTunesSection.cell.title = @"Apple's TV app (TV):"; [self.iTunesSection sizeToFit];
        [self changeButtonToAppleTV: self.addToiTunes];
        [self changeButtonToAppleTV: self.deleteFromItunes];
		self.AutoSynciTunes.hidden = YES;
	}
}

-(BOOL) validateMenuItem:(NSMenuItem *)menuItem {
    if ([menuItem.title isEqualToString: @"TiVo"]) {
        for (MTTiVo *tiVo in tiVoManager.tiVoList) {
            if (tiVo.supportsRPC) return YES;
        }
        return NO;
	} else if ([menuItem.title isEqualToString:@"<Per Module>"]) {
		if ([[NSUserDefaults standardUserDefaults] integerForKey:kMTDebugLevel] > 0) {
			return NO;
		}
	}
    return YES;
}

-(BOOL) enableTivoArtwork {
	for (MTTiVo *tiVo in tiVoManager.tiVoList) {
		if (tiVo.supportsRPC) return YES;
	}
	return NO;
}

-(BOOL) enablePerModule {
	if ([[NSUserDefaults standardUserDefaults] integerForKey:kMTDebugLevel] > 0) {
		return NO;
	}
	return YES;

}
-(IBAction)commercialHelp:(id)sender {
	MTHelpViewController *helpController = [[MTHelpViewController alloc] init];
	[helpController loadResource:@"CommercialHelpFile"];
	[helpController pointToView:sender preferredEdge:NSMaxXEdge];
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
	} else {
		[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
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
	[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString: @"https://github.com/mackworth/cTiVo/wiki/Configuration#options"]];
}

-(void) dealloc {
	[[NSUserDefaults standardUserDefaults] removeObserver:self forKeyPath: kMTFileNameFormat ];
}

@end

