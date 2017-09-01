//
//  NSURL+MTURLExtensions.h
//  cTiVo
//
//  Created by Hugh Mackworth on 8/29/17.
//  Copyright © 2017 cTiVo. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NSURL (MTURLExtensions)

-(NSString *) directory;
-(BOOL) directoryContainsURL: (NSURL *) fileURL;
-(BOOL) fileExists;

@end
