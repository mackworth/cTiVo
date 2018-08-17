//
//  MTiTunes.m
//  cTiVo
//
//  Copyright (c) 2012 Scott Buchanan. All rights reserved.
//

#import "MTiTunes.h"
#import "iTunes.h"
#import "MTDownload.h"

@implementation MTiTunes

__DDLOGHERE__

-(SBApplication *) iTunes {
	if (!_iTunes || ![_iTunes isRunning]){
		_iTunes = [SBApplication applicationWithBundleIdentifier:@"com.apple.iTunes"];
		if (!_iTunes) DDLogMajor(@"couldn't find iTunes");
	}
	return _iTunes;
}

-(iTunesSource *) iTunesLibraryHelper {
	NSPredicate * libraryKindPred = [NSPredicate predicateWithFormat:@"kind == %@",[NSAppleEventDescriptor descriptorWithTypeCode:iTunesESrcLibrary]];
	SBElementArray *librarySources = [self.iTunes sources];
	[librarySources filterUsingPredicate:libraryKindPred];
	if ([librarySources count] > 0){
		return [librarySources objectAtIndex:0];
	} else {
		return nil;
	}
}

+(void) warnUserPermissions {
	if(@available(macOS 10.14, *)) {
		//trigger check
		[[NSUserDefaults standardUserDefaults] setObject:nil forKey:kMTiTunesSubmitCheck];
		[[NSUserDefaults standardUserDefaults] setBool:YES forKey:kMTiTunesSubmit];
	} else {
		NSAlert *alert2 = [NSAlert alertWithMessageText: @"Warning: cTiVo cannot access iTunes. "
										  defaultButton: @"OK"
										alternateButton: nil
											otherButton: nil
							  informativeTextWithFormat: @"Please contact cTiVo help site."];
		[alert2 runModal];
	}
}

-(iTunesSource *) iTunesLibrary   {
	if (!_iTunesLibrary || ![_libraryPlayList exists]) {
		_iTunesLibrary = [self iTunesLibraryHelper];
		if (!_iTunesLibrary) {
			DDLogReport(@"couldn't find iTunes Library. Probably permissions problem; quit cTiVo and try again.");
			dispatch_async(dispatch_get_main_queue(), ^{
				[MTiTunes warnUserPermissions];
			});
		}
	}
	return _iTunesLibrary;
}

-(BOOL) preflightiTunesCheck {
	if (@available (macOS 10.14.0, *)) {
		if (self.iTunesLibraryHelper) {
			return YES;
		} else {
			return NO;
		}
	} else {
		return YES;
	}
}

-(iTunesLibraryPlaylist *) libraryPlayList {
	if (!_libraryPlayList|| ![_libraryPlayList exists]) {
        iTunesSource * iLibrary = [self iTunesLibrary];
        if (!iLibrary) return nil;
		SBElementArray * allLists = [iLibrary libraryPlaylists];
		if (allLists.count > 0) {
				
			iTunesPlaylist * list = [allLists objectAtIndex:0];
            if ([list exists]) {
				_libraryPlayList = (iTunesLibraryPlaylist *)list;
            }
		}
        if (!_libraryPlayList) {
			DDLogMajor(@"couldn't find iTunes playList");
		}
	}
	return _libraryPlayList;
}

-(iTunesPlaylist *) tivoPlayList {
	if (!_tivoPlayList || ![_tivoPlayList exists]) {
        iTunesSource * iLibrary = [self iTunesLibrary];
        if (!iLibrary) return nil;
		SBElementArray * allLists = [iLibrary playlists];
        NSPredicate * libraryKindPred = [NSPredicate predicateWithFormat:@"name LIKE[CD] %@ ",@"Tivo Shows"];
		NSArray *TivoLists = [allLists filteredArrayUsingPredicate:libraryKindPred];
		if ([TivoLists count] > 0){
			_tivoPlayList = [TivoLists objectAtIndex:0];
        }
		if (!_tivoPlayList || ![_tivoPlayList exists]) {
			//No tivo playlist found; create one
			NSDictionary *props = @{
				@"name":@"Tivo Shows",
				//@"specialKind":[NSNumber numberWithInt:iTunesESpKMovies],
			};
			iTunesPlaylist * newPlayList = [[[[self iTunes] classForScriptingClass:@"playlist" ] alloc ] initWithProperties:props ];
			
			//newPlayList.specialKind = iTunesESpKMovies;
			if (newPlayList ) {
				[allLists  insertObject:newPlayList atIndex:[allLists count]-1];
				if ([newPlayList exists]) {
					newPlayList.name = @"Tivo Shows";
				} else {
					DDLogMajor(@"couldn't create TivoShow list");
				}
				_tivoPlayList = newPlayList;
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

-(NSString *) importIntoiTunes: (MTDownload * ) download withArt:(NSImage *) image {
	//Caller responsible for informing user of progress
	// There can be a long delay as iTunes starts up
	//maintain source code parallel with MTTivoShow.m>metadataTagsWithImage
	MTTiVoShow * show = download.show;
	NSURL * showFileURL = [NSURL fileURLWithPath:download.encodeFilePath];
    iTunesPlaylist * myPlayList = self.tivoPlayList;
    if (!myPlayList) {
        DDLogReport(@"Couldn't create TiVo playlist, because library not found. Is iTunes frozen?" );
        return nil;
    }
    iTunesFileTrack * newTrack = (iTunesFileTrack *)[self.iTunes add:@[showFileURL] to: [self tivoPlayList] ];
	NSError * error = newTrack.lastError;
	if ([newTrack exists]) {
		DDLogReport(@"Added iTunes track:  %@", show.showTitle);
		NSString * fileExtension = [[download.encodeFilePath pathExtension] uppercaseString];
		NSSet * musicTypes =[NSSet setWithObjects:@"AAC", @"MPE",@"AIF",@"WAV",@"AIFF",@"M4A",nil];
		BOOL audioOnly = [musicTypes containsObject:fileExtension] ;
		if (audioOnly) {
			newTrack.videoKind = iTunesEVdKNone;
		} else if (show.isMovie) {
			newTrack.videoKind = iTunesEVdKMovie;
		} else {
			newTrack.videoKind = iTunesEVdKTVShow;
		}

		if (show.isMovie) {
			newTrack.name = show.showTitle;
            newTrack.artist = show.directors.string;
		} else {
			if (show.season > 0) {
				newTrack.album = [NSString stringWithFormat: @"%@, Season %d",show.seriesTitle, show.season];
				newTrack.seasonNumber = show.season;
			} else {
				newTrack.album =  show.seriesTitle;
			}
			newTrack.albumArtist = show.seriesTitle;
			newTrack.artist =show.seriesTitle;
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

	/* haven't bothered with:
	 tell application "Finder"
	 set comment of this_item2 to (((show_name as string) & " - " & episodeName as string) & " - " & file_description as string)
	 
	 end tell
	 */
		if ([[NSUserDefaults standardUserDefaults] boolForKey:kMTiTunesSync]) {
			[self updateAllIDevices];
		}
		NSString * newLocation =  [[newTrack location] path];

		if ([self is:newLocation sameFileAs:download.encodeFilePath]) {
			return download.encodeFilePath;
		} else {
			return newLocation;
		}
	} else {
		DDLogReport(@"Couldn't add iTunes track: %@ (%@)from %@ because %@", show.showTitle, download.encodeFormat.name, showFileURL, [error localizedDescription] );
		DDLogVerbose(@"track: %@, itunes: %@; playList: %@", newTrack, self.iTunes, self.tivoPlayList);
		return nil;
	}
}

- (void) updateAllIDevices {
    SBElementArray * sources = [[self iTunes] sources];
    for (iTunesSource * iPod in sources) {
        [iPod update];
    }
	DDLogMajor(@"Updated all iTunes Devices");

}

@end
