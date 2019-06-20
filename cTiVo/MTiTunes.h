//
//  MTiTunes.h
//  cTiVo
//
//  Copyright (c) 2012 Scott Buchanan. All rights reserved.
//

#import <Foundation/Foundation.h>

@class MTDownload;

@interface MTiTunes : NSObject {
	
}

-(void) iTunesPermissionCheck;

-(NSString *) importIntoiTunes: (MTDownload * ) download withArt:(NSImage *) image;
//returns nil if can't add; location of video file if it can
//this may be a new file if iTunes copies
//or  download.encodePath if iTunes references existing path

-(void) updateAllIDevices;
//-(void) testModule;

@end
