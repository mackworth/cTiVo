//
//  MTFormatEditorController.m
//  cTiVo
//
//  Created by Scott Buchanan on 1/12/13.
//  Copyright (c) 2013 Scott Buchanan. All rights reserved.
//

#import "MTFormatEditorController.h"
#import "MTTiVoManager.h"
#import "MTFormatPopUpButton.h"
#import "NSString+Helpers.h"
#import "MTFormat.h"
#import "MTHelpViewController.h"
#import "NSTask+RunTask.h"

@interface MTFormatEditorController ()
{
    IBOutlet MTFormatPopUpButton *formatPopUpButton;
    NSAlert *deleteAlert, *saveOrCancelAlert, *cancelAlert;
    IBOutlet NSButton *saveButton, *encodeHelpButton, *comSkipHelpButton;
}

@property (nonatomic, strong) MTFormat *currentFormat;
@property (nonatomic, strong) NSMutableArray *formatList;
@property (nonatomic, strong) NSNumber *shouldSave;
@property (nonatomic, strong) NSColor *validExecutableColor;
@property (nonatomic, strong) NSNumber *validExecutable;
@property (nonatomic, strong) NSString *validExecutableString;
@property (nonatomic, strong) IBOutlet NSTextField *executableTextField;
@property (nonatomic, strong) IBOutlet NSPopUpButton *presetPopup;
@property (nonatomic, assign) NSInteger customPresetStart;
@property (nonatomic, strong) NSDictionary *alertResponseInfo;
@property (weak, nonatomic) IBOutlet NSButton * helpButton;
//@property (nonatomic, strong) NSArray * ;
@end

@implementation MTFormatEditorController


//- (id)initWithWindow:(NSWindow *)window
-(id)initWithCoder:(NSCoder *)aDecoder
{
    self = [super initWithCoder:aDecoder];
    if (self) {
        // Initialization code here.
		self.validExecutableColor = [NSColor textColor];
		self.validExecutable = [NSNumber numberWithBool:YES];
		self.validExecutableString = @"No valid executable found.";
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateForFormatChange) name:kMTNotificationFormatChanged object:nil];

    }
    
    return self;
}

-(void)awakeFromNib
{
	[super awakeFromNib];
    [self launchReadPreset];
    formatPopUpButton.showHidden = YES;
    self.shouldSave = @NO;
    [self refreshFormatList];
}


-(IBAction)selectedHandbrakePreset:(id)sender {
    if (!self.presetPopup.selectedItem.enabled) return;
    BOOL customPreset = NO;
    NSInteger menuIndex = [self.presetPopup indexOfItem: self.presetPopup.selectedItem]; //-1 if not found
    if (menuIndex >= self.customPresetStart) {
        customPreset =YES;
    }

    NSString * preset = self.presetPopup.selectedItem.title;
    NSString * presetDesc = self.presetPopup.selectedItem.toolTip;
   if (self.currentFormat.isFactoryFormat.boolValue) {
        //if this is afactory one, create a user one to allow them to use it.
        [self newFormat:self];
        self.currentFormat.encoderUsed=@"HandBrakeCLI";
        [self updateForFormatChange];
    }
    
    self.currentFormat.inputFileFlag = @"-i";
    self.currentFormat.outputFileFlag = @"-o";
    self.currentFormat.name = [@"HB " stringByAppendingString:preset] ;
    self.currentFormat.regExProgress = @" ([\\d\\.]*?) \\%";
    NSString * importString = @"";
    if (customPreset) {
        importString = @"--preset-import-gui ";
    }
    self.currentFormat.encoderVideoOptions = [NSString stringWithFormat:@"%@-Z\"%@\"" , importString, preset];
    self.currentFormat.comSkip = @NO;
    NSString * extension = @".mp4";
    BOOL iTunes = YES;
    if ([preset contains:@"MKV"] || [presetDesc contains:@"MKV"]) {
        extension = @".mkv";
        iTunes = NO;
    }
    self.currentFormat.filenameExtension = extension;
    self.currentFormat.formatDescription = presetDesc;
    self.currentFormat.isHidden = @NO;
    self.currentFormat.iTunes = @(iTunes);
    [self updateForFormatChange];

}

- (void)launchReadPreset {
	NSString * cliLocation = [[NSBundle mainBundle] pathForAuxiliaryExecutable:@"HandBrakeCLI" ];
	if (!cliLocation) {
		NSLog(@"HandbrakeCLI is missing??");
		return;
	}
	NSString * handBrakeOutput = [NSTask runProgram:cliLocation withArguments:@[ @"--preset-import-gui", @"--preset-list"]];

    NSArray *presetLines = [handBrakeOutput componentsSeparatedByString:@"\n"];
    [self.presetPopup removeAllItems];
    NSString * description = @"";
    //    put a title here
    [self.presetPopup addItemWithTitle:@"HANDBRAKE PRESETS"];
    [self.presetPopup lastItem].enabled = NO;
    [self.presetPopup lastItem].target = nil;
    [self.presetPopup lastItem].onStateImage = [[NSImage alloc] initWithSize:CGSizeMake(0,0)];
    NSUInteger folderLevel = 0;
    BOOL skipFirstLines = YES;
    for (NSString * presetLine in presetLines) {
        NSUInteger indent = 0;
        while (indent < presetLine.length && [presetLine characterAtIndex:indent] == ' ') indent++;
        if (indent >= presetLine.length) continue;
        NSString * line = [presetLine substringFromIndex:indent];
        if (skipFirstLines) {
            if (![line isEqualToString:@"General/"]) continue;
            skipFirstLines = NO;
        }
        if (folderLevel > indent) folderLevel= indent; //pop up a level

        if (indent < 8 && description.length > 0) {
            [[self.presetPopup lastItem] setToolTip:description];
            description = @"";
        }
        if ([line hasSuffix:@"/"]){
            //folder, but we only use top level ones
            if (folderLevel == 0) {
                line = [line substringToIndex:line.length-1];
                [self.presetPopup.menu addItem:[NSMenuItem separatorItem]];
                [self.presetPopup addItemWithTitle:[@"        " stringByAppendingString:line]];
                [[self.presetPopup lastItem] setEnabled:NO];
                [[self.presetPopup lastItem] setTarget:nil];
            }
            folderLevel = folderLevel+4;
        } else if (indent >=  folderLevel + 4 ) {
            //description text, but may be multi-line
            if (description.length > 0) {
                description = [NSString stringWithFormat:@"%@ %@", description, line ];
            } else {
                description = line;
            }
        } else {
            //got a preset
            [self.presetPopup addItemWithTitle:line];
            [[self.presetPopup lastItem] setEnabled:YES];
            [[self.presetPopup lastItem] setTarget:self];
            [[self.presetPopup lastItem] setAction:@selector(selectedHandbrakePreset:)];
            if ([line isEqualToString:@"CLI Default"]) {
                //no other way to tell if this is a user preset
                self.customPresetStart = [self.presetPopup numberOfItems];
            }
        }
    }
    if (description.length) {
        [[self.presetPopup lastItem] setToolTip:description];
    }
}

-(void)refreshFormatList
{
	//Deepcopy array so we have new object
	self.formatList = [NSMutableArray array];
    MTFormat * selectedFormat = nil;
    NSString * searchName = self.currentFormat.name ?: tiVoManager.selectedFormat.name;
	for (MTFormat *f in tiVoManager.formatList) {
		MTFormat *newFormat = [f copy];
		[_formatList addObject:newFormat];
		newFormat.formerName = f.name;
		if ([searchName isEqualToString:newFormat.name]){
			selectedFormat = newFormat;
		}
	}
    self.currentFormat = selectedFormat ?: self.formatList[0];  //wait until after formatList is built
    [self updateForFormatChange];
}

- (BOOL)windowShouldClose:(id)sender
{
	[[NSApp keyWindow] makeFirstResponder:[NSApp keyWindow]]; //save any text edits in process
	if ([self.shouldSave boolValue]) {
		saveOrCancelAlert = [NSAlert alertWithMessageText:@"You have edited the formats.  Leaving the window will discard your changes.  Do you want to save your changes?" defaultButton:@"Save" alternateButton:@"Leave Window" otherButton:@"Continue Editing" informativeTextWithFormat:@" "];
 		[saveOrCancelAlert beginSheetModalForWindow:self.view.window ?: [NSApp keyWindow]
                                      modalDelegate:self
                                     didEndSelector:@selector(alertDidEnd:returnCode:contextInfo:)
                                        contextInfo:nil];
		self.alertResponseInfo = (NSDictionary *)sender;
		return NO;
	} else {
		[self close];
		return YES;

	}
}

- (void) alertDidEnd:(NSAlert *)alert returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo
{
	if (alert == deleteAlert) {
		if (returnCode == 1) {
            NSInteger startIndex = [formatPopUpButton indexOfItemWithRepresentedObject:_currentFormat];
            //move to next one
            NSInteger index = startIndex+1;
            MTFormat *newFormat = nil;

            while (index < formatPopUpButton.numberOfItems && ![(newFormat = [formatPopUpButton itemAtIndex:index].representedObject) isKindOfClass:[MTFormat class]]) {
                index ++;
            }
            //unless there isn't one, then move to previous one
            if (!newFormat) {
                while (index > 0 && ![(newFormat =[formatPopUpButton itemAtIndex:index].representedObject) isKindOfClass:[MTFormat class]]) {
                    index --;
                }
            }
            [self.formatList removeObject:self.currentFormat];
            if (!newFormat) newFormat = _formatList[0];
            self.currentFormat = newFormat;

			[self refreshFormatPopUp:nil];
			[self updateForFormatChange];
		}
    } else if (alert == saveOrCancelAlert) {
		switch (returnCode) {
			case 1:
				//Save changes here
				[self saveFormats:nil];
				//				[self.window close];
				[self close];
				[self alertResponse:_alertResponseInfo];
				break;
			case 0:
				//Cancel Changes here and dismiss
				//				[self.window close];
				[self close];
				[self alertResponse:_alertResponseInfo];
				break;
			case -1:
				//Don't Close the window
				break;
			default:
				break;
		}
	}
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
-(void)alertResponse:(NSDictionary *)info
{
	id target = (id)info[@"Target"];
	SEL selector = NSSelectorFromString(info[@"Selector"]);
	id argument = (id)info[@"Argument"];
	[target performSelector:selector withObject:argument];
}
#pragma clang diagnostic pop


-(void)close
{
//	[NSApp endSheet:self.window];
//	[self.window orderOut:nil];
	[self refreshFormatList]; //throw away all changes
}


//-(void)showWindow:(id)sender
//{
//	//Deepcopy array so we have new object
//    if (formatPopUpButton) {  //Clumsy way of refreshing popup selection after dismissal and re-show of window.  Need better connection
//		[self refreshFormatPopUp:nil];
//		self.currentFormat= [formatPopUpButton selectFormatNamed:tiVoManager.selectedFormat.name];
//		self.currentFormat = formatPopUpButton.selectedItem.representedObject;
//  
//         self.shouldSave = [NSNumber numberWithBool:NO];
//    }
//	[super showWindow:sender];
//    [self updateForFormatChange];
//}
//
#pragma mark - Utility Methods

-(void)updateForFormatChange
{
	self.currentFormat.name = [self checkFormatName:self.currentFormat.name];
	[self checkShouldSave];
	[self checkValidExecutable];
	[self refreshFormatPopUp:nil];
}

-(void)checkValidExecutable
{
	NSString *validPath = [_currentFormat pathForExecutable];
	if (validPath) {
        self.validExecutableColor = [NSColor textColor];
		self.validExecutableString = [NSString stringWithFormat:@"Found at %@",validPath];
        self.validExecutable = @YES;
    } else {
		if (@available(macOS 10.10, *)) {
			self.validExecutableColor = [NSColor systemRedColor];
		} else {
			self.validExecutableColor = [NSColor redColor];
		}
        self.validExecutableString = @"File not found or not executable.";
        self.validExecutable = @NO;

    }
    CGRect execFrame = self.executableTextField.frame;
    CGRect popupFrame = self.presetPopup.frame;
    if ( [[self.currentFormat.encoderUsed lowercaseString] hasPrefix:@"handbrake"]) {
        self.currentFormat.encoderUsed = @"HandBrakeCLI";
        self.executableTextField.stringValue = self.currentFormat.encoderUsed;
        //make room for preset and show it
        self.presetPopup.hidden = NO;
        CGFloat popupLeft = popupFrame.origin.x;
        execFrame.size.width = popupLeft - execFrame.origin.x - 12 ;
        self.executableTextField.frame = execFrame;
        NSString * preset = self.presetPopup.selectedItem.title;
        NSString * options = self.currentFormat.encoderVideoOptions;
        if (!preset.length || ![options contains:preset]) {
            //popup doesn't match preset (if any) in encoderVideoOptions
            //so see if we have it
            NSUInteger offset = [options rangeOfString:@"-Z\""].location;
            if (offset == NSNotFound) {
                [self.presetPopup selectItemAtIndex:0];
            } else {
                options = [options substringFromIndex:offset+3];
                offset = [options rangeOfString:@"\""].location; //ending quote
                if (offset != NSNotFound) {
                    options = [options substringToIndex:offset];
                }
                [self.presetPopup selectItemWithTitle:options];
            }
        }
        if (!self.presetPopup.selectedItem) [self.presetPopup selectItemAtIndex:0];
    } else {
        self.presetPopup.hidden = YES;
        CGFloat popupRight = popupFrame.origin.x + popupFrame.size.width;
        execFrame.size.width = popupRight ;
        self.executableTextField.frame = execFrame;
    }
}

-(void)checkShouldSave
{
	BOOL result = NO;
	if (_formatList.count != tiVoManager.formatList.count) {
		result =  YES;
	} else {
		for (MTFormat *f in _formatList) {
			MTFormat *foundFormat = [tiVoManager findFormat:f.name];
			if ( ! [f.name isEqualToString:foundFormat.name]) { //We have a new format so we should be able to save/cancel
				result = YES;
				break;
			} else if (![foundFormat isSame:f]) { //We found a format that exisit but is different.
				result = YES;
				break;
			}
		}
	}
	self.shouldSave = [NSNumber numberWithBool:result];
}

-(NSString *)checkFormatName:(NSString *)name
{
	if (!name) return nil;
	//Make sure the title isn't the same and if it is add a -1 modifier
    for (MTFormat *f in _formatList) {
		if (f == self.currentFormat) continue;  //checking our own name
		if ([name caseInsensitiveCompare:f.name] == NSOrderedSame) {
            NSRegularExpression *ending = [NSRegularExpression regularExpressionWithPattern:@"(.*)-([0-9]+)$" options:NSRegularExpressionCaseInsensitive error:nil];
            NSTextCheckingResult *result = [ending firstMatchInString:name options:NSMatchingWithoutAnchoringBounds range:NSMakeRange(0, name.length)];
            if (result) {
                int n = [[f.name substringWithRange:[result rangeAtIndex:2]] intValue];
                name = [[name substringWithRange:[result rangeAtIndex:1]] stringByAppendingFormat:@"-%d",n+1];
            } else {
                name = [name stringByAppendingString:@"-1"];
            }
           return [self checkFormatName:name];
        }
    }
	return name;
}

- (BOOL)validateValue:(id *)ioValue forKeyPath:(NSString *)inKeyPath error:(out NSError **)outError {
	if ([inKeyPath isEqualToString:@"currentFormat.name"]) {
		NSString *proposedName = (NSString *)*ioValue;
		if (proposedName == nil) return NO;
		*ioValue = [self checkFormatName:proposedName];
	}
	return YES;
}

#pragma mark - UI Actions

-(IBAction)cancelFormatEdit:(id)sender
{
	[self windowShouldClose:nil];
}

-(IBAction)selectFormat:(id)sender
{
	MTFormatPopUpButton *thisButton = (MTFormatPopUpButton *)sender;
	self.currentFormat = [[thisButton selectedItem] representedObject];
	[self updateForFormatChange];
	
}


-(IBAction)deleteFormat:(id)sender
{
	deleteAlert = [NSAlert alertWithMessageText:[NSString stringWithFormat:@"Do you want to delete the format %@ entirely?",_currentFormat.name] defaultButton:@"Yes" alternateButton:@"No" otherButton:nil informativeTextWithFormat:@" "];
 	[deleteAlert beginSheetModalForWindow:self.view.window ?: [NSApp keyWindow]
                            modalDelegate:self
                           didEndSelector:@selector(alertDidEnd:returnCode:contextInfo:)
                              contextInfo:nil];
	
}

-(IBAction)saveFormats:(id)sender
{
	[tiVoManager.formatList removeAllObjects];
	for (MTFormat *f in _formatList) {
		MTFormat *newFormat = [f copy];
		[tiVoManager.formatList addObject:newFormat];
	}
    //Now update the tiVoManger selectedFormat object and user preference
    tiVoManager.selectedFormat = [tiVoManager findFormat:tiVoManager.selectedFormat.name];
	[[NSUserDefaults standardUserDefaults] setObject:tiVoManager.userFormatDictionaries forKey:kMTFormats];

    NSMutableArray *tmpFormats = [NSMutableArray arrayWithArray:_formatList];
    [tmpFormats filterUsingPredicate:[NSPredicate predicateWithFormat:@"isFactoryFormat == %@ && isHidden == %@",@(YES),@(YES)]];
    NSMutableArray *tmpFormatNames = [NSMutableArray array];
    for (MTFormat *f in tmpFormats) {
        [tmpFormatNames addObject:f.name];
    }

    [[NSUserDefaults standardUserDefaults] setObject:tmpFormatNames forKey:kMTHiddenFormats];
	[[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationFormatListUpdated object:nil];
	[self updateForFormatChange];
}

-(IBAction)newFormat:(id)sender
{
	
	MTFormat *newFormat = [MTFormat new];
    newFormat.name = @"New Format";
    [newFormat checkAndUpdateFormatName:_formatList];
	[self.formatList addObject:newFormat];
	self.currentFormat = newFormat;
    [self updateForFormatChange];
}

-(IBAction)duplicateFormat:(id)sender
{
	MTFormat *newFormat = [_currentFormat copy];
    [newFormat checkAndUpdateFormatName:_formatList];
	newFormat.isFactoryFormat = [NSNumber numberWithBool:NO];
	[self.formatList addObject:newFormat];
	self.currentFormat = newFormat;
    [self updateForFormatChange];
}

-(void)refreshFormatPopUp:(NSNotification *)notification
{
    formatPopUpButton.formatList =  [NSArray arrayWithArray: self.formatList];
    [formatPopUpButton selectFormat:_currentFormat];
}

-(IBAction)encodeHelp:(id)sender
{
	//Get help text for encoder
	MTHelpViewController *helpController = [[MTHelpViewController alloc] init];
	if (sender == encodeHelpButton) {
		[helpController loadResource:@"EncoderHelpText"];
	} else if (sender == comSkipHelpButton) {
		[helpController loadResource:@"ComSkipHelpText"];
	}
	[helpController pointToView:sender preferredEdge:NSMaxXEdge];
}

-(IBAction) help:(id)sender {
	[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString: @"https://github.com/mackworth/cTiVo/wiki/Advanced-Topics#edit-formats"]];
}

#pragma mark - Memory Management

-(void) dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
