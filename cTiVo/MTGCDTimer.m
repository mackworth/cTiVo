//
//  MTGCDTimer.m
//

#import "MTGCDTimer.h"

@interface MTGCDTimer ()
@property (nonatomic, strong) dispatch_source_t timer;


@end
@implementation MTGCDTimer {
}

- (instancetype) initScheduledTimerWithTimeInterval:(NSTimeInterval)interval repeats:(BOOL)repeats queue:(dispatch_queue_t)queue block:(dispatch_block_t)block
{
	NSAssert(queue != NULL, @"queue can't be NULL");
	
	if ((self = [super init])) {
		self.timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);
		__weak __typeof__(self) weakSelf = self;

		dispatch_source_set_timer(self.timer,
								  dispatch_time(DISPATCH_TIME_NOW, 0),
								  interval * NSEC_PER_SEC,
								  0);
		
		dispatch_source_set_event_handler(self.timer, ^{
				  if (block) {
					  block();
				  }
				  if (!repeats) {
					  [weakSelf invalidate];
				  }
			  });
		
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, interval * NSEC_PER_SEC), queue, ^{
			__typeof__(self) strongSelf = weakSelf;
			if (strongSelf) dispatch_resume(strongSelf.timer);
		});
	}
	return self;
}

- (instancetype) initScheduledTimerWithTimeInterval:(NSTimeInterval)interval repeats:(BOOL)repeats block:(dispatch_block_t)block
{
	return self = [self initScheduledTimerWithTimeInterval:interval repeats:repeats queue:dispatch_get_main_queue() block:block];
}

- (void) dealloc
{
	dispatch_source_cancel(self.timer);
}

- (void) invalidate
{
	dispatch_source_cancel(self.timer);
}

+ (instancetype) scheduledTimerWithTimeInterval:(NSTimeInterval)interval repeats:(BOOL)repeats queue:(dispatch_queue_t)queue block:(dispatch_block_t)block
{
	return [[MTGCDTimer alloc] initScheduledTimerWithTimeInterval:interval repeats:repeats queue:queue block:block];
}

+ (instancetype) scheduledTimerWithTimeInterval:(NSTimeInterval)interval repeats:(BOOL)repeats block:(dispatch_block_t)block
{
	return [self scheduledTimerWithTimeInterval:interval repeats:repeats queue:dispatch_get_main_queue() block:block];
}

@end
