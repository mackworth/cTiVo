//
//  MTiTunes.h
//  cTiVo
//
//  Copyright (c) 2012 Scott Buchanan. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "MTTiVoShow.h"

@class iTunesApplication, iTunesSource, iTunesLibraryPlaylist, iTunesPlaylist;

@interface MTiTunes : NSObject {
	
}

@property (nonatomic, strong) iTunesApplication *iTunes;
@property (nonatomic, strong) iTunesSource *iTunesLibrary;
@property (nonatomic, strong) iTunesLibraryPlaylist *libraryPlayList;
@property (nonatomic, strong) iTunesPlaylist *tivoPlayList;

-(BOOL) importIntoiTunes: (MTTiVoShow * ) show;
-(void) updateAllIDevices;
//-(void) testModule;

@end
