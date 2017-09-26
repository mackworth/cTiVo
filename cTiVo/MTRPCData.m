//
//  MTRPCData.m
//  cTiVo
//
//  Created by Hugh Mackworth on 8/16/17.
//  Copyright © 2017 cTiVo. All rights reserved.
//

#import "MTRPCData.h"

@implementation MTRPCData
static NSString * kRecordingID = @"recordingID";
static NSString * kEpisodeNum  = @"episodeNum";
static NSString * kSeasonNum  = @"seasonNum";
static NSString * kGenre  = @"genre";
//static NSString * kFormat  = @"format";
static NSString * kImageURL  = @"imageURL";
static NSString * kTitle = @"title";


- (instancetype)init {
    self = [super init];
//    if (self) {
//        self.format = MPEGFormatUnknown;
//    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [self init];
    if (self) {
        _recordingID = [coder decodeObjectOfClass:[NSString class] forKey:  kRecordingID];
        _episodeNum =  [coder decodeIntegerForKey: kEpisodeNum];
        _seasonNum =   [coder decodeIntegerForKey: kSeasonNum];
        _genre =       [coder decodeObjectOfClass:[NSString class] forKey:  kGenre];
//      _format =      [coder decodeIntegerForKey: kFormat];
        _imageURL =    [coder decodeObjectOfClass:[NSString class] forKey:  kImageURL];
        _series =      [coder decodeObjectOfClass:[NSString class] forKey:  kTitle];

    }
    return self;
}

+(BOOL) supportsSecureCoding {
    return YES;
}

- (void)encodeWithCoder:(NSCoder *)coder {
     [coder encodeObject: _recordingID forKey:kRecordingID];
     [coder encodeInteger:_episodeNum forKey:kEpisodeNum];
     [coder encodeInteger:_seasonNum forKey:kSeasonNum];
     [coder encodeObject:_genre forKey:kGenre];
//     [coder encodeInteger:_format forKey:kFormat];
     [coder encodeObject:_imageURL forKey:kImageURL];
     [coder encodeObject:_series forKey:kTitle];
}

-(NSString *)description {
    return [NSString stringWithFormat:@"%@: S%0.2dE%0.2d (%@); %@; @ %@", self.series, (int)self.seasonNum, (int)self.episodeNum, self.genre, self.recordingID, self.imageURL];
}


@end
