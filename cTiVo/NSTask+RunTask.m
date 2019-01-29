//
//  NSTask+RunTask.m
//  cTiVo
//
//  Created by Hugh Mackworth on 1/27/19.
//  Copyright © 2019 cTiVo. All rights reserved.
//

#import "NSTask+RunTask.h"

@implementation NSTask (RunTask)

+(NSString *) runProgram:(NSString *)path withArguments:(NSArray<NSString *> *)arguments {
	NSPipe *pipe = [NSPipe pipe];
	NSFileHandle *file = pipe.fileHandleForReading;
	
	NSTask *task = [[NSTask alloc] init];
	task.launchPath = path;
	task.arguments = arguments;
	task.standardOutput = pipe;
	task.standardError = pipe;
	[task launch];
	
	NSMutableData *data = [NSMutableData dataWithCapacity:512];
	while ([task isRunning]) {
		[data appendData:[file availableData]];
	}
	[data appendData:[file availableData]];
	[file closeFile];
	
	NSString *output = [[NSString alloc] initWithData: data encoding: NSUTF8StringEncoding];
	return output;
}

@end
