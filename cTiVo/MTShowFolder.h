//
//  MTShowFolder.h
//  cTiVo
//
//  Created by Hugh Mackworth on 12/30/17.
//  Copyright © 2017 cTiVo. All rights reserved.
//

#import "MTTiVoShow.h"

@interface MTShowFolder : NSObject <NSPasteboardWriting, NSPasteboardReading, NSSecureCoding >
//this is an ugly wrapper for an array, solely to allow the use of KVC
//passed through to the array.  Would have been better to subclass, but you can't do that for an NSArray, and extending all Arrays looked even worse.

@property (nonatomic, strong) NSArray <MTTiVoShow *> * folder;

@property (nonatomic, readonly) NSString * sizeString, *lengthString;
@property (nonatomic, readonly) double fileSize;  //Cumulative size on TiVo;
@property (nonatomic, readonly)  time_t showLength;  //cumulative length of shows in seconds
@property (nonatomic, readonly) BOOL isFolder;
@property (nonatomic, readonly) NSNumber * rpcSkipMode; //only for sorting in tables
@property (nonatomic, readonly) BOOL isOnDisk;

@end

@interface NSArray (FlattenShows)
//takes an array of shows and folders, returns a flattened array
-(NSArray <MTTiVoShow *> *) flattenShows;
@end
