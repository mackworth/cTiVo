//
//  MTiTunes.m
//  cTiVo
//
//  Copyright (c) 2012 Scott Buchanan. All rights reserved.
//

#import "MTiTunes.h"
#import "iTunes.h"
#import "MTDownload.h"

@interface MTiTunes()
@property (nonatomic, strong) iTunesApplication *iTunes;
@property (nonatomic, strong) iTunesSource *iTunesLibrary;
@property (nonatomic, strong) iTunesLibraryPlaylist *libraryPlayList;
@property (nonatomic, strong) iTunesPlaylist *tivoPlayList;
@property (nonatomic, assign) BOOL audioOnly;
@end

@implementation MTiTunes

__DDLOGHERE__

-(SBApplication *) iTunes {
	if (!_iTunes || ![_iTunes isRunning]){
            _iTunes = [SBApplication applicationWithBundleIdentifier:[self appBundleName]];
        if (!_iTunes) {
            DDLogMajor(@"couldn't find %@ application", [self appName]);
        }
	}
	return _iTunes;
}

-(iTunesSource *) iTunesLibraryHelper {
	NSArray<iTunesSource *> *librarySources = [[self.iTunes sources] get];
    for ( iTunesSource * source in librarySources) {
        if (source.kind == iTunesESrcLibrary) {
            return source;
        }
    }
    return nil;
}

-(iTunesSource *) iTunesLibrary   {
	if (!_iTunesLibrary) {
		_iTunesLibrary = [self iTunesLibraryHelper];
		if (!_iTunesLibrary) {
			DDLogReport(@"couldn't find %@ Library. Probably permissions problem.", [self appName]);
			[self warnUserPermissions];
			_iTunesLibrary = [self iTunesLibraryHelper];
			
		}
	}
	return _iTunesLibrary;
}


-(iTunesLibraryPlaylist *) libraryPlayList {
	if (!_libraryPlayList|| ![_libraryPlayList exists]) {
        iTunesSource * iLibrary = [self iTunesLibrary];
        if (!iLibrary) return nil;
		NSArray <iTunesLibraryPlaylist *> * allLists = [[iLibrary libraryPlaylists] get];
		if (allLists.count > 0) {
            _libraryPlayList = allLists[0];
		}
        if (!_libraryPlayList) {
			DDLogMajor(@"couldn't find %@ playList", [self appName]);
		}
	}
	return _libraryPlayList;
}

-(iTunesPlaylist *) tivoPlayList {
	if (!_tivoPlayList) {
        iTunesSource * iLibrary = [self iTunesLibrary];
        if (!iLibrary) return nil;
		NSArray<iTunesPlaylist *> * allLists = [[iLibrary playlists] get];
        for ( iTunesPlaylist * playList in allLists) {
            if ([playList.name isEqualToString: @"Tivo Shows"]) {
                _tivoPlayList = playList;
                break;
            }
        }
		if (!_tivoPlayList ) {
			//No tivo playlist found; create one
			NSDictionary *props = @{
				@"name":@"Tivo Shows",
				//@"specialKind":[NSNumber numberWithInt:iTunesESpKMovies],
			};
			iTunesPlaylist * newPlayList = [[[[self iTunes] classForScriptingClass:@"playlist" ] alloc ] initWithProperties:props ];
			
			if (newPlayList ) {
				[[iLibrary playlists]  insertObject:newPlayList atIndex:[allLists count]-1];
				if ([newPlayList exists]) {
					newPlayList.name = @"Tivo Shows";
				} else {
					DDLogMajor(@"couldn't create Tivo Shows list");
				}
				_tivoPlayList = newPlayList;
			} else {
				DDLogMajor(@"No playlist created.");
			}
		}
	}
	return _tivoPlayList;
}

-(unsigned long) deviceNumber:(NSDictionary *) attributes {
	NSNumber * deviceNum = attributes[NSFileDeviceIdentifier];
	return deviceNum.unsignedLongValue;
}

-(unsigned long) fileNumber:(NSDictionary *) attributes {
	NSNumber * fileNum = attributes [NSFileSystemFileNumber];
	return fileNum.unsignedLongValue;
}

- (BOOL) is: (NSString *) pathA sameFileAs: (NSString *) pathB {
	NSDictionary * attributesA = [[NSFileManager defaultManager] attributesOfItemAtPath:pathA error:nil];
	NSDictionary * attributesB = [[NSFileManager defaultManager] attributesOfItemAtPath:pathB error:nil];
	
	return ([self deviceNumber:attributesA] == [self deviceNumber:attributesB]) &&
	([self fileNumber:attributesA] == [self fileNumber:attributesB]);
}

//handles diffferences between TV and iTunes sdef
-(void) setArtist:(NSString *) artist forTrack:(iTunesFileTrack *) track {
	if (artist.length ==0) return;
	if ([track respondsToSelector:@selector(setArtist:)]) {
		[track performSelector:@selector(setArtist:) withObject:artist];
	}
	if ([track respondsToSelector:@selector(setAlbumArtist:)]) {
		[track performSelector:@selector(setAlbumArtist:) withObject:artist];
	}
}

-(void) setDirector:(NSString *)director forTrack:(iTunesFileTrack *) track {
	if (director.length ==0) return;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wundeclared-selector"
    if ([track respondsToSelector:@selector(setDirector:)]) {
		[track performSelector:@selector(setDirector:) withObject:director];
	}
#pragma clang diagnostic pop
	if ([track respondsToSelector:@selector(setArtist:)]) {
		[track performSelector:@selector(setArtist:) withObject:director];
	}
}

-(NSString *) importIntoiTunes: (MTDownload * ) download withArt:(NSImage *) image {
	//Caller responsible for informing user of progress
	// There can be a long delay as iTunes starts up
	//maintain source code parallel with MTTivoShow.m>metadataTagsWithImage
	MTTiVoShow * show = download.show;
	NSURL * showFileURL = [NSURL fileURLWithPath:download.encodeFilePath];
    NSString * fileExtension = [[download.encodeFilePath pathExtension] uppercaseString];
    NSSet * musicTypes =[NSSet setWithObjects:@"AAC", @"MPE",@"AIF",@"WAV",@"AIFF",@"M4A",@"MP3",nil];
    self.audioOnly = [musicTypes containsObject:fileExtension] ;
    iTunesLibraryPlaylist * myLibraryList = self.libraryPlayList;
    if (!myLibraryList) {
        DDLogReport(@"Couldn't create TiVo playlist, because library not found. Is %@ frozen?", [self appName] );
        return nil;
    }
    iTunesFileTrack * newTrack = (iTunesFileTrack *)[self.iTunes add:@[showFileURL] to: myLibraryList ];

    NSError * error = newTrack.lastError;
    if (newTrack && !error) {

		DDLogReport(@"Added %@ track to %@", show.showTitle, [self appName]);
        if (self.audioOnly) {
			newTrack.mediaKind = iTunesEMdKSong;
		} else if (show.isMovie) {
			newTrack.mediaKind = iTunesEMdKMovie;
		} else {
			newTrack.mediaKind = iTunesEMdKTVShow;
		}

		if (show.isMovie) {
			newTrack.name = show.showTitle;
			[self setDirector: show.directors.string forTrack:newTrack];
		} else {
			if (show.season > 0) {
				newTrack.album = [NSString stringWithFormat: @"%@, Season %d",show.seriesTitle, show.season];
				newTrack.seasonNumber = show.season;
			} else {
				newTrack.album =  show.seriesTitle;
			}
			[self setArtist: show.seriesTitle forTrack:newTrack];
			[self setDirector: show.directors.string forTrack:newTrack];
			if (show.episodeTitle.length ==0) {
				NSString * dateString = show.originalAirDateNoTime;
				if (dateString.length == 0) {
					NSDateFormatter *dateFormat = [[NSDateFormatter alloc] init];
					[dateFormat setDateStyle:NSDateFormatterShortStyle];
					[dateFormat setTimeStyle:NSDateFormatterNoStyle];
					dateString =  [dateFormat stringFromDate: show.showDate ];
				}
				newTrack.name = [NSString stringWithFormat:@"%@ - %@",show.showTitle, dateString];
			} else {
				newTrack.name = show.episodeTitle;
			}
            NSInteger episodeNum = show.episode;
            if (episodeNum == 0) episodeNum = show.episodeNumber.integerValue;
			if (episodeNum > 0) {
				newTrack.episodeNumber = show.episode;
				newTrack.trackNumber = show.episode;
			}
 		}
		newTrack.episodeID = show.episodeID;
		NSString * descrip = show.showDescription;
		if (!descrip)  descrip = @"";
		newTrack.comment = descrip;
		newTrack.longDescription = descrip;
		newTrack.objectDescription = descrip;
		newTrack.show = show.seriesTitle;
        NSString * releaseDate = show.isMovie ? show.movieYear : show.originalAirDate;
        if (releaseDate.length == 0) {
            releaseDate = show.isMovie ? show.originalAirDate : show.movieYear ;
        }
        if (releaseDate.length > 4) {
            releaseDate = [releaseDate substringToIndex:4];
        }
        NSInteger episodeYear = [releaseDate intValue];
		if (episodeYear) newTrack.year = episodeYear;
		//Can't set release date for some reason
		//No tv  channel or network concept
		newTrack.genre = show.episodeGenre;
		if (image) {
			//don't ask me why this works...
			iTunesArtwork	*artwork = [[newTrack artworks] objectAtIndex:0];
			artwork.data = image;
		}

        iTunesPlaylist * myPlayList = self.tivoPlayList;
        iTunesFileTrack * tivoShowTrack = (iTunesFileTrack *) [newTrack duplicateTo:myPlayList];
        error = tivoShowTrack.lastError;
        
		if ([[NSUserDefaults standardUserDefaults] boolForKey:kMTiTunesSync]) {
			[self updateAllIDevices];
		}
        NSString * newLocation =  [[newTrack location] path];

        if (error || !newLocation) {
            DDLogReport(@"%@ reports problem with track: %@ (%@)from %@ because %@",  [self appName], show.showTitle, download.encodeFormat.name, showFileURL, [error localizedDescription] ?: @"no reason given");
            return download.encodeFilePath;
        }  else if ([self is:newLocation sameFileAs:download.encodeFilePath]) {
			return download.encodeFilePath;
		} else {
			return newLocation;
		}
	} else {
		DDLogReport(@"Couldn't add %@ track: %@ (%@)from %@ because %@",  [self appName], show.showTitle, download.encodeFormat.name, showFileURL, [error localizedDescription] );
		DDLogVerbose(@"track: %@, itunes: %@; playList: %@", newTrack, self.iTunes, self.tivoPlayList);
		return nil;
	}
}

- (void) updateAllIDevices {
    SBElementArray * sources = [[self iTunes] sources];
    for (iTunesSource * iPod in sources) {
        if ([iPod respondsToSelector:@selector(update)]) {
            [iPod update];
        }
    }
	DDLogMajor(@"Updated all iTunes Devices");

}

#pragma mark - iTunes Permissions   Yuck.

-(void) warnUserPermissions {
	if (![NSThread isMainThread]) {
		dispatch_sync(dispatch_get_main_queue(), ^{
			[self warnUserPermissions];
		});
	} else if (@available(macOS 10.14, *)) {
		//trigger check
		[[NSUserDefaults standardUserDefaults] setBool:NO forKey:kMTiTunesSubmit];
		[[NSUserDefaults standardUserDefaults] setBool:YES forKey:kMTiTunesSubmit];
	} else {
		NSAlert *alert2 = [NSAlert alertWithMessageText: @"Warning: " kcTiVoName @" cannot access iTunes. "
										  defaultButton: @"OK"
										alternateButton: nil
											otherButton: nil
							  informativeTextWithFormat: @"Please contact " kcTiVoName @" help site."];
		[alert2 runModal];
	}
}

-(BOOL) preflightiTunesCheck {
	if (@available (macOS 10.14.0, *)) {
		_iTunesLibrary = nil;
		if (self.iTunesLibraryHelper) {
			return YES;
		} else {
			return NO;
		}
//could also use:
//		NSAppleEventDescriptor *targetAppEventDescriptor = [NSAppleEventDescriptor descriptorWithBundleIdentifier:@"com.apple.iTunes"];
//
//		OSStatus status = AEDeterminePermissionToAutomateTarget(targetAppEventDescriptor.aeDesc, typeWildCard, typeWildCard, true);
//		if (status == errAEEventNotPermitted) {
//			//(-1743): the user has declined permission.
//		} else if (status == -1744) { //errAEEventWouldRequireUserConsent) {
//			//(-1744): user consent is required for this, but the user has not yet been prompted for it.
//			//You need to pass false for askUserIfNeeded to get this.
//		} else if (status == procNotFound) {
//			//procNotFound (-600): the specified target app is not currently running.
//		} else if (status == noErr) {
//			//noErr (0): the app is authorized to send AppleEvents to the target app.
//		} else {
//			return YES;
//		}
	} else {
		return YES;
	}
}


-(void) iTunesPermissionCheck {
	//one-time check for iTunes permissions
	// state driven on kMTiTunesSubmitCheck
	//nil/0 = never run before
	//1 = has run; everything was fine
	//2 = Suggested turning on permissions, need to confirm
	//3 = Wiped out permissions, need to confirm
	//4 = User confirmed don't use iTunes; OR something bad; we give up
	if (@available(macOS 10.14, *)) {
	} else {
		return;
	}
	NSUserDefaults * defaults = [NSUserDefaults standardUserDefaults];
	if (![defaults boolForKey:kMTiTunesSubmit]) return;

	NSInteger state = [defaults integerForKey:kMTiTunesSubmitCheck];
	if (state == 1) return;

	//has to be sync on main thread, or else a current failing download won't get loaded into iTunes
	if ([self preflightiTunesCheck]) {
		[self setITunesPermissionState:1];
	} else {
		[self iTunesPermissionProcessFromState:state];
	}
}

-(void) closeiTunes {
    for ( NSRunningApplication * app in [[NSWorkspace sharedWorkspace] runningApplications] ) {
        if ( [[self appName] isEqualToString:[[app executableURL] lastPathComponent]]) {
            [app terminate];
            break;
        }
    }
}

-(void) disableITunesUse {
	[self setITunesPermissionState:4];
	[[NSUserDefaults standardUserDefaults] setBool:NO forKey:kMTiTunesSubmit]; //notifies TiVoManager to disable iTunes
}

-(void) setITunesPermissionState: (NSInteger) newstate {
	[[NSUserDefaults standardUserDefaults] setInteger:newstate forKey:kMTiTunesSubmitCheck];
}

-(void) iTunesPermissionProcessFromState: (NSInteger) state {
	switch (state) {
		case 0:
			[self closeiTunes];
			if ([self askForiTunesPermissionFix]) {
				if ([self preflightiTunesCheck]) {
					[self setITunesPermissionState:1];
				} else {
					[self setITunesPermissionState:2];
					[self warnQuitting];
					[NSApp terminate:nil];
				}
			} else {
				[self disableITunesUse];
			}
			break;
		case 2:
			[self closeiTunes];
			if ([self offerResetPermissions]) {
				if ([self preflightiTunesCheck]) {
					[self setITunesPermissionState:1];
				} else {
					[self setITunesPermissionState:3];
					[self warnQuitting];
					[NSApp terminate:nil];
				}
			} else {
				[self disableITunesUse];
			}
			break;
		case 3:
			[self warniTunesFailure];
			[self disableITunesUse];
			break;
		case 4:
			[self disableITunesUse];
			break;
		default:
			break;
	}
}

-(NSString *) appBundleName {
	if (@available(macOS 10.15, *)) {
        if (self.audioOnly) {
            return @"com.apple.Music";
        } else {
            return @"com.apple.TV";
        }
	} else {
		return @"com.apple.iTunes";
	}

}
-(NSString *) appName {
	if (@available(macOS 10.15, *)) {
        if (self.audioOnly) {
            return @"Music";
        } else {
            return @"TV";
        }
	} else {
		return @"iTunes";
	}
}

-(BOOL) askForiTunesPermissionFix {
	//ask user to fix problem
	//returns YES to try again, no if not fixed.
	NSString * msg = [NSString stringWithFormat:@"" kcTiVoName @" cannot access %@, probably due to Automation Permission problem.", [self appName]];
	NSString * altMsg = [NSString stringWithFormat:@"Disable " kcTiVoName @"'s use of %@", [self appName]];
	NSAlert *iTunesAlert = [NSAlert alertWithMessageText: msg
										   defaultButton: @"Open System Preferences"
										 alternateButton: altMsg
											 otherButton: nil
							   informativeTextWithFormat: @"You can fix in System Preferences OR disable %@ submittal", [self appName]];
	NSInteger returnValue = [iTunesAlert runModal];
	switch (returnValue) {
		case NSAlertDefaultReturn: {
			DDLogMajor(@"user asked for SysPrefs");
			NSString *urlString = @"x-apple.systempreferences:com.apple.preference.security?Privacy_Automation";
			[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:urlString]];
			return [self confirmiTunesPermissionFixed];
		}
		case NSAlertAlternateReturn:
			DDLogMajor(@"User asked to disable %@",  [self appName]);
			return NO;
			break;
		default:
			return NO;
			break;
	}
}

-(void) warnQuitting {
	NSString * msg = [NSString stringWithFormat: @"To connect to %@, " kcTiVoName @" must now quit.", [self appName]];
	NSAlert *alert2 = [NSAlert alertWithMessageText: msg
									  defaultButton: @"OK"
									alternateButton: nil
										otherButton: nil
						  informativeTextWithFormat: @"Please restart " kcTiVoName @" to check %@ access", [self appName]];
	[alert2 runModal];
}

-(BOOL) confirmiTunesPermissionFixed {
	NSString * msg = [NSString stringWithFormat:@"Please click OK when you have enabled " kcTiVoName @"'s %@ permission in Privacy.", [self appName]];
	NSString * altMsg = [NSString stringWithFormat: @"Disable " kcTiVoName @"'s use of %@", [self appName]];

	NSAlert *alert = [NSAlert alertWithMessageText: msg
									 defaultButton: @"OK"
								   alternateButton: altMsg
									   otherButton: @"No such switch??"
						 informativeTextWithFormat: @"Or you can choose to disable %@ submittal entirely.", [self appName]];
	NSInteger returnValue = [alert runModal];
	switch (returnValue) {
		case NSAlertDefaultReturn: {
			DDLogMajor(@"user said to try again");
			return YES;
			break;
		}
		case NSAlertAlternateReturn:
			DDLogMajor(@"User asked to disable %@", [self appName]);
			return NO;
			break;
		case NSAlertOtherReturn:
			return [self offerResetPermissions];
		default:
			break;
	}
	return NO; //shouldn't get here
}

-(BOOL) offerResetPermissions {
	NSString * msg = [NSString stringWithFormat:@"Still no %@ access; " kcTiVoName @" can reset macOS Automation permissions for ALL apps if you wish.", [self appName]];
	NSString * altMsg = [NSString stringWithFormat: @"Disable " kcTiVoName @"'s use of %@", [self appName]];
	NSAlert *alert = [NSAlert alertWithMessageText: msg
									 defaultButton: @"Reset Automation Permissions"
								   alternateButton: altMsg
									   otherButton: nil
						 informativeTextWithFormat: @"Or you can choose to disable %@ submittal entirely.",  [self appName]];
	NSInteger returnValue = [alert runModal];
	switch (returnValue) {
		case NSAlertDefaultReturn: {
			DDLogMajor(@"user said to reset permissions");
			NSTask *task = [[NSTask alloc] init];
			task.launchPath = @"/usr/bin/tccutil";
			task.arguments = @[@"reset", @"AppleEvents"];
			[task launch];
			[task waitUntilExit];
			return YES;
			break;
		}
		case NSAlertAlternateReturn:
			DDLogMajor(@"User asked to disable %@", [self appName]);
			return NO;
			break;
		default:
			break;
	}
	return NO; //shouldn't get here
}

-(BOOL) warniTunesFailure {
	NSString * msg = [NSString stringWithFormat:@"" kcTiVoName @" still cannot access %@.", [self appName]];
	NSAlert *alert2 = [NSAlert alertWithMessageText: msg
									  defaultButton: @"OK"
									alternateButton: nil
										otherButton: nil
						  informativeTextWithFormat: @"Please check for help at " kcTiVoName @"'s website."];
	[alert2 runModal];
	return NO;
}


@end
