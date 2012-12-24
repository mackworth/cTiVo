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
		NSLog(@"new iTunes");
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


//-(void) testModule {
//	NSLog(@"Current song is %@", [[self.iTunes currentTrack] name]);
//	
//	NSLog(@"Library playlist contains %ld", self.libraryPlayList.tracks.count);
//	NSLog(@"Tivo Shows playlist contains %ld", self.tivoPlayList.tracks.count);
//	MTTiVoShow * show = [[MTTiVoShow alloc] init];
//	show.title = @"Aistream";
//	if (![self importIntoiTunes:@{@"fileName":@"/Users/hughmackworth/Movies/TiVoShows/mitologia.mp4",
//	 @"Title": @"Aistream",
//	 @"ID": @(23432),
//	 @"Size": @(234333343),
//	
//	@"episodeNum": @(23),
//	@"episodeYear":@(2012),
//	@"episodeLength": @(70),
//	 @"episodeGenre": @"Comedy",
//		 }]) NSLog(@"Ooops");
//	NSLog(@"Tivo Shows playlist contains %ld", self.tivoPlayList.tracks.count);
//
//}

-(BOOL) importIntoiTunes: (MTTiVoShow * ) show {
	//Caller responsible for informing user of progress
	// There can be a long delay as iTunes starts up
	NSURL * showFileURL = [NSURL fileURLWithPath:show.targetFilePath];
	NSLog(@"%@",showFileURL);
	
	
	//NSLog(@"adding %@",trackName);
	iTunesTrack * newTrack = [self.iTunes add:@[showFileURL] to: [self tivoPlayList] ];
	if ([newTrack exists]) {
		NSLog(@"Added track: %@", newTrack);

		if ((show.episodeTitle.length ==0) &&
			([show.episodeNumber intValue] == 0) &&
			(show.showLength > 70) ) {
			newTrack.videoKind = iTunesEVdKMovie;
			newTrack.name = show.episodeTitle;
		} else {
			newTrack.videoKind = iTunesEVdKTVShow;
			newTrack.album = show.episodeTitle;
			newTrack.albumArtist = show.episodeTitle;
			if (show.episodeTitle.length ==0) {
				newTrack.name = [NSString stringWithFormat:@"%@ - %d",show.episodeTitle, show.showID];
				newTrack.episodeID = [NSString stringWithFormat:@"%d", show.showID];
			} else {
				newTrack.name = show.episodeTitle;
				newTrack.episodeID = show.episodeTitle;
			}
			if ([show.episodeNumber intValue] > 0) {
				newTrack.episodeNumber = [show.episodeNumber intValue];
			}
			
		}
		newTrack.comment = show.description;
		newTrack.longDescription = show.description;
		newTrack.show = show.episodeTitle;
		newTrack.year = show.episodeYear;
		newTrack.genre = show.episodeGenre;
	/* haven't bothered with:
	 tell application "Finder"
	 set comment of this_item2 to (((show_name as string) & " - " & episodeName as string) & " - " & file_description as string)
	 
	 end tell
	 */
		return YES;
	} else {
		NSLog(@"Couldn't add track: %@ from %@", show.showTitle, showFileURL);
		return NO;
	}
}

@end
