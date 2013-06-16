//
//  MTTask.h
//  cTiVo
//
//  Created by Scott Buchanan on 4/9/13.
//  Copyright (c) 2013 cTiVo. All rights reserved.
//

#import <Foundation/Foundation.h>

@class MTDownload, MTTaskChain;

@interface MTTask : NSObject

@property (strong, nonatomic) NSTask *task;

@property (strong, nonatomic) NSString	*taskName,
                                        *baseName,
										*outputFilePath,
										*logFilePath,
										*errorFilePath;

@property (strong, nonatomic) NSFileHandle	*outputFileHandle,
											*errorFileHandle,
											*logFileWriteHandle,
											*logFileReadHandle;

@property (strong, nonatomic) NSRegularExpression *trackingRegEx;

//@property (strong, nonatomic) MTTaskChain *nextTaskChain;

@property (weak, nonatomic) MTDownload *download;

@property (nonatomic, copy) void (^terminationHandler)(void);

@property (nonatomic, copy) BOOL (^startupHandler)(void), (^completionHandler)(void);

@property (nonatomic, copy) double (^progressCalc)(NSString *data);

@property (nonatomic, copy) void (^cleanupHandler)();

@property BOOL requiresInputPipe, requiresOutputPipe, shouldReschedule;
@property (nonatomic) BOOL taskFailed;

@property int pid;

@property (nonatomic, strong) NSArray *successfulExitCodes;

+(MTTask *)taskWithName:(NSString *)name download:(MTDownload *)download;
+(MTTask *)taskWithName:(NSString *)name download:(MTDownload *)download completionHandler:(BOOL(^)(void))completionHandler;

-(void) trackProcess;

-(void)setLaunchPath:(NSString *)path;
-(void)setCurrentDirectoryPath:(NSString *)path;
-(void)setEnvironment:(NSDictionary *)env;
-(void)setArguments:(NSArray *)args;
-(void)setStandardOutput:(id)stdo;
-(void)setStandardInput:(id)stdi;
-(void)setStandardError:(id)stde;
-(void)launch;
-(void)terminate;
-(void)interrupt;
-(void)suspend;
-(void)waitUntilExit;
-(BOOL)isRunning;
-(void)cleanUp;
-(void)cancel;
-(void) saveLogFile;


@end
