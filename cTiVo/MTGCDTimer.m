//
//  MTGCDTimer.m
//
#import "MTGCDTimer.h"

@interface MTGCDTimer ()
@property (nonatomic, strong) dispatch_source_t timer;
@end

@implementation MTGCDTimer

- (instancetype) initScheduledTimerWithTimeInterval:(NSTimeInterval)interval repeats:(BOOL)repeats queue:(dispatch_queue_t)queue block:(dispatch_block_t)block{
	NSAssert(queue != NULL, @"queue can't be NULL");
	if ((self = [super init])) {
		self.timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);
		[self nextFireTimeFromNow:interval];
		
		__weak __typeof__(self) weakSelf = self;
		dispatch_source_set_event_handler(self.timer, ^{
				  if (block) {
					  block();
				  }
				  if (!repeats) {
					  [weakSelf invalidate];
				  }
			  });
		dispatch_resume(self.timer);
	}
	return self;
}

- (instancetype) initScheduledTimerWithTimeInterval:(NSTimeInterval)interval repeats:(BOOL)repeats block:(dispatch_block_t)block{
	dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
	return [self initScheduledTimerWithTimeInterval:interval repeats:repeats queue:queue block:block];
}

+ (instancetype) scheduledTimerWithTimeInterval:(NSTimeInterval)interval repeats:(BOOL)repeats queue:(dispatch_queue_t)queue block:(dispatch_block_t)block{
	return [[MTGCDTimer alloc] initScheduledTimerWithTimeInterval:interval repeats:repeats queue:queue block:block];
}

+ (instancetype) scheduledTimerWithTimeInterval:(NSTimeInterval)interval repeats:(BOOL)repeats block:(dispatch_block_t)block{
	dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
	return [self scheduledTimerWithTimeInterval:interval repeats:repeats queue:queue block:block];
}

-(void) nextFireTimeFromNow: (NSTimeInterval) seconds {
	dispatch_source_set_timer(self.timer,
							  dispatch_time(DISPATCH_TIME_NOW, seconds * NSEC_PER_SEC),
							  seconds * NSEC_PER_SEC,
							  0);
}

- (void) invalidate{
	dispatch_source_cancel(self.timer);
}

- (void) dealloc{
	[self invalidate];
}

@end
