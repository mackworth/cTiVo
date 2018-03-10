//
//  NSDate+Tomorrow.h
//  cTiVo
//
//  Created by Hugh Mackworth on 3/8/18.
//  Copyright © 2018 cTiVo. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NSDate (Tomorrow)

-(double) secondsUntilNextTimeOfDay;

+(NSDate *) tomorrowAtTime: (NSInteger) minutes;

@end
