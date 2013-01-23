//
//  MTiTunes.m
//  cTiVo
//
//  Copyright (c) 2012 Scott Buchanan. All rights reserved.
//

#import "MTiTunes.h"
#import "iTunes.h"


@implementation MTiTunes


-(SBApplication *) iTunes {
	if (!_iTunes || ![_iTunes isRunning]){
		_iTunes = [SBApplication applicationWithBundleIdentifier:@"com.apple.iTunes"];
	}
	return _iTunes;

}

-(iTunesSource *) iTunesLibrary   {
	if (!_iTunesLibrary || ![_libraryPlayList exists]) {
		NSPredicate * libraryKindPred = [NSPredicate predicateWithFormat:@"kind == %@",[NSAppleEventDescriptor descriptorWithTypeCode:iTunesESrcLibrary]];
		NSArray *librarySources = [[self.iTunes sources] filteredArrayUsingPredicate:libraryKindPred];
		if ([librarySources count] > 0){
			_iTunesLibrary = [librarySources objectAtIndex:0];
	
		}
	}
	return _iTunesLibrary;

}

-(iTunesLibraryPlaylist *) libraryPlayList {
	if (!_libraryPlayList|| ![_libraryPlayList exists]) {
		SBElementArray * allLists = [[self iTunesLibrary] libraryPlaylists];
		if (allLists.count > 0) {
				
			iTunesPlaylist * list = [allLists objectAtIndex:0];
			if ([list exists])
				_libraryPlayList = (iTunesLibraryPlaylist *)list;

		}
	}
	return _libraryPlayList;
}

-(iTunesPlaylist *) tivoPlayList {
	if (!_tivoPlayList || ![_tivoPlayList exists]) {
		SBElementArray * allLists = [[self iTunesLibrary] playlists];
		NSPredicate * libraryKindPred = [NSPredicate predicateWithFormat:@"name LIKE[CD] %@ ",@"Tivo Shows"];
		NSArray *TivoLists = [allLists filteredArrayUsingPredicate:libraryKindPred];
		if ([TivoLists count] > 0){
			_tivoPlayList = [TivoLists objectAtIndex:0];
			
		}
		if (!_tivoPlayList || ![_tivoPlayList exists]) {
			//No playlist found; create one
			NSDictionary *props = @{
				@"name":@"Tivo Shows",
				//@"specialKind":[NSNumber numberWithInt:iTunesESpKMovies],
			};
			iTunesPlaylist * newPlayList = [[[[self iTunes] classForScriptingClass:@"playlist" ] alloc ] initWithProperties:props ];
			
			//newPlayList.specialKind = iTunesESpKMovies;
			if (newPlayList ) {
				[allLists  insertObject:newPlayList atIndex:[allLists count]-1];
				if ([newPlayList exists])
					newPlayList.name = @"Tivo Shows";
					_tivoPlayList = newPlayList;
			}
		}
	}
	return _tivoPlayList;
}


-(BOOL) importIntoiTunes: (MTTiVoShow * ) show {
	//Caller responsible for informing user of progress
	// There can be a long delay as iTunes starts up
	NSURL * showFileURL = [NSURL fileURLWithPath:show.encodeFilePath];
	
	
	
	iTunesTrack * newTrack = [self.iTunes add:@[showFileURL] to: [self tivoPlayList] ];
	if ([newTrack exists]) {
		NSLog(@"Added iTunes track:  %@", show.showTitle);

		if (show.isMovie) {
			newTrack.videoKind = iTunesEVdKMovie;
			newTrack.name = show.showTitle;
		} else {
			newTrack.videoKind = iTunesEVdKTVShow;
			newTrack.album = show.seriesTitle;
			newTrack.albumArtist = show.seriesTitle;
			if (show.episodeTitle.length ==0) {
                NSDateFormatter *dateFormat = [[[NSDateFormatter alloc] init] autorelease];
                [dateFormat setDateStyle:NSDateFormatterShortStyle];
                [dateFormat setTimeStyle:NSDateFormatterNoStyle];
				newTrack.name = [NSString stringWithFormat:@"%@ - %@",show.showTitle, [dateFormat stringFromDate: show.showDate ]];
			} else {
				newTrack.name = show.episodeTitle;
			}
			newTrack.episodeID = [NSString stringWithFormat:@"%d", show.showID];
            newTrack.episodeNumber = show.episode;
            newTrack.seasonNumber = show.season;
		}
		newTrack.comment = show.showDescription;
		newTrack.longDescription = show.showDescription;
		newTrack.objectDescription = show.showDescription;
		newTrack.show = show.seriesTitle;
		newTrack.year = show.episodeYear;
		newTrack.genre = show.episodeGenre;
	/* haven't bothered with:
	 tell application "Finder"
	 set comment of this_item2 to (((show_name as string) & " - " & episodeName as string) & " - " & file_description as string)
	 
	 end tell
	 */
		return YES;
	} else {
		NSLog(@"Couldn't add iTunes track: %@ (%@)from %@", show.showTitle, show.encodeFormat.name, showFileURL );
		return NO;
	}
    if ([[NSUserDefaults standardUserDefaults] boolForKey:kMTiTunesSync]) {
		[self updateAllIDevices];
	}
}

- (void) updateAllIDevices {
    SBElementArray * sources = [[self iTunes] sources];
    for (iTunesSource * iPod in sources) {
        [iPod update];
    }

}

@end
