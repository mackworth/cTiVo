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

@interface MTRemoteWindowController ()<NSWindowDelegate>
@property (nonatomic, weak) IBOutlet NSPopUpButton * tivoListPopup;
@property (nonatomic, strong) NSArray <MTTiVo *> * tiVoList;
@property (nonatomic, readonly) MTTiVo * selectedTiVo;
@property (nonatomic, weak) IBOutlet NSImageView * tivoRemote;
@property (nonatomic, weak) IBOutlet NSMenu * serviceMenu;
@property (weak) IBOutlet NSProgressIndicator *infoLoadingSpinner;
@end

@implementation MTRemoteWindowController

__DDLOGHERE__

-(instancetype) init {
	if ((self = [self initWithWindowNibName:@"MTRemoteWindowController"])) {
		[self updateTiVoList];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateTiVoList) name:kMTNotificationTiVoListUpdated object:nil];
        self.window.contentAspectRatio = self.tivoRemote.image.size;
    };
	self.window.delegate = self;
	return self;
}

- (void)windowDidResignKey:(NSNotification *)notification {
	[self.infoLoadingSpinner stopAnimation:nil];
}

- (NSSize)windowWillResize:(NSWindow *)sender
					toSize:(NSSize)frameSize {
	if (isnan(frameSize.height)) {
		//who knows why the OS is sending us this...?
		frameSize.height = frameSize.width * (sender.frame.size.height/ sender.frame.size.width);
	}
	return frameSize;
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
	for (MTTiVo * tivo in [tiVoManager tiVoMinis]) {
		if (tivo.enabled && tivo.rpcActive) {
			[newList addObject:tivo];
		}
	}
	self.tiVoList = [newList copy];
}

-(IBAction)netflixButton:(NSButton *) sender {
	[NSMenu popUpContextMenu:self.serviceMenu
				   withEvent: NSApplication.sharedApplication.currentEvent
							   forView:(NSButton *)sender];
}

-(IBAction)rebootTiVo:(NSButton *) sender {
	NSString *message = [NSString stringWithFormat:@"Are you sure you want to reboot your TiVo %@?", self.selectedTiVo.tiVo.name];
	NSAlert *keyAlert = [NSAlert alertWithMessageText:message defaultButton:@"Cancel" alternateButton:@"Reboot" otherButton:nil informativeTextWithFormat:@"Warning: this will immediately reboot your TiVo, interrupting all downloads, recordings, etc. for several minutes."];
	
	NSInteger button = [keyAlert runModal];
	if (button == NSAlertAlternateReturn) {
		DDLogMajor(@"Rebooting TiVo %@",self.selectedTiVo);
		[self.selectedTiVo reboot];
	}
}

- (IBAction)serviceMenuSelected:(NSPopUpButton *)sender {
	NSMenuItem * item = sender.selectedItem;
	if (!item) return;
	NSDictionary * commands = @{
	  @"Netflix" 		:   @"x-tivo:netflix:netflix",
	  @"HBO Go"			: 	@"x-tivo:web:https://tivo.hbogo.com",
	  @"Amazon Prime"	: 	@"x-tivo:web:https://atv-ext.amazon.com/blast-app-hosting/html5/index.html?deviceTypeID=A3UXGKN0EORVOF",
	  @"Hulu"			: 	@"x-tivo:web:https://tivo.app.hulu.com/cube/prod/tivo/hosted/index.html",
	  @"Epix"			: 	@"x-tivo:web:https://tivoapp.epix.com/",
	  @"YouTube"		: 	@"x-tivo:web:https://www.youtube.com/tv",
	  @"Vudu"			: 	@"x-tivo:vudu:vudu",
	  @"Plex"			: 	@"x-tivo:web:https://plex.tv/web/tv/tivo",
	  
	  @"Alt TV"			: 	@"x-tivo:web:https://channels.wurl.com/launch",
	  @"AOL"			: 	@"x-tivo:web:https://ott.on.aol.com/ott/tivo_tv/homepage?secure=false",
	  @"FlixFling"		: 	@"x-tivo:web:https://tv.flixfling.com/tivo",
	  @"HSN"			: 	@"x-tivo:web:https://tivo.hsn.com/home.aspx",
	  @"iHeart Radio"	: 	@"x-tivo:web:https://tv.iheart.com/tivo/",
	  @"MLB"			: 	@"x-tivo:web:https://secure.mlb.com/ce/tivo/index.html",
	  @"Music Choice"	: 	@"x-tivo:web:https://tivo.musicchoice.com/tivo",
	  @"Toon Goggles"	: 	@"x-tivo:web:https://html5.toongoggles.com",
	  @"Tubi TV"		: 	@"x-tivo:web:https://ott-tivo.tubitv.com/",
	  @"Vevo"			: 	@"x-tivo:web:https://tivo.vevo.com/index.html",
	  @"Vewd"			: 	@"x-tivo:web:tvstore",
	  @"Wurl TV"		: 	@"x-tivo:web:http://channels.wurl.com/tune/channel/ign_e3_live?lp=tvdb",
	  @"WWE"			: 	@"x-tivo:web:https://secure.net.wwe.com/ce/tivo/index.html",
	  @"Yahoo"			: 	@"x-tivo:web:https://smarttv-screen.manhattan.yahoo.com/v2/e/production?man=tivo",
	  @"YuppTV"			: 	@"x-tivo:web:https://www.yupptv.com/tivo/index.html",

	  
//	  @"Evue": 	@"x-tivo:web:http://evueapp.evuetv.com/evuetv/tivo/init.php",  //Not authrized
//	  @"Spotify": 	@"x-tivo:web:https://d27nv3bwly96dm.cloudfront.net/indexOperav2.html",  //no reaction
//	  @"YouTube Flash" 	: @"x-tivo:flash:uuid:B8CEA236-0C3D-41DA-9711-ED220480778E",
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

-(IBAction) reportTiVoInfo: (id) sender {
	NSString * name = self.selectedTiVo.tiVo.name;
	__weak __typeof__(self) weakSelf = self;
	if (!name) return;
	[self.infoLoadingSpinner startAnimation:nil];
	[self.selectedTiVo tiVoInfoWithCompletion:^(NSString *status) {
		[self.infoLoadingSpinner stopAnimation:nil];
		NSAlert *alert = [[NSAlert alloc] init];
		[alert setMessageText:name];
		[alert setInformativeText:status];
		[alert addButtonWithTitle:@"OK"];
		[alert setAlertStyle:NSAlertStyleInformational];

		[alert beginSheetModalForWindow:weakSelf.window completionHandler:^(NSModalResponse returnCode) {
		}];

	}];
}

-(void) dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
