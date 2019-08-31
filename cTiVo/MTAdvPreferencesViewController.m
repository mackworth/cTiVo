//
//  MTAdvPreferencesViewController.m
//  cTiVo
//
//  Created by Hugh Mackworth on 2/7/13.
//  Copyright (c) 2013 Scott Buchanan. All rights reserved.
//

#import "MTAdvPreferencesViewController.h"
#import "MTTiVoManager.h"
#import "MTAppDelegate.h"
#import "NSString+Helpers.h"
#import "MTHelpViewController.h"
#import "NSTask+RunTask.h"

@interface MTAdvPreferencesViewController ()

@property (nonatomic, strong) NSArray <NSPopUpButton *> * popups;
@property (nonatomic, strong) NSArray <NSString *> * classNames;

@property (weak) IBOutlet NSPopUpButton *keywordPopup;
@property (weak) IBOutlet NSView *debugLevelView;
@property (weak) IBOutlet NSPopUpButton *masterDebugLevel;
@property (weak) IBOutlet NSPopUpButton *decodePopup;
@property (weak) IBOutlet NSTextField *fileNameField;

-(IBAction) keywordSelected:(id) sender;
-(IBAction)newDecodeValue:(id)sender;
-(IBAction)selectTmpDir:(id)sender;
-(IBAction)TVDBStatistics:(id)sender;

@end

@implementation MTAdvPreferencesViewController

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
  self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        // Initialization code here.
    }
    return self;
}

-(void) updateDebugCells {
	for (NSUInteger index = 0; index < self.popups.count ; index++) {
		NSPopUpButton * myCell = self.popups[index];
		NSInteger newVal = [DDLog levelForClass:NSClassFromString(self.classNames[index])];
		[myCell selectItemWithTag:newVal];
	}
}

-(IBAction)selectTmpDir:(id)sender {
#ifdef SANDBOX
	[[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath: tiVoManager.tmpFilesDirectory]];
#else
	[((MTAppDelegate *) [NSApp delegate]) promptForNewDirectory: tiVoManager.tmpFilesDirectory withMessage:@"Select Temp Directory for Files" isProblem:NO isTempDir:YES];
#endif
}

-(NSTextField *) newTextField: (NSRect) frame {
	NSTextField *textField;
	
    textField = [[NSTextField alloc] initWithFrame:frame];
    [textField setBezeled:NO];
    [textField setDrawsBackground:NO];
    [textField setEditable:NO];
    [textField setSelectable:NO];
	[textField setAlignment: NSRightTextAlignment ];
	[textField setFont:[NSFont systemFontOfSize:[NSFont systemFontSizeForControlSize:NSSmallControlSize]]];
	[textField setAutoresizingMask: NSViewMinXMargin | NSViewWidthSizable | NSViewMaxXMargin | NSViewMinYMargin | NSViewHeightSizable | NSViewMaxYMargin];
	return textField;
}

-(void) addDebugMenuTo:(NSPopUpButton*) cell withCurrentLevel: (NSInteger) currentLevel{
	NSArray * debugNames = @[@"None",@"Normal" ,@"Major" ,@"Detail" , @"Verbose"];
	int debugLevels[] = {LOG_LEVEL_OFF, LOG_LEVEL_REPORT, LOG_LEVEL_MAJOR, LOG_LEVEL_DETAIL, LOG_LEVEL_VERBOSE};
	
	[cell addItemsWithTitles: debugNames];
	for (int index = 0; index < cell.numberOfItems; index++) {
		//	for (NSMenuItem * item in [cell itemArray]) {
		NSMenuItem * menu = [cell itemAtIndex:index];
		menu.tag = debugLevels[index];
		if (menu.tag == currentLevel) {
			[cell selectItem:menu];
		}
	}
}

-(void) addDecodeMenuTo:(NSPopUpButton*) cell withCurrentChoice: (NSString *) level{
    NSArray * decodeNames = @[ @"tivodecode-ng",
                               @"TivoLibre"];
    NSArray * toolTips = @[ @"Traditional decoder", @"Alternate decoder (Requires Java)"];
    [cell addItemsWithTitles: decodeNames];
    for (NSUInteger i = 0; i < decodeNames.count; i++) {
        NSMenuItem *item =  [cell itemAtIndex:i];
        item.toolTip = toolTips[i];
    }
    [cell bind:@"selectedValue" toObject:[NSUserDefaults standardUserDefaults] withKeyPath:@"DecodeBinary" options:nil];
}

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem{
   if ([[menuItem title ] isEqualToString: @"TivoLibre"]) {
        return ([self javaInstalled]);
   } else if ([menuItem.title isEqualToString:@"<Per Module>"]) {
	   if ([[NSUserDefaults standardUserDefaults] integerForKey:kMTDebugLevel] > 0) {
		   return NO;
	   }
    }
    return YES;
}

#define kMTPlexSimple @"[MainTitle] - [SeriesEpNumber | OriginalAirDate] [\"- \" EpisodeTitle]"

#define kMTTestCommand @"Test on Selected Shows"

-(void) addKeywordMenuTo:(NSPopUpButton*) cell{
	NSArray * keyWords = @[
						   @"Title",  //these values must be same as those in keyword processing
						   @"MainTitle",
						   @"EpisodeTitle",
						   @"ChannelNum",
						   @"Channel",
						   @"Min",
						   @"Hour",
						   @"Wday",
						   @"Mday",
						   @"Month",
						   @"MonthNum",
						   @"Year",
						   @"OriginalAirDate",
						   @"Season",
						   @"Episode",
                           @"Guests",
						   @"EpisodeNumber",
                           @"ExtraEpisode",
						   @"SeriesEpNumber",
						   @"StartTime",
						   @"MovieYear",
						   @"TiVoName",
						   @"Format",
						   @"Options",
						   @"TVDBseriesID",
						   @"• Plex Simple",  //• means replace whole field;
						   @"• Plex Folders", //these must match below
						   @"• cTiVo Default",
						   @"• cTiVo Folders"
   						   ];
	[cell addItemsWithTitles: keyWords];

    //And add test command
    [[cell menu] addItem:[NSMenuItem separatorItem]];
    [cell addItemWithTitle: kMTTestCommand];

	for (NSMenuItem * item in cell.itemArray) {
		item.representedObject = item.title;
	}
	//and fixup the ones that are special
	NSMenuItem * plex = [cell itemWithTitle:@"• Plex Simple"];
	plex.representedObject = kMTPlexSimple;
	
	NSMenuItem * plex2 = [cell itemWithTitle:@"• Plex Folders"];
    plex2.representedObject = 	kMTPlexFolder;
	
	NSMenuItem * example = [cell itemWithTitle:@"• cTiVo Default"];
	example.representedObject = kMTcTiVoDefault;
	
	NSMenuItem * folders = [cell itemWithTitle:@"• cTiVo Folders"];
	folders.representedObject = kMTcTiVoFolder;
}

-(IBAction)testFileNames: (id) sender {
//    NSArray * testStrings  = @[
//                               @" [\"TV Shows\" / dateShowTitle / \"Season \" plexSeason / dateShowTitle \" - \" plexID [\" - \" episodeTitle]][\"Movies\" / mainTitle \" (\" movieYear \")\"]"
                               //                              @"title: [title]\nmaintitle: [maintitle]\nepisodetitle: [episodetitle]\ndateshowtitle: [dateshowtitle]\nchannelnum: [channelnum]\nchannel: [channel]\nstarttime: [starttime]\nmin: [min]\nhour: [hour]\nwday: [wday]\nmday: [mday]\nmonth: [month]\nmonthnum: [monthnum]\nyear: [year]\noriginalairdate: [originalairdate]\nepisode: [episode]\nseason: [season]\nepisodenumber: [episodenumber]\nseriesepnumber: [seriesepnumber]\ntivoname: [tivoname]\nmovieyear: [movieyear]\ntvdbseriesid: [tvdbseriesid]",
                               //                               @" [mainTitle [\"_Ep#\" EpisodeNumber]_[wday]_[month]_[mday]",
                               //                               //							   @" [mainTitle] [\"_Ep#\" EpisodeNumber]_[wday]_[month]_[mday",
                               //                               @" [mainTitle] [\"_Ep#\" EpisodeNumber]_[wday]_[month]_[mday",
                               //                               //							   @" [mainTitle] [\"_Ep# EpisodeNumber]_[wday]_[month]_[mday]",
                               //                               //							   @" [mainTitle] [\"_Ep#\" EpisodeNumber \"\"]_[wday]_[]_[mday]",
                               //                               //							   @" [mainTitle][\"_Ep#\" EpisodeNumber]_[wday]_[month]_[mday]",
                               //                               @"[mainTitle][\" (\" movieYear \")][\" (\" SeriesEpNumber \")\"][\" - \" episodeTitle]",
                               //                               @"[mainTitle / seriesEpNumber \" - \" episodeTitle][\"MOVIES\"  / mainTitle \" (\" movieYear \")"
//                               ];
//    for (NSString * str in testStrings) {
//    NSString * str = [[NSUserDefaults standardUserDefaults] objectForKey:kMTFileNameFormat];
//  NSLog(@"FOR TEST STRING %@",str);
//    [self testFileName:str];
//
    NSString * pattern = self.fileNameField.stringValue;
    NSMutableString * fileNames = [NSMutableString stringWithFormat: @"FOR TEST PATTERN >>> %@\n\n",pattern];

    NSArray	*shows = [((MTAppDelegate *) [NSApp delegate]) currentSelectedShows] ;
    for (MTTiVoShow * show in shows) {
        MTDownload * testDownload = [MTDownload downloadForShow:show withFormat:[tiVoManager selectedFormat] withQueueStatus: kMTStatusNew];
        [fileNames appendFormat:@"%@    >>>>    %@\n",show.showTitle, [testDownload.show swapKeywordsInString:pattern withFormat: [tiVoManager selectedFormat].name andOptions:@"Skip"] ];
    }

	MTHelpViewController * helpController = [[MTHelpViewController alloc] init];
	helpController.text = fileNames;
	helpController.preferredContentSize = CGSizeMake(1000, 400);
	[helpController pointToView:sender preferredEdge:NSMaxYEdge];
}

-(void) awakeFromNib {
	[super awakeFromNib];
	if (!self.debugLevelView) return; //called too soon.
	if (self.popups) return; //called twice.

	[self addKeywordMenuTo:self.keywordPopup];
    [self addDecodeMenuTo:self.decodePopup withCurrentChoice:[[NSUserDefaults standardUserDefaults] stringForKey:kMTDecodeBinary]];
	NSArray <Class> * debugClasses = [DDLog registeredClasses] ;  //all classes registered with DDLog (including autogenerated)

	NSMutableArray <NSString *> * classNames = [NSMutableArray arrayWithCapacity:debugClasses.count];
	for (Class class in debugClasses) {
		NSString * className =  NSStringFromClass(class);
		if ([className hasPrefix:@"NSKVONotifying"]) continue;
		[classNames addObject:className];
	}
	[classNames sortUsingSelector:  @selector(localizedCaseInsensitiveCompare:)];
	
	NSMutableArray <NSPopUpButton *> * popups = [NSMutableArray arrayWithCapacity:debugClasses.count ];
	int numItems = (int)[classNames count];
	int itemNum = 0;
	for (NSString * className in classNames) {
		Class class =  NSClassFromString(className);
		const CGFloat vertBase = self.debugLevelView.frame.size.height-40;
		const CGFloat horizBase = self.debugLevelView.frame.size.width;
		const int labelWidth = 160;
		const int popupHeight = 25;
		const int popupWidth = 80;
		const int vertMargin = 5;
		const int horizMargin = 10;
		const CGFloat columnWidth = horizBase/2;
		int columnNum = (itemNum < (numItems+1)/2)? 0:1;
		int rowNum = itemNum - columnNum * (numItems+1)/2;
		
		NSRect labelFrame = NSMakeRect(columnNum*columnWidth,vertBase-rowNum*(popupHeight+vertMargin)-4,labelWidth,popupHeight);
		NSTextField * label = [self newTextField:labelFrame];
		NSString * displayName = [NSString stringWithFormat:@"%@:",className];
		if ([displayName hasPrefix:@"MT"]) {
			displayName = [displayName substringFromIndex:2]; //delete "MT"
		}
		[label setStringValue:displayName];
		
		NSRect frame = NSMakeRect(columnNum*columnWidth+labelWidth+horizMargin,vertBase-rowNum*(popupHeight+vertMargin),popupWidth,popupHeight);
		NSPopUpButton * cell = [[NSPopUpButton alloc] initWithFrame:frame pullsDown:NO];
		
		cell.font= 	[NSFont systemFontOfSize:[NSFont systemFontSizeForControlSize:NSSmallControlSize]];

		[self addDebugMenuTo:cell withCurrentLevel: [DDLog levelForClass:class]];
		cell.target = self;
		cell.action = @selector(newValue:);
		
		[self.debugLevelView addSubview:label];
		[self.debugLevelView addSubview:cell];
		[popups addObject: cell];
		itemNum++;
	}
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateDebugCells) name:kMTNotificationLogLevelsUpdated object:nil ];
	self.popups = [popups copy];
	self.classNames = [classNames copy];
}

-(IBAction)TVDBStatistics:(id)sender {
    NSString * statsString = [tiVoManager.tvdb stats];

	MTHelpViewController * helpController = [[MTHelpViewController alloc] init];
	helpController.text = statsString;
	helpController.preferredContentSize = CGSizeMake(1100, 400);
	[helpController checkLinks];
	
	[helpController pointToView:sender preferredEdge:NSMaxYEdge];
}

-(IBAction) keywordSelected:(id)sender {
	NSPopUpButton * cell =  (NSPopUpButton *) sender;
	NSString * keyword = [cell.selectedItem representedObject];
	NSText * editor = [self.fileNameField currentEditor];
	NSString * current = self.fileNameField.stringValue;
	if (!editor) {
		//not selected, so select, at end of text
		[self.view.window makeFirstResponder:self.fileNameField];
		editor = [self.fileNameField currentEditor];
		[editor setSelectedRange:NSMakeRange(current.length,0)];
	}
	if ([cell.selectedItem.title hasPrefix:@"•"]) {
		//whole template, so replace whole string
		[editor setSelectedRange:NSMakeRange(0,current.length)];
    } else	if ([cell.selectedItem.title isEqualToString:kMTTestCommand]) {
        [self testFileNames:sender];
        keyword = @"";
    } else {
		//normally we add brackets around individual keywords, but not if we're inside one already
		NSUInteger cursorLoc = editor.selectedRange.location;
		NSRange beforeCursor = NSMakeRange(0,cursorLoc);
		NSInteger lastLeft = [current rangeOfString:@"[" options:NSBackwardsSearch range:beforeCursor].location;
		NSInteger lastRight = [current rangeOfString:@"]" options:NSBackwardsSearch range:beforeCursor].location;
		if (lastLeft == NSNotFound ||  //might be inside a [, but only if
			(lastRight != NSNotFound && lastRight > lastLeft)) { //we don't have a ] after it
			keyword = [NSString stringWithFormat:@"[%@]",keyword];
		} else {
			//inside a bracket, so we may want a space-delimited keywords
			unichar priorCh = [current characterAtIndex:cursorLoc-1];
			if (priorCh != '[' && priorCh != ' ') {
				keyword =[NSString stringWithFormat:@" %@ ",keyword];
			}
		}
	}
	[editor insertText:keyword];

}

-(IBAction) newValue:(id) sender {
	NSPopUpButton * cell =  (NSPopUpButton *) sender;
	NSInteger whichPopup = [self.popups indexOfObject:sender];
	NSString * className = self.classNames[whichPopup];
	
	int newVal = (int) cell.selectedItem.tag;
	[MTLogWatcher setDebugLevel:newVal forClassWithName :className];
}

-(IBAction)newDecodeValue:(id)sender {
//    NSPopUpButton * cell =  (NSPopUpButton *) sender;
//    NSString * decoder = cell.selectedItem.title;
//    [[NSUserDefaults standardUserDefaults] setObject:decoder forKey:kMTDecodeBinary];
////    [[NSUserDefaults standardUserDefaults] synchronize];
}

-(BOOL) javaInstalled {
	NSString *javaOutput = [NSTask runProgram:@"/usr/libexec/java_home" withArguments:@[]];
    return ![javaOutput hasPrefix:@"Unable"];
}

-(IBAction) help:(id)sender {
	[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString: @"https://github.com/mackworth/cTiVo/wiki/Advanced-Topics#advanced-settings"]];
}

-(IBAction)emptyCaches:(id)sender
{
    NSAlert *cacheAlert = [NSAlert alertWithMessageText:@"Emptying the caches will then reload all information from the TiVos and from TheTVDB.\nDo you want to continue?" defaultButton:@"Yes" alternateButton:@"No" otherButton:nil informativeTextWithFormat:@" "];
    NSInteger returnButton = [cacheAlert runModal];
    if (returnButton != 1) {
        return;
    }
    [tiVoManager resetAllDetails];
}

- (BOOL)windowShouldClose:(id)sender {
	//notified by PreferenceWindowController that we're going to close, so save the currently edited textField
	NSResponder * responder = [self.view.window firstResponder];
	if ([responder class] == [NSTextView class] ) {
		[self.view.window makeFirstResponder:nil ];
	}
	return YES;
}


@end
