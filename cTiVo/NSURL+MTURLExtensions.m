//
//  NSURL+MTURLExtensions.m
//  cTiVo
//
//  Created by Hugh Mackworth on 8/29/17.
//  Copyright © 2017 cTiVo. All rights reserved.
//

#import "NSURL+MTURLExtensions.h"

@implementation NSURL (MTURLExtensions)

-(NSString *) directory {
    return [[self path] stringByDeletingLastPathComponent];
}

-(BOOL) directoryContainsURL: (NSURL *) fileURL {
    return ([[self path] isEqualToString: [fileURL directory]]);
}

-(BOOL) fileExists {
    return [self checkResourceIsReachableAndReturnError:nil];
}

@end
