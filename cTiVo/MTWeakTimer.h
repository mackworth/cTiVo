//
//  MTWeakTimerTarget.h
//  cTiVo
//
//  Created by Hugh Mackworth on 1/21/18.
//  Copyright © 2018 cTiVo. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface MTWeakTimer: NSObject

+ (NSTimer *) scheduledTimerWithTimeInterval:(NSTimeInterval)ti target:(id)aTarget selector:(SEL)aSelector userInfo:(id)userInfo repeats:(BOOL)yesOrNo;

@end
