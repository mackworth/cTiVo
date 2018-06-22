//
//  NSViewController.m
//  cTiVo
//
//  Created by Hugh Mackworth on 2/6/18.
//  Copyright © 2018 cTiVo. All rights reserved.
//

#import "MTRemoteWindowController.h"
#import "MTTiVoManager.h"
#import "NSNotificationCenter+Threads.h"

@interface MTRemoteWindowController ()
@property (nonatomic, weak) IBOutlet NSPopUpButton * tivoListPopup;
@property (nonatomic, strong) NSArray <MTTiVo *> * tiVoList;
@property (nonatomic, readonly) MTTiVo * selectedTiVo;
@property (nonatomic, weak) IBOutlet NSImageView * tivoRemote;
@end

@implementation MTRemoteWindowController

__DDLOGHERE__

-(instancetype) init {
	if ((self = [self initWithWindowNibName:@"MTRemoteWindowController"])) {
		[self updateTiVoList];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateTiVoList) name:kMTNotificationTiVoListUpdated object:nil];
		
        self.window.contentAspectRatio = self.tivoRemote.image.size;
    };
	return self;
}

-(void) whatsOn {
	[self.selectedTiVo whatsOnWithCompletion:^(MTWhatsOnType whatsOn, NSString *recordingID) {
		switch (whatsOn) {
			case MTWhatsOnUnknown:
				DDLogReport(@"Tivo is showing unknown %@", recordingID);
				break;
			case MTWhatsOnLiveTV:
				DDLogReport(@"Tivo is showing live TV %@", recordingID);
				break;
			case MTWhatsOnRecording:
				DDLogReport(@"Tivo is showing a recording %@", recordingID);
				break;
			case MTWhatsOnStreamingOrMenus:
				DDLogReport(@"Tivo is in menus or streaming %@", recordingID);
				break;
			default:
				break;
		}
	}];
}
	 
-(MTTiVo *) selectedTiVo {
	MTTiVo* tivo = nil;
	if (self.tiVoList.count > 0) {
		NSInteger index = MIN(MAX(self.tivoListPopup.indexOfSelectedItem,0), ((NSInteger) self.tiVoList.count)-1);
		tivo = self.tiVoList[index];
	}
	return tivo;
}
-(void) updateTiVoList {
	NSMutableArray * newList = [NSMutableArray array];
	for (MTTiVo * tivo in [tiVoManager tiVoList]) {
		if (tivo.enabled && tivo.rpcActive) {
			[newList addObject:tivo];
		}
	}
	self.tiVoList = [newList copy];
}

-(IBAction)netflixButton:(NSButton *) sender {
	[self.selectedTiVo sendURL: @"x-tivo:netflix:netflix"];
}
- (IBAction)serviceMenuSelected:(NSPopUpButton *)sender {
	NSMenuItem * item = sender.selectedItem;
	if (!item) return;
	NSDictionary * commands = @{
	  @"Netflix (html)" : @"x-tivo:netflix:netflix",
	  @"Plex" 			: @"x-tivo:web:https://plex.tv/web/tv/tivo",
//	  @"Spotify" 		: @"x-tivo:web:https://d27nv3bwly96dm.cloudfront.net/indexOperav2.html",
	  @"Vewd" 			: @"x-tivo:web:tvstore",
	  @"Vewd Apps" 	    : @"x-tivo:web:tvstore:https://tivo.tvstore.opera.com/?startwith=myapps",
	  @"iHeart Radio" 	: @"x-tivo:web:https://tv.iheart.com/tivo/",
//	  @"YouTube Flash" 	: @"x-tivo:flash:uuid:B8CEA236-0C3D-41DA-9711-ED220480778E",
	  @"YouTube HTML" 	: @"x-tivo:web:https://www.youtube.com/tv",
	  @"Amazon Prime" 	: @"x-tivo:web:https://atv-ext.amazon.com/cdp/resources/app_host/index.html?deviceTypeID=A3UXGKN0EORVOF",
	  @"Vudu" 			: @"x-tivo:vudu:vudu",
//	  @"Amazon"			: @"x-tivo:hbogo:hbogo"
	  
//	  @"Amazon" 		: @"x-tivo:hme:uuid:35FE011C-3850-2228-FBC5-1B9EDBBE5863",
//	  @"Hulu Plus" 		: @"x-tivo:flash:uuid:802897EB-D16B-40C8-AEEF-0CCADB480559",
//	  @"AOL On"			: @"x-tivo:flash:uuid:EA1DEF9D-D346-4284-91A0-FEA8EAF4CD39",
//	  @"Launchpad" 		: @"x-tivo:flash:uuid:545E064D-C899-407E-9814-69A021D68DAD"
	  };
	[self.selectedTiVo sendURL: commands[item.title]];
	 
}

-(IBAction)buttonPressed:(NSButton *)sender {
	if (!sender.title) return;
	[self.selectedTiVo sendKeyEvent: sender.title];
}

-(void) dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
