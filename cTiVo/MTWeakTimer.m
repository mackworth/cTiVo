//
//  MTWeakTimerTarget.m
//  cTiVo
//
//  Created by Hugh Mackworth on 1/21/18.
//  Copyright © 2018 cTiVo. All rights reserved.
//


#import "MTWeakTimer.h"

@interface MTWeakTimerTarget : NSObject
@property (nonatomic, weak) id target;
@property (assign) SEL selector;
@property (nonatomic, strong) NSTimer* timer;
@end



@implementation MTWeakTimerTarget

- (void) fire: (id)userInfo {
	if (self.target) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
		[self.target performSelector:self.selector withObject:userInfo];
#pragma clang diagnostic pop
	} else {
		[self.timer invalidate];
	}
}

@end


@implementation MTWeakTimer

+ (NSTimer *) scheduledTimerWithTimeInterval:(NSTimeInterval)ti target:(id)aTarget selector:(SEL)aSelector userInfo:(id)userInfo repeats:(BOOL)yesOrNo {
	MTWeakTimerTarget* timerTarget = [[MTWeakTimerTarget alloc] init]; 
	timerTarget.target = aTarget;
	timerTarget.selector = aSelector;
	timerTarget.timer = [NSTimer scheduledTimerWithTimeInterval:ti target:timerTarget selector:@selector(fire:) userInfo:userInfo repeats:yesOrNo];
	return timerTarget.timer;
}


@end
