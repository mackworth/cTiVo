//
//  MTTivoRPC.m
//  TestTivo
//
//  Created by Hugh Mackworth on 11/27/16.
//  Copyright © 2016 Hugh Mackworth. All rights reserved.
//

#import "MTTivoRPC.h"
#import "DDLog.h"
#import "MTTiVoManager.h" //just for maskMediaKeys
#import "NSNotificationCenter+Threads.h"
#import "NSString+Helpers.h"
#import "MTWeakTimer.h"
#import "NSArray+Map.h"

@interface MTTivoRPC () <NSStreamDelegate>
@property (nonatomic, strong) NSInputStream *iStream;
@property (nonatomic, strong) NSOutputStream *oStream;
@property (nonatomic, assign) NSInteger retries;

@property (nonatomic, strong) NSString * hostName;
@property (nonatomic, strong) NSString * tiVoSerialNumber;

@property (nonatomic, strong) NSString * mediaAccessKey;
@property (nonatomic, assign) int32_t  hostPort;

@property (nonatomic, strong) NSString * userName;
@property (nonatomic, strong) NSString * userPassword;

@property (nonatomic, assign) int rpcID, sessionID;
@property (nonatomic, strong) NSString * bodyID;
@property (nonatomic, assign) BOOL authenticationLaunched;
@property (nonatomic, assign) BOOL authenticated;

@property (nonatomic, strong) NSMutableData * remainingData; //data left over from last write
@property (nonatomic, strong) NSMutableData * incomingData;
@property (nonatomic, assign) BOOL iStreamAnchor, oStreamAnchor;
@property (class, nonatomic, strong) NSArray * myCerts;
@property (atomic, assign) NSInteger updating;

@property (nonatomic, strong) NSMutableDictionary < NSString *, MTRPCData *> *showMap;
@property (nonatomic, strong) NSArray < NSString *> *lastShowList;

@property (nonatomic, strong) NSMutableDictionary < NSString *, NSString *>  *seriesImages;

@property (nonatomic, strong) NSTimer * deadmanTimer; //check connection good every few minutes

typedef void (^ReadBlock)(NSDictionary *, BOOL);
@property (nonatomic, strong) NSMutableDictionary <NSNumber *, ReadBlock > * readBlocks;
@property (nonatomic, strong) NSMutableDictionary <NSNumber *, NSDictionary* > * requests; //debug only

@property (nonatomic, strong) NSMutableArray < MTRPCData *> *skipModeQueueMetaData, * skipModeQueueEDL;
@property (atomic, assign) NSInteger goodJump, shortJumps, longJump;

@end

@interface NSObject (Threads)
//prettier syntax
-(void) afterDelay: (NSTimeInterval )time launchBlock: (void (^)(void)) block;
@end

@implementation NSObject (Threads)

-(void) afterDelay: (NSTimeInterval) time launchBlock: (void (^)(void)) block {
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, time * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
		if (block) block();
	});
}
@end

@implementation MTTivoRPC

__DDLOGHERE__

static NSArray * _myCerts = nil;        //across all TiVos; never deallocated
static SecKeychainRef keychain = NULL;  //
NSTimeInterval delay1, delay2, delay3,delay4 = 1.0;

+(void) setMyCerts:(NSArray *)myCerts {
    if (myCerts != _myCerts) {
        _myCerts = [myCerts copy];
    }
}

+(NSArray *) myCerts {
	NSString * keychainPassword = @"password";
    static dispatch_once_t onceToken = 0;
    dispatch_once(&onceToken, ^{
        DDLogDetail(@"Importing cert");
        NSData *p12Data = [NSData dataWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"cdata" ofType:@"p12"]];
        if (!p12Data.length) {
            DDLogReport(@"Error getting certificate");
        }

        //SecPKCS12Import will automatically add the items to the system keychain
        //so we create our own keychain
        //make sure we create a unique keychain name:
		NSString *temporaryDirectory = NSTemporaryDirectory();
        NSString *keychainPath = [[temporaryDirectory stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]] stringByAppendingPathExtension:@"keychain"];

        OSStatus status = SecKeychainCreate(keychainPath.UTF8String,
                                            (UInt32)(keychainPassword.length),
                                            keychainPassword.UTF8String,
                                            FALSE,
                                            NULL,
                                            &keychain);
        if (status != errSecSuccess) {
            DDLogReport(@"Could not create temporary keychain \"%@\": [%d] %@", keychainPath, (int)status, securityErrorMessageString(status));
        } else if (keychain) {
			NSString * tivoPassword = @"5vPNhg6sV4tD";

			NSDictionary * optionsDictionary = @{(id)kSecImportExportPassphrase: tivoPassword,
												 (id)kSecImportExportKeychain:   (__bridge id)keychain};
			CFArrayRef p12Items = NULL;
			OSStatus result = SecPKCS12Import((__bridge CFDataRef)p12Data, (__bridge CFDictionaryRef)optionsDictionary, &p12Items);
			if (result != noErr) {
				DDLogReport(@"Error on pkcs12 import: %d", result);
			} else {
				CFDictionaryRef identityDict = CFArrayGetValueAtIndex(p12Items, 0);
				if (identityDict) {
					SecIdentityRef identityApp =(SecIdentityRef)CFDictionaryGetValue(identityDict,kSecImportItemIdentity);

					// the certificates array, containing the identity then the root certificate
					NSMutableArray * chain =  CFDictionaryGetValue(identityDict, @"chain");
					_myCerts = @[(__bridge id)identityApp, chain[1], chain[2]];
				}
			}
			if (p12Items) CFRelease(p12Items);
		}
// We should do the following,but it seems to fail the opening of the stream.
//Instead we keep keychain around and unlock it before using certs
//        if (keychain) {
//            SecKeychainDelete(keychain);
//            CFRelease(keychain);
//        }
    });
    SecKeychainStatus keyStatus = 0;
    SecKeychainGetStatus(keychain, &keyStatus);
    UInt32 mask = (kSecUnlockStateStatus | kSecReadPermStatus);
    if (!((keyStatus & mask) == mask)) {
		DDLogMajor(@"Unlocking RPC keychain again");
        SecKeychainUnlock(keychain, (UInt32)keychainPassword.length, keychainPassword.UTF8String, TRUE);
    }
    return _myCerts;
}

NSString *securityErrorMessageString(OSStatus status) { return (__bridge_transfer NSString *)SecCopyErrorMessageString(status, NULL); }

-(instancetype) initServer: (NSString *)serverAddress forUser:(NSString *) user withPassword: (NSString *) password {
    if ((self = [super init])){
        self.userName = user;
        self.userPassword = password;
        self.hostName = serverAddress;
        self.hostPort = 443;
        [self commonInit];
    }
    return self;

}

-(instancetype) initServer: (NSString *)serverAddress tsn: (NSString *) tsn onPort: (int32_t) port andMAK:(NSString *) mediaAccessKey forDelegate:(id<MTRPCDelegate>)delegate {
    if (!serverAddress.length) return nil;
    if ((self = [super init])){
        self.hostName = serverAddress;
        self.tiVoSerialNumber = tsn;
        self.hostPort = port;
        self.mediaAccessKey = mediaAccessKey;
        self.delegate = delegate;
        [self commonInit];
    }
    return self;
}

-(void) commonInit {
    self.rpcID = 0;
    self.retries = 0;
    self.remainingData = [NSMutableData data];
    self.incomingData = [NSMutableData dataWithCapacity:50000];
    self.readBlocks = [NSMutableDictionary dictionary];
    self.requests =
#ifndef DEBUG
            nil;
#else
            [NSMutableDictionary dictionary];
#endif

    self.authenticationLaunched = NO;
	self.updating = 0;
    self.skipModeQueueMetaData = [NSMutableArray array];
    self.skipModeQueueEDL = [NSMutableArray array];
    [self launchServer];
    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver: self
                                                           selector: @selector(receiveWakeNotification:)
                                                               name: NSWorkspaceDidWakeNotification object: NULL];
	[[[NSWorkspace sharedWorkspace] notificationCenter] addObserver: self
														   selector: @selector(receiveSleepNotification:)
															   name: NSWorkspaceWillSleepNotification object: NULL];
   [[NSNotificationCenter defaultCenter] addObserver:self
        selector:@selector(appWillTerminate:) 
            name:NSApplicationWillTerminateNotification 
          object:nil];
}

#pragma mark Caches/defaults
-(void) setTiVoSerialNumber:(NSString *)TSN {
    if (TSN.length == 0) return;
    if ([TSN isEqualToString:_tiVoSerialNumber]) return;
    if ([TSN hasPrefix:@"tsn:"]) {
        TSN = [TSN substringWithRange:NSMakeRange(4, TSN.length-4)];
    }

    _tiVoSerialNumber = TSN;
    if (!self.showMap.count) {
        NSData * archiveMap = [[NSUserDefaults standardUserDefaults] objectForKey:self.defaultsKey];
        self.showMap = [NSKeyedUnarchiver unarchiveObjectWithData: archiveMap] ?: [NSMutableDictionary dictionary];
    }
}

-(void) emptyCaches {
    self.showMap = [NSMutableDictionary dictionaryWithCapacity:self.showMap.count];
    [[NSUserDefaults standardUserDefaults] setObject:nil forKey:self.defaultsKey ];
    self.seriesImages = [NSMutableDictionary dictionaryWithCapacity:self.seriesImages.count];
    self.lastShowList = nil;
    [self getAllShows];
}

-(void) saveDefaults {
   NSData * archive = [NSKeyedArchiver archivedDataWithRootObject:self.showMap];
   [[NSUserDefaults standardUserDefaults] setObject:archive forKey:self.defaultsKey ];
}

-(NSDictionary <NSString *, NSString *> *) seriesImages {
    if (!_seriesImages) {
        _seriesImages = [NSMutableDictionary dictionary];
        for (NSString * key in self.showMap.allKeys){
            MTRPCData * rpcInfo = self.showMap[key];
            NSString * title= rpcInfo.series;
            if (title && !_seriesImages[title]) {
                _seriesImages[title] = rpcInfo.imageURL;
            }
        }
    }
    return _seriesImages;
}

-(NSString *) defaultsKey {
    return [NSString stringWithFormat:@"%@ - %@", kMTRPCMap, self.tiVoSerialNumber ?:@"unknown"];
}
#pragma mark Communications
 -(void) launchServer {
     if (!self.delegate.isReachable) {
         DDLogMajor(@"Can't launch RPC; TiVo %@ offline",self.delegate);
         return;
     }
     if (!([self streamClosed: self.iStream] || [self streamClosed: self.oStream] )) return;
     [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(launchServer) object:nil  ];
     self.sessionID = arc4random_uniform(0x27dc20);
     CFReadStreamRef readStream;
     CFWriteStreamRef writeStream;

     CFStreamCreatePairWithSocketToHost(NULL, (__bridge CFStringRef)self.hostName, self.hostPort, &readStream, &writeStream);

     NSInputStream * iStream = (__bridge_transfer NSInputStream *)readStream;
     NSOutputStream * oStream =  (__bridge_transfer NSOutputStream *)writeStream;

     iStream.delegate = self;
     oStream.delegate = self;

     [iStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
     [oStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];


     [oStream setProperty:NSStreamSocketSecurityLevelNegotiatedSSL
                   forKey:NSStreamSocketSecurityLevelKey];
     if (![MTTivoRPC myCerts]) {
         DDLogReport(@"No certificate available?");
     } else {
         NSDictionary * sslOptions = @{
                                       (NSString *)kCFStreamSSLValidatesCertificateChain: (id)kCFBooleanFalse,
                                       (NSString *)kCFStreamSSLPeerName:                  (id)kCFNull,
                                       (NSString *)kCFStreamSSLIsServer:                  (id)kCFBooleanFalse,
                                       (NSString *)kCFStreamSSLCertificates:              MTTivoRPC.myCerts
                                       } ;
         [oStream setProperty:sslOptions forKey:(__bridge id)kCFStreamPropertySSLSettings];
         
         _iStreamAnchor = NO; _oStreamAnchor = NO;
         self.iStream = iStream;
         self.oStream = oStream;
         self.deadmanTimer = [MTWeakTimer scheduledTimerWithTimeInterval:12 target:self selector:@selector(checkStreamStatus) userInfo:nil repeats:YES];
         DDLogMajor(@"Launching RPC streams for %@", self.delegate);
        [iStream open];
         [oStream open];
     }
	 if (self.skipModeQueueMetaData.count > 0 || self.skipModeQueueEDL.count > 0 ) { //recover commercialing under way (e.g. after sleep)
	 	DDLogMajor(@"SkipMode Queue restarting: %@ AND %@", self.skipModeQueueMetaData, self.skipModeQueueEDL);
		[NSNotificationCenter postNotificationNameOnMainThread:kMTNotificationTiVoCommercialed object: self.delegate  ]; //remove if already there
		 [self performSelector:@selector(findSkipModeRecursive:) withObject:@0 afterDelay:20];
	 }

 }

-(BOOL) isActive {
	return self.iStream.streamStatus == NSStreamStatusOpen ||
		   self.iStream.streamStatus == NSStreamStatusOpening;
}

-(BOOL) streamClosed: (NSStream *) stream {
    return  stream.streamStatus == NSStreamStatusNotOpen ||
            stream.streamStatus == NSStreamStatusAtEnd ||
            stream.streamStatus == NSStreamStatusClosed ||
            stream.streamStatus == NSStreamStatusError  ;
}

-(void) checkStreamStatus {
    if ([self streamClosed: self.iStream] ||
        [self streamClosed: self.oStream]) {

        [self tearDownStreams];
        if (self.delegate.isReachable) {
            NSInteger seconds;
            switch (self.retries) {
                case 0: seconds = 10; break;
                case 1: seconds = 30; break;
                case 2: seconds = 60; break;
                case 3: seconds = 300; break;
                default: seconds = 900; break;
            }
            DDLogMajor(@"Stream failed, but reachable: %@ (failure #%@); Trying again in %@ seconds",self.oStream.streamError.description, @(self.retries), @(seconds));
            [self performSelector:@selector(launchServer) withObject:nil afterDelay:seconds];
            self.retries ++;
       } else {
           DDLogMajor(@"Stream failed, and unreachable: %@ (failure #%@); Awaiting reachability",self.oStream.streamError.description, @(self.retries) );
        }
		[self.delegate connectionChanged];
    }
}

-(void) startUpdating {
	BOOL needToNotify = NO;
	@synchronized(self) {
		if  (self.delegate && self.updating == 0) {
			needToNotify = YES;
		}
		self.updating ++;
	}
	if (needToNotify)[NSNotificationCenter postNotificationNameOnMainThread:kMTNotificationTiVoUpdating  object:self.delegate];
}

-(void) endUpdatingIfNecessary {
	BOOL needToNotify = NO;
	@synchronized(self) {
		self.updating --;
		if (self.delegate && self.updating == 0) {
			//turn off spinner.
			needToNotify = YES;
		}
	}
	if (needToNotify) {
		[NSNotificationCenter postNotificationNameOnMainThread:kMTNotificationTiVoUpdated  object:self.delegate userInfo:nil afterDelay:2.0];
	}
}
-(void) forceEndUpdating {
	@synchronized(self) {
	}
	[self endUpdatingIfNecessary];
}

-(void) tearDownStreams {
	DDLogMajor(@"Tearing down streams for %@", self.delegate);
	
	[self.deadmanTimer invalidate];
	self.deadmanTimer = nil;
    [self.iStream setDelegate: nil];
    [self.iStream close];
    [self.oStream setDelegate: nil];
    [self.oStream close];

	@synchronized(self.readBlocks) {
		[self.readBlocks removeAllObjects];
	}
	@synchronized(self.remainingData) {
		self.remainingData.length = 0;
	}
	@synchronized(self) {
		self.incomingData.length = 0;
		self.authenticationLaunched = NO;
		if (self.updating > 1) self.updating = 1;
	}
	[self endUpdatingIfNecessary];
}

static NSRegularExpression * rpcRegex = nil;
static NSRegularExpression * rpcIDRegex = nil;
static NSRegularExpression * isFinalRegex = nil;

-(NSInteger) parseResponse: (NSData *) dataIn  {
    //returns -1 for error
    //0 if not enough characters to read
    //otherwise, # of actual bytes read (bytes, not characters)

    //uses self.readBlocks to call packet-specific response handlers
    static dispatch_once_t onceToken = 0;
    dispatch_once(&onceToken, ^{
        rpcRegex = [NSRegularExpression regularExpressionWithPattern: @"^.*MRPC/2\\s*(\\d+)\\s*(\\d+).*$"
                                                             options:0 |
                    NSRegularExpressionAnchorsMatchLines
                                                               error:nil];
        rpcIDRegex = [NSRegularExpression regularExpressionWithPattern: @"^RpcId: (\\d+)$"
                                                               options:NSRegularExpressionAnchorsMatchLines
                                                                 error:nil];
        isFinalRegex = [NSRegularExpression regularExpressionWithPattern: @"^IsFinal: (.+)$"
                                                                 options:NSRegularExpressionAnchorsMatchLines
                                                                   error:nil];
    });
    if (dataIn.length < 10) return 0;
    NSString * incoming = nil;
    NSUInteger dataLength = 0;
    @synchronized (dataIn) {
        incoming = [[NSString alloc] initWithData:dataIn encoding:NSUTF8StringEncoding];
        dataLength = dataIn.length;
        if (!incoming) { //garbage in input stream, not UTF8 compatible
            DDLogReport(@"Warning: skipping invalid data received from TiVo: %@", dataIn);
            return dataLength;
        }
    }
    NSTextCheckingResult * lenResult = [rpcRegex firstMatchInString:incoming options:0 range:NSMakeRange(0, incoming.length)];
    if (lenResult) {
        NSRange headerLenRange = [lenResult rangeAtIndex:1];
        NSInteger headerLen = [incoming substringWithRange: headerLenRange].integerValue;
        NSRange bodyLenRange = [lenResult rangeAtIndex:2];
        NSInteger bodyLen =   [incoming substringWithRange: bodyLenRange].integerValue;
        NSRange headerRange = NSMakeRange(NSMaxRange(bodyLenRange)+ 2, headerLen);
        NSInteger bodyStart = NSMaxRange(headerRange);
        //check if we have whole packet
        NSRange bodyRange = NSMakeRange(bodyStart, bodyLen);
        NSUInteger packetLength = NSMaxRange(bodyRange);
        if (packetLength <= dataLength) {
            NSString * headers = [incoming substringWithRange:headerRange]; //assumes no unicode in header
            NSData * bodyData = nil;
            @synchronized (dataIn) {
                bodyData = [dataIn subdataWithRange:bodyRange];
            }
            NSError * error = nil;
            NSDictionary * jsonData = [NSJSONSerialization JSONObjectWithData:bodyData
                                                                      options:0
                                                                        error:&error];
            if (jsonData && !error) {
                NSTextCheckingResult * rpcIDResult = [rpcIDRegex firstMatchInString:headers options:0 range:NSMakeRange(0, headers.length)];
                if (rpcIDResult) {
                    NSInteger rpcID = [headers substringWithRange:[rpcIDResult rangeAtIndex:1]].integerValue;
                    BOOL isFinal = YES;
                    NSTextCheckingResult * finalResult = [isFinalRegex firstMatchInString:headers options:0 range:NSMakeRange(0, headers.length)];
                    if (finalResult && [@"false" isEqualToString:[headers substringWithRange:[finalResult rangeAtIndex:1]]]) {
                        isFinal = NO;
                    }
                    ReadBlock readBlock = nil;
                    NSDictionary * readPacket = nil;
                    @synchronized (self.readBlocks) {
                        readBlock = [self.readBlocks objectForKey:@(rpcID)];
                        readPacket = self.requests[@(rpcID)];
                        [self.requests removeObjectForKey:@(rpcID)];
                        if (isFinal && readBlock) {
                            [self.readBlocks removeObjectForKey:@(rpcID)];
                            DDLogDetail(@"Final for %@; %d still active", @(rpcID), (int)self.readBlocks.count);
                        } else {
                            DDLogDetail(@"Not final for %@", @(rpcID));
                        }
					}
					if (isFinal) [self endUpdatingIfNecessary];
                    if ([jsonData[@"type"] isEqualToString:@"error"]) {
                        DDLogReport(@"Error: error JSON response. %@\n%@\n%@", headers, readPacket, jsonData);
						if ([jsonData[@"code"] isEqualToString:@"mindUnavailable"]) {
							[self.oStream close]; //mark to reset
							[self checkStreamStatus];
						}
                        return -packetLength;
                    } else {
                        if (readBlock) {
                            dispatch_async(dispatch_get_main_queue(), ^{
                                readBlock(jsonData, isFinal);
                            }) ;
                        }
                        return packetLength;
                    }
                } else {
                    DDLogReport(@"Error: bad / missing RPCID");
                    return -packetLength;
                }
            } else {
                DDLogReport(@"Error: %@",error.localizedDescription);
                return -packetLength;
            }
        } else {
            return 0; // packet too short, so keep reading
        }
    } else {
        DDLogReport(@"Error: bad packet from TiVo: doesn't start with MRPC/2 (d) (d): %@", dataIn);
        return -dataLength; //probably wrong, but don't know what else to do here
    }
}

- (void)stream:(NSStream *)theStream handleEvent:(NSStreamEvent)streamEvent {
    NSString * streamName = (theStream == self.iStream) ? @"inStream" : @"outStream";
    //theoretically, we should check our incoming stream for trust,
    //but frankly we really don't care if we're being spoofed.
    //    if (streamEvent == NSStreamEventHasBytesAvailable || streamEvent == NSStreamEventHasSpaceAvailable) {
    //        /* Check it. */
    //        if (![self checkTrustedStream:theStream]){
    //            DDLogReport(@"Failed checkStream for %@", streamName);
    //        }
    //    }
    switch (streamEvent) {
        case NSStreamEventNone: {
            DDLogReport(@"NoEvent for %@", streamName);
            break;
        }
        case NSStreamEventOpenCompleted: {
            DDLogDetail(@"Stream opened for %@", streamName);
            self.retries = 0;
            if (theStream == self.oStream) [self authenticate];
            break;
        }
        case NSStreamEventHasBytesAvailable: {
            //            DDLogVerbose(@"Stream hasBytes for %@",  streamName);
            uint8_t buf[16384];
            NSInteger len = 0;
            len = [(NSInputStream *) theStream read:buf maxLength:16384];
            if (len > 0) {
                //              DDLogVerbose(@"%@: %lu bytes read: %.*s", streamName, len, (int)len, buf); //careful changing this
                @synchronized (self.incomingData) {
                    [self.incomingData appendBytes:(const void *)buf length:len];
                }
                BOOL morePackets = YES;
                while (morePackets) {
                    morePackets = NO;
                    NSInteger bytesUsed = [self parseResponse: self.incomingData ];
                    BOOL error = bytesUsed < 0;
                    if (error) bytesUsed *= -1;
                    @synchronized (self.incomingData) {
                        DDLogVerbose(@"bytes Used: %lu of %lu %@", bytesUsed, self.incomingData.length, error ? @"with error": @"");
                        if ((NSUInteger)bytesUsed >= self.incomingData.length) {
                            //used up all the data
                            self.incomingData.length = 0;
                        } else if (bytesUsed > 0) {
                            //more data available
                            [self.incomingData replaceBytesInRange:NSMakeRange(0, bytesUsed) withBytes:NULL length:0 ];
                            morePackets = YES;
                        } else {
                            //apparently packet needs more bytes to come in
                        }
                    }
                }
            } else {
                DDLogMajor(@"%@ Failed read==> closed connection? %@: %@", streamName, @(len), [theStream streamError]);
                [self checkStreamStatus];
            }
            break;
        }
        case NSStreamEventHasSpaceAvailable: {
            [self reallyWriteData];
            break;
        }
        case NSStreamEventErrorOccurred: {
            DDLogMajor(@"StreamError on %@: %@", streamName, [theStream streamError]);
            [self checkStreamStatus];
            break;
        }
        case NSStreamEventEndEncountered: {
            DDLogMajor(@"%@ Stream End", streamName);
            [self checkStreamStatus];
            break;
        }
        default: {
            DDLogMajor(@"Other Stream Event (%d) for %@", (int)streamEvent, streamName);
            break;
        }
    }
}

-(BOOL) reallyWriteData  {
    if (!self.oStream.hasSpaceAvailable) return NO;
    NSData * data = nil;
    @synchronized(self.remainingData) {
        if (self.remainingData.length >0) {
            data = [self.remainingData copy];
            self.remainingData.length = 0;
        }
    }
    if (data.length) {
        NSInteger numbytes = [self.oStream write:[data bytes] maxLength:data.length];
        if (numbytes < 0) {
            DDLogReport(@"Write error: %@", [self.oStream streamError]);
            [self checkStreamStatus];
            return NO;
        } else if (numbytes == 0) {
            DDLogReport(@"Huh? stream is full: %@", [self.oStream streamError]);
            return NO;
        } else if ((NSUInteger)numbytes < data.length) {
            @synchronized (self.remainingData) {
                self.remainingData = [NSMutableData dataWithData:[data subdataWithRange:NSMakeRange(numbytes, data.length-numbytes)]];
            }
            return YES;
        } else {
            return YES;
        }
    } else {
        return NO;
    }
}
-(NSString *) maskTSN:(NSObject *) data {
	return [[data description] maskSerialNumber:self.tiVoSerialNumber];
}

-(void) sendRpcRequest:(NSString *) type monitor:(BOOL) monitor withData: (NSDictionary *) data completionHandler: (void (^)(NSDictionary * jsonResponse, BOOL isFinal)) completionHandler {
    NSString * responseCount = monitor ? @"multiple" : @"single";
    NSString * bodyID = data[@"bodyId"] ?: @"";
    NSString * schema =  @"17";
    self.rpcID++;
    NSString * headers = [NSString stringWithFormat:
          @"Type: request\r\n"
          "RpcId: %d\r\n"
          "SchemaVersion:  %@\r\n"
          "Content-Type: application/json\r\n"
          "RequestType:  %@\r\n"
          "ResponseCount:  %@\r\n"
          "BodyId:  %@\r\n"
          "X-ApplicationName: Quicksilver\r\n"
          "X-ApplicationVersion: 1.2\r\n"
          "X-ApplicationSessionId: 0x%x\r\n\r\n",
        self.rpcID, schema, type, responseCount, bodyID, self.sessionID];
    NSData * headerData = [headers dataUsingEncoding:NSUTF8StringEncoding];

    NSMutableDictionary * finalData = [data mutableCopy];
    finalData[@"type"] = type;

    NSData * body = [NSJSONSerialization dataWithJSONObject:finalData options:0 error:nil];
    NSString * startLine = [NSString stringWithFormat: @"MRPC/2 %d %d\r\n", (int)headerData.length, (int)body.length];
    NSMutableData * request = [NSMutableData dataWithData:[startLine dataUsingEncoding:NSUTF8StringEncoding]];
    [request appendData:headerData];
    [request appendData:body];
    [request appendData:[@"\n" dataUsingEncoding:NSUTF8StringEncoding]];
	DDLogDetail(@"Sending RPC #%d, %@", self.rpcID, type);
    DDLogVerbose(@"RPC Packet: %@\n%@\n", headers, [self maskTSN:[data  maskMediaKeys]]);
    @synchronized (self.remainingData) {
        [self.remainingData appendData:request];
    }
    @synchronized (self.readBlocks) {
		[self.requests setObject:finalData forKey:@(self.rpcID)];
       	self.readBlocks[@(self.rpcID)] = [completionHandler copy];
    }
	if (!monitor) [self endUpdatingIfNecessary];

    [self reallyWriteData];
}

#pragma mark RPC Commands
-(void) authenticate {
    DDLogDetail(@"Calling Authenticate");
    if (self.authenticationLaunched) return;
    self.authenticationLaunched = YES;
    NSDictionary * data = nil;
    if (self.userName) {
        data =
                @{@"credential":
                      @{@"type": @"mmaCredential",
                        @"username": self.userName,
                        @"password": self.userPassword
                       }
                 };
    } else {
        data = @{@"credential":
                     @{@"type": @"makCredential",
                       @"key": self.mediaAccessKey
                       }
                 };
    }
	__weak __typeof__(self) weakSelf = self;
    [self sendRpcRequest:@"bodyAuthenticate"
                 monitor:NO
                withData:data
       completionHandler:^(NSDictionary *jsonResponse, BOOL isFinal) {
		   __typeof__(self) strongSelf = weakSelf;
		   if (!strongSelf ) return;
          DDLogVerbose(@"Authenticate from TiVo RPC: %@", [self maskTSN:jsonResponse]);
           if ([jsonResponse[@"status"] isEqualToString:@"success"]) {
               DDLogDetail(@"Authenticated");
//               if (jsonResponse[@"deviceId"]) {  //for tivo middlemind in future
//                   for (NSDictionary * device in jsonResponse[@"deviceId"]) {
//                       if ([device[@"friendlyName"] isEqualToString:self.hostname]) { //wrong name
//                           self.bodyID = device[@"id"];
//                           self.tiVoSerialNumber = self.bodyID;
//                           [self.delegate setTiVoSerialNumber:self.bodyID];
//                           break;
//                       }
//                   }
//               }
               if (!strongSelf.bodyID) {
                   [strongSelf getBodyID];
               } else {
                   [strongSelf getAllShows];
				   [self.delegate connectionChanged];
               }
           } else {
               DDLogReport(@"RPC Authentication failure!");
               [strongSelf sharedShutdown];
           }
    }];
}

-(void) getBodyID {
    NSDictionary * data =  @{@"bodyId": @"-" };
    DDLogDetail(@"Calling BodyID");
	__weak __typeof__(self) weakSelf = self;

    [self sendRpcRequest:@"bodyConfigSearch"
                 monitor:NO
                withData:data
       completionHandler:^(NSDictionary *jsonResponse, BOOL isFinal) {
           DDLogVerbose(@"BodyID from TiVo RPC: %@",[self maskTSN: jsonResponse]);
		   __typeof__(self) strongSelf = weakSelf;
           NSArray * bodyConfigs = jsonResponse[@"bodyConfig"];
           if (bodyConfigs.count > 0) {
               NSDictionary * bodyConfig = (NSDictionary *)bodyConfigs[0];
               //could also get userDiskSize and userDiskUsed here
               NSString * bodyId = bodyConfig[@"bodyId"];
               if (bodyId) {
                   strongSelf.bodyID =bodyId;
                   DDLogVerbose(@"Got BodyID");
                   strongSelf.tiVoSerialNumber = bodyId;
                   [strongSelf.delegate setTiVoSerialNumber:bodyId];
				   [strongSelf.delegate connectionChanged];
                   [strongSelf getAllShows];
               }
           }
       }];
}


-(void) getAllShows {
    DDLogDetail(@"Calling GetAllShows");
    if (!self.bodyID) {
        [self getBodyID];
        return;
    }
	if (self.delegate.isMini) return;  //don't subscribe to updates from Minis
    NSDictionary * data = @{@"flatten": @"true",
                            @"format": @"idSequence",
                            @"bodyId": self.bodyID
                            };
	__weak __typeof__(self) weakSelf = self;
	[self sendRpcRequest:@"recordingFolderItemSearch"
                 monitor: YES
                withData:data
       completionHandler:^(NSDictionary *jsonResponse, BOOL isFinal) {
           //This will be called every time the TiVo List changes, so first Launch differentiates the very first time.
		   __typeof__(self) strongSelf = weakSelf;
		   if (!strongSelf) return;
		   DDLogVerbose(@"Got All Shows from TiVo RPC: %@", [strongSelf maskTSN:jsonResponse]);
           NSArray <NSString *> * shows = jsonResponse[@"objectIdAndType"];
           BOOL isFirstLaunch = strongSelf.lastShowList == nil;
           DDLogMajor (@"Got %lu shows from TiVo", shows.count);
		   DDLogDetail(@"Shows from TiVo RPC: %@", [shows componentsJoinedByString:@", "]);
           if (!strongSelf.showMap) {
               strongSelf.showMap = [NSMutableDictionary dictionaryWithCapacity:shows.count];
               [strongSelf recursiveGetShowInfoForShows: shows ];
           } else {
               NSMutableArray <NSString *> *lookupDetails = [NSMutableArray array];
               NSMutableArray <NSString *> * newIDs = [NSMutableArray array];
               NSMutableArray <NSNumber *> * indices = [NSMutableArray array];
               NSMutableDictionary < NSString *, MTRPCData *> *deletedShows = [strongSelf.showMap mutableCopy];
               [shows enumerateObjectsUsingBlock:^(NSString *  _Nonnull objectID, NSUInteger idx, BOOL * _Nonnull stop) {
				   MTRPCData * thisRPC = strongSelf.showMap[objectID];
                   if (!thisRPC) {
                       [newIDs addObject:objectID];
                       [lookupDetails addObject:objectID];
                       [indices addObject:@(idx)];
                   } else {
                       //have seen before, so don't lookup, but also don't delete
                       [deletedShows removeObjectForKey:objectID];
                       if (isFirstLaunch &&
						   (!thisRPC.imageURL || (thisRPC.clipMetaDataId && ! (thisRPC.edlList || thisRPC.programSegments)))) {
                           //saved last time without having finished checking the art or getting segment info
                           [lookupDetails addObject:objectID];
                       }
                   }
               }
                ];
               for (NSString * objectID in deletedShows) {
                   [strongSelf.showMap removeObjectForKey:objectID];
               }
			   [strongSelf recursiveGetShowInfoForShows: lookupDetails];
			   if ((newIDs.count + deletedShows.count > 0) ||
				   [shows isEqual:strongSelf.lastShowList] ||
				   isFirstLaunch) {  //if any adds or delete, OR unchanged list
				   [strongSelf.delegate tivoReports:  shows.count withNewShows:newIDs atTiVoIndices:indices andDeletedShows:deletedShows isFirstLaunch: isFirstLaunch];
				} else { //problem...
					[strongSelf.delegate rpcResync];
			   }
           }
		   strongSelf.lastShowList = shows;
       } ];
}

-(void) purgeShows: (NSArray <NSString *> *) showIDs {
	if (!showIDs.count) return;
	for (NSString * showID in showIDs) {
		MTRPCData * rpcData = self.showMap[showID];
		if (rpcData) {
			if (rpcData.series){
				[self.seriesImages removeObjectForKey:rpcData.series];
			}
			[self.showMap removeObjectForKey:showID];
		}
	}
}

-(void) getShowInfoForShows: (NSArray <NSString *> *) requestShows  {
	if (requestShows.count == 0 || !self.bodyID) {
		return;
	}
	NSArray <NSString *> * neededShows = [requestShows mapObjectsUsingBlock:^id(NSString * id, NSUInteger idx) {
		if (self.showMap[id].clipMetaDataId) {
			[self.delegate receivedRPCData:self.showMap[id] ];
			return nil;
		} else {
			return id;
		}
	}];
	[self recursiveGetShowInfoForShows: neededShows];
}

-(void) recursiveGetShowInfoForShows: (NSArray <NSString *> *) requestShows {
	if (requestShows.count == 0 || !self.bodyID) {
		return;
	}
    const int idsPerCall = 10;
    NSArray <NSString *> *  subArray = nil;
    BOOL lastBatch = idsPerCall >= requestShows.count;
	NSArray <NSString *> * restArray = nil;
    if ( lastBatch) {
        subArray = requestShows;
    } else {
        subArray = [requestShows subarrayWithRange:NSMakeRange(0, idsPerCall)];
        restArray = [requestShows subarrayWithRange:NSMakeRange(idsPerCall, requestShows.count -idsPerCall)];
    }
    DDLogDetail(@"Getting showInfo for %@", subArray);
    //    if (!showInfoResponseTemplate) {    //DOESN"T WORK for episodeNum??
//        showInfoResponseTemplate =
//        @[@{
//              @"type": @"responseTemplate",
//              @"fieldName": @[@"recording"],
//              @"typeName": @"recordingList"
//          },@{
//              @"type":      @"responseTemplate",
//              @"fieldName": @[@"episodeNum", @"seasonNumber",  @"recordingId", @"contentId", @"title"],
//              @"fieldInfo": @[
//                                @{@"maxArity": @[@1],
//                                  @"fieldName": @[@"category"],
//                                  @"type": @"responseTemplateFieldInfo"},
//                                @{@"maxArity": @[@1],
//                                  @"fieldName": @[@"episodeNum"],
//                                  @"type": @"responseTemplateFieldInfo"},
//                      ],
//              @"typeName":  @"recording"}];
//    }
//
    NSDictionary * data = @{@"bodyId": self.bodyID,
                            @"levelOfDetail": @"high",
                            @"objectIdAndType": subArray,
//                          @"responseTemplate": showInfoResponseTemplate
                            };
	__weak __typeof__(self) weakSelf = self;

    [self sendRpcRequest:@"recordingSearch"
             monitor:NO
            withData:data
   completionHandler:^(NSDictionary *jsonResponse, BOOL isFinal) {
	   __typeof__(self) strongSelf = weakSelf;
	   if (!strongSelf) return;
       NSArray * responseShows = jsonResponse[@"recording"];
	   DDLogVerbose(@"Got ShowInfo from TiVo RPC: %@", [strongSelf maskTSN:jsonResponse]);
	   if (!lastBatch) {
		   [strongSelf recursiveGetShowInfoForShows:restArray ];
	   }
       if (responseShows.count == 0 || responseShows.count != subArray.count) {
           DDLogReport(@"Warning: Invalid # of TivoRPC shows: \n%@ \n%@", responseShows, subArray);
       }
       NSMutableArray * showsWithoutImage = [NSMutableArray arrayWithCapacity:responseShows.count];
       NSMutableArray * showsObjectIDs = [NSMutableArray arrayWithCapacity:responseShows.count];

       NSUInteger objectIDIndex = 0;
       for (NSDictionary * showInfo in responseShows) {
           NSString * objectId = subArray[objectIDIndex];
           NSNumber * episodeNum = @0;
           NSArray * episodeNumbers = showInfo[@"episodeNum"];
           if (episodeNumbers.count > 0) {
               episodeNum = episodeNumbers[0];
           }
           NSString * genre = @"";
           NSArray * categories = showInfo[@"category"];
           if  (categories.count > 0) {
               genre = categories[0][@"label"];
           }
           MTRPCData * rpcData = [[MTRPCData alloc] init];
           rpcData.episodeNum = episodeNum.integerValue;
           rpcData.seasonNum = ((NSNumber *)showInfo[@"seasonNumber"] ?: @(0)).integerValue;
           rpcData.genre = genre;
           rpcData.recordingID = (NSString *) showInfo[@"recordingId"];
		   rpcData.contentID = (NSString *) showInfo[@"contentId"];
           rpcData.series = (NSString *)showInfo[@"title"];
           rpcData.rpcID = [NSString stringWithFormat: @"%@|%@", strongSelf.hostName, objectId];
//           NSString * mimeType = (NSString *)showInfo[@"mimeType"];  doesn't work!
//           if ([@"video/mpg2" isEqualToString:mimeType] ){
//               rpcData.format = MPEGFormatMP2;
//           } else if ([@"video/mpg4" isEqualToString:mimeType] ){
//               rpcData.format = MPEGFormatMP4;
//           } else {
//               rpcData.format = MPEGFormatOther;
//           }
		   
           @synchronized (strongSelf.showMap) {
			   MTRPCData * oldData = strongSelf.showMap[rpcData.rpcID];
			   if (oldData) {
				   rpcData.clipMetaDataId = oldData.clipMetaDataId;
				   rpcData.programSegments = oldData.programSegments;
				   rpcData.edlList = oldData.edlList;
			   }
               [strongSelf.showMap setObject:rpcData forKey:objectId];
           }

           [strongSelf parseMetadataID:showInfo forShow:rpcData withCompletionHandler:nil ];

           //very annoying that TiVo won't send over image information with the rest of the show info.
           NSString * imageURL = strongSelf.seriesImages[rpcData.series]; //tivo only has series images
           if (imageURL) {
               rpcData.imageURL = imageURL;
               [strongSelf.delegate receivedRPCData:rpcData];
           } else {
               NSString * contentId = rpcData.contentID;
               if (contentId.length) {
                    [showsWithoutImage addObject:contentId];
                    [showsObjectIDs addObject:objectId];
                }
           }
           objectIDIndex++;
       }
       [strongSelf getImageFor:showsWithoutImage withObjectIds: showsObjectIDs];
           //leave some time for imageURLS, then save defaults.
       if (lastBatch) {
           dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
               [strongSelf saveDefaults];
           });
       }
   } ];
}

-(MTRPCData *) rpcDataForID: (NSString *) idString {
    @synchronized (self.showMap) {
        MTRPCData * rpcData = self.showMap[idString];
		return rpcData;
    }
}

static NSArray * imageResponseTemplate = nil;

-(void) getImageFor: (NSArray <NSString *> *) contentIds withObjectIds: (NSArray <NSString *> *) objectIds {
	if (!self.bodyID) {
		[self getBodyID];
		return;
	}
    if (contentIds.count ==0) return;
    NSAssert(contentIds.count == objectIds.count,@"Invalid ObjectIds");
    DDLogDetail(@"Getting Images for %@", objectIds);
    if (!imageResponseTemplate) {
        imageResponseTemplate =
        @[@{
              @"type":      @"responseTemplate",
              @"fieldName": @[@"image"],
              @"typeName":  @"recording"}];
    }

    NSDictionary * data = @{
                        @"bodyId": self.bodyID,
                        @"levelOfDetail": @"high",
                        @"responseTemplate": imageResponseTemplate,
                        @"contentId": contentIds
                        };
	__weak __typeof__(self) weakSelf = self;

    [self sendRpcRequest:@"contentSearch"
                 monitor:NO
                withData:data
       completionHandler:^(NSDictionary *jsonResponse, BOOL isFinal) {
		__typeof__(self) strongSelf = weakSelf;
		if (!strongSelf) return;
        NSArray * shows = jsonResponse[@"content"];
        DDLogVerbose(@"Got ImageInfo from TiVo RPC: %@", shows);
        for (NSDictionary * showInfo in shows) {
            NSString * imageURL = @"";
            NSInteger maxSize = 0;
            NSUInteger index = [contentIds indexOfObject: showInfo[@"contentId"]];
            if (index == NSNotFound) {
                DDLogReport(@"Could not find %@ in %@",showInfo, contentIds);
            } else {
                for (NSDictionary * image in showInfo[@"image"]) {
                   NSInteger imageWidth = ((NSNumber *)image[@"width"]).integerValue;
                   if (imageWidth > maxSize) {
                       maxSize = imageWidth;
                       imageURL = image[@"imageUrl"];
                   }
                }
                MTRPCData * episodeInfo = nil;
                DDLogDetail(@"For %@, found TiVo imageInfo %@",objectIds[index], imageURL);
                @synchronized (strongSelf.showMap) {
                   episodeInfo = strongSelf.showMap[objectIds[index]];
                   episodeInfo.imageURL  = imageURL;  //if none available, still mark as ""
                   NSString * title= episodeInfo.series;
                   if (title && !strongSelf.seriesImages[title]) {
                       strongSelf.seriesImages[title] = imageURL;
                   }
                }
                [strongSelf.delegate receivedRPCData:episodeInfo];
           }
       }
    }];
}

-(void) deleteShowsWithRecordIds: (NSArray <NSString *> *) recordingIds {
    if (recordingIds.count ==0) return;
	if (!self.bodyID) {
		[self getBodyID];
		return;
	}
    DDLogDetail(@"Deleting shows %@", recordingIds);
    NSDictionary * data = @{
                            @"bodyId": self.bodyID,
                            @"state": @"deleted",
                            @"recordingId": recordingIds
                            };

    [self sendRpcRequest:@"recordingUpdate"
                 monitor:NO
                withData:data
       completionHandler:nil];
}

-(void) undeleteShowsWithRecordIds: (NSArray <NSString *> *) recordingIds {
    if (recordingIds.count ==0) return;
	if (!self.bodyID) {
		[self getBodyID];
		return;
	}
    DDLogDetail(@"Stopping Recording (or Undeleting) shows %@", recordingIds);
    NSDictionary * data = @{
                            @"bodyId": self.bodyID,
                            @"state": @"complete",
                            @"recordingId": recordingIds
                            };

    [self sendRpcRequest:@"recordingUpdate"
                 monitor:NO
                withData:data
       completionHandler:nil];
}

-(void) stopRecordingShowsWithRecordIds: (NSArray <NSString *> *) recordingIds {
    [self undeleteShowsWithRecordIds:recordingIds]; //coincidentally the same command
}

-(void) sendKeyEvent: (NSString *) keyEvent withCompletion: (void (^)(void)) completionHandler  {
	if (keyEvent.length ==0 || !self.bodyID) {
		DDLogReport(@"Can't send keyEvent: %@", keyEvent);
		if (completionHandler) completionHandler();
		return;
	}
	
	DDLogDetail(@"Sending KeyEvent: %@", keyEvent);
	NSDictionary * data = @{
							@"bodyId": self.bodyID,
							@"event": keyEvent,
							};
	
	[self sendRpcRequest:@"keyEventSend"
				 monitor:NO
				withData:data
	   completionHandler:^(NSDictionary *jsonResponse, BOOL isFinal) {
		   DDLogVerbose(@"sent keyStroke %@; got %@", keyEvent, jsonResponse);
		   if (completionHandler) completionHandler();
	   }];
}

-(void) sendURL: (NSString *) URL {
	if (URL.length == 0  || !self.bodyID) {
		DDLogMajor (@"Can't send URL %@", URL);
		return;
	}
	DDLogDetail(@"Sending URL: %@", URL);
	NSDictionary * data = @{
							@"uri": URL,
							};
	
	[self sendRpcRequest:@"uiNavigate"
				 monitor:NO
				withData:data
	   completionHandler:^(NSDictionary *jsonResponse, BOOL isFinal) {
		   DDLogVerbose(@"sent URL %@; got %@", URL, jsonResponse);
	   }];
}

-(void) checkServices {
	DDLogDetail(@"Asking What services are available:");
	[self sendRpcRequest:@"uiDestinationInstanceSearch"
				 monitor:NO
				withData:@{@"noLimit":@(YES),
						   @"uiDestinationType":@"flash"}   //classicUI, hme, web, flash
	   completionHandler:^(NSDictionary *jsonResponse, BOOL isFinal) {
		   DDLogReport(@"sent checkService request; got %@", jsonResponse);
	   }];
}

-(void) rebootTiVo {
	DDLogReport(@"Rebooting Tivo %@", self.delegate);
	NSDictionary * data = @{
							@"type": @"uiNavigate",
							@"uri":  @"x-tivo:classicui:restartDvr",
							};
	__weak __typeof__(self) weakSelf = self;

	[self sendRpcRequest:@"uiNavigate"
				 monitor:NO
				withData:data
	   completionHandler:^(NSDictionary *jsonResponse, BOOL isFinal) {
	  //using blank lines instead of indenting.
	   [weakSelf afterDelay:5.0 launchBlock:^{
		   
	   [weakSelf sendKeyEvent: @"thumbsDown" withCompletion:^{
		   
	   [weakSelf sendKeyEvent: @"thumbsDown" withCompletion:^{
		   
	   [weakSelf sendKeyEvent: @"thumbsDown" withCompletion:^{
		   
	   [weakSelf sendKeyEvent: @"enter" withCompletion:^{
		   
	   DDLogReport(@"Finished rebooting Tivo %@", self.delegate);
	   [weakSelf tearDownStreams];
	   [weakSelf performSelector:@selector(launchServer) withObject:nil afterDelay:120]; //start trying to reconnect in 2 minutes

	   }];
	   }];
	   }];
	   }];
	   }];
	}];
}

-(void) channelListWithCompletion: (void (^)(NSDictionary <NSString *, NSString *> *)) completionHandler {
	DDLogDetail(@"Asking what channels exist:");

	NSArray * responseTemplate =
	@[@{
		  @"type":      @"responseTemplate",
		  @"fieldName": @[@"affiliate", @"callSign", @"channelNumber"],
		  @"typeName":  @"channel"
		  }];;
	/* also available:
	affiliate = "WGN America (West)";
	bitrate = 2861924614144;
	callSign = "WGNAM-W";
	channelId = "tivo:ch.6553599";
	channelNumber = 9;
	isBlocked = 0;
	isDigital = 1;
	isEntitled = 1;
	isHdtv = 0;
	isKidZone = 0;
	isReceived = 1;
	levelOfDetail = low;
	logoIndex = 65667;
	name = "WGNAM-W";
	objectIdAndType = 325455979347967;
	serviceId = 26478;
	sourceType = cable;
	stationId = "tivo:st.338261044";
	type = channel
	*/
	[self sendRpcRequest:@"channelSearch"
				 monitor:NO
				withData:@{@"noLimit":@(YES),
						   @"isReceived":@(YES),
						   @"responseTemplate": responseTemplate
						   }
	   completionHandler:^(NSDictionary *jsonResponse, BOOL isFinal) {
		   DDLogDetail(@"sent channelSearch; got %@", jsonResponse);
		   NSMutableDictionary * channels = [NSMutableDictionary dictionaryWithCapacity:jsonResponse.count];
		   for (NSDictionary * channel in jsonResponse[@"channel"]) {
			   NSString * callSign = channel[@"callSign"];
			   if (callSign.length) channels[callSign] = channel;
			}

		   if (completionHandler) completionHandler([channels copy]);
	   }];
}

-(NSString *) describeNetwork: (NSDictionary <NSString *, NSString *> *) network  {
	NSMutableString * outString = [NSMutableString string];
	for (NSString * key in network.allKeys) {
		if ([key isEqualToString:@"type"]) continue;
		NSString * outKey = key;
		if ([outKey isEqualToString:@"ipAddress"]) outKey = @"TCP/IP Address";
		if ([outKey isEqualToString:@"interfaceState"]) outKey = @"Interface Status";
		if ([outKey isEqualToString:@"mac"]) outKey = @"MAC Address";
		if ([outKey isEqualToString:@"interfaceType"]) outKey = @"Interface Type";

		if (network[key].length > 0) {
			[outString appendFormat: @"    %@:  %@\n", outKey, network[key]];
		}
	}
	return [outString copy];
}

-(void) tiVoInfoWithCompletion: (void (^)(NSString *)) completionHandler {
	__weak __typeof__(self) weakSelf = self;

	[self sendRpcRequest:@"bodyConfigSearch"
				 monitor:NO
				withData:@{}
	   completionHandler:^(NSDictionary *jsonResponse, BOOL isFinal) {
		DDLogDetail(@"sent bodyConfigSearch; got %@", jsonResponse);
		NSArray * configs =jsonResponse[@"bodyConfig"];
		NSDictionary * configJSON;

		if ([configs isKindOfClass:[NSArray class]] && configs.count > 0) {
			configJSON = configs[0];
		} else if ([configs isKindOfClass:[NSDictionary class]]) {
			configJSON = (NSDictionary *) configs;
		} else {
			if (completionHandler) completionHandler(@"");
		}
		NSMutableString * outString = [NSMutableString string];
		NSString * diskSizeString = configJSON[@"userDiskSize"];
		NSString * diskUsedString = configJSON[@"userDiskUsed"];
		double megabyte = 1024*1024;
		double diskSizeGB = diskSizeString.longLongValue/megabyte; //reported in 1K chunks
		double diskUsedGB = diskUsedString.longLongValue/megabyte;
		if (diskSizeGB > 1.0) { //probably Mini otherwise
			int percentUsed = (int)(diskUsedGB / diskSizeGB * 100.0);
			[outString appendFormat:@"Disk Space: \n    Total: %0.1lld GB\n    Used: %0lld GB (%d%%)\n\n",  (int64_t) diskSizeGB, (int64_t) diskUsedGB, percentUsed];
		}
		NSArray * networks = configJSON[@"networkInterface"];
		if (networks && [networks isKindOfClass:[NSArray class]] && networks.count > 0) {
			if (networks.count > 1) {
				[outString appendString:@"Network Interfaces:\n"];
				for (NSDictionary * network in networks) {
					[outString appendFormat:@"\n%@", [weakSelf describeNetwork: network]];
				}
			} else {
				[outString appendString:@"Network Interface:\n"];
				[outString appendFormat:@"%@", [weakSelf describeNetwork: networks[0]]];
			}
			[outString appendString:@"\n"];
		}
		NSString * controls = configJSON[@"parentalControlsState"];
		if (controls.length) {
			[outString appendFormat:@"Parental Controls: %@\n\n", controls];
		}
		NSString * version = configJSON[@"softwareVersion"];
		if (version.length) {
			[outString appendFormat:@"Software Version: %@\n\n", version];
		}
		if (completionHandler) completionHandler([outString copy]);
	   }];

}

-(void) whatsOnSearchWithCompletion: (void (^)(MTWhatsOnType whatsOn, NSString * recordingID, NSString * channelNumber)) completionHandler {
	DDLogDetail(@"Asking What's on:");
	[self sendRpcRequest:@"whatsOnSearch"
				 monitor:NO
				withData:@{}
	   completionHandler:^(NSDictionary *jsonResponse, BOOL isFinal) {
		   DDLogDetail(@"sent what'sOnSearch; got %@", jsonResponse);
		   NSDictionary * whatsOn = jsonResponse[@"whatsOn"][0];
		   NSString * playback = whatsOn[@"playbackType"];
		   NSString * recordingId = whatsOn[@"recordingId"];
		   NSString * channelNumber = nil;
		   MTWhatsOnType result = MTWhatsOnUnknown;
		   if (!playback) {
				DDLogReport(@"No playbackType?? got %@", jsonResponse);
		   } else {
			   NSArray * map = @[@"unknown", @"liveCache", @"recording", @"idle", @"loopset"];
			   NSInteger location = [map indexOfObject:playback];
			   if (location == NSNotFound) {
				   DDLogReport(@"Unknown playbackType: %@ in %@",playback, jsonResponse );
			   } else {
				   DDLogDetail(@"Found playbackType: %@ with %@",playback, recordingId );
				   result = (MTWhatsOnType) location;
				   NSDictionary * channelId = whatsOn[@"channelIdentifier"];
				   if (channelId) {
					   channelNumber = channelId[@"channelNumber"]; //nil if not there
				   }
			   }
		   }
		   if (completionHandler) completionHandler(result,recordingId, channelNumber);
	   }];
}

-(void) retrievePositionWithCompletionHandler: (void (^)(long long position, long long length)) completionHandler {
	if (!self.bodyID) {
		DDLogMajor (@"can't Retrieve Position");
		if (completionHandler) completionHandler(0, 0);
		return;
	}
	DDLogDetail(@"Getting current Position");
	NSDictionary * data = @{
							@"throttleDelay": @1000
							};
	
	[self sendRpcRequest:@"videoPlaybackInfoEventRegister"
				 monitor:NO
				withData:data
	   completionHandler:^(NSDictionary *jsonResponse, BOOL isFinal) {
		   DDLogVerbose(@"got positionResponse: %@", jsonResponse);
		   NSString * positionString = jsonResponse[@"position"];
		   long long position = positionString.length ? positionString.longLongValue : -1;
		   DDLogDetail(@"Position = %@",@(position));
		   NSString * lengthString = jsonResponse[@"end"];
		   long long length = lengthString.length ? lengthString.longLongValue : -1;
           if (length == -1) {
               DDLogMajor(@"No PositionResponse: %@", jsonResponse);
           }
		   if (completionHandler) completionHandler(position, length);
	   }];
}

-(void) jumpToPosition: (NSInteger) location withCompletionHandler: (void (^)(BOOL success)) completionHandler {
	if (location < 0 || !self.bodyID) {
		DDLogMajor (@"can't jump to Position %@",@(location));
		if (completionHandler) completionHandler(NO);
		return;
	}
	
	DDLogDetail(@"Jump to Position: %@", @(location));
	NSDictionary * data = @{
							@"offset": @(location)
							};
	
	[self sendRpcRequest:@"videoPlaybackPositionSet"
				 monitor:NO
				withData:data
	   completionHandler:^(NSDictionary *jsonResponse, BOOL isFinal) {
		   DDLogDetail(@"got positionResponse: %@", jsonResponse);
		   NSString * responseString = jsonResponse[@"type"];
		   if (completionHandler) completionHandler([@"success" isEqualToString:responseString]);
	   }];
}

-(void) setBookmarkPosition: (NSInteger) location forRecordingId: (NSString *) recordingId withCompletionHandler: (void (^)(BOOL success)) completionHandler {
	if (recordingId.length == 0 || location < 0 || !self.bodyID) {
		DDLogMajor (@"can't set BookMark to Position %@",@(location));
		if (completionHandler) completionHandler(NO);
		return;
	}
	DDLogDetail(@"Setting bookmark position for %@ to  %@", recordingId, @(location));
	NSDictionary * data = @{
							@"bodyId": self.bodyID,
							@"recordingId": recordingId,
							@"bookmarkPosition": @(location)
							};
	
	[self sendRpcRequest:@"recordingUpdate"
				 monitor:NO
				withData:data
	   completionHandler:^(NSDictionary *jsonResponse, BOOL isFinal) {
		   DDLogDetail(@"got setBookMark response: %@", jsonResponse);
		   NSString * responseString = jsonResponse[@"type"];
		   if (completionHandler) completionHandler([@"success" isEqualToString:responseString]);
	   }];
}

-(void) playOnTiVo: (NSString *) recordingId withCompletionHandler: (void (^)(BOOL success)) completionHandler {
	if (recordingId.length == 0 || !self.bodyID) {
		DDLogMajor (@"can't play %@ on TiVo",recordingId);
		if (completionHandler) completionHandler(NO);
		return;
	}

	DDLogDetail(@"Playing recording %@", recordingId);
	NSDictionary * data = @{
							@"type": @"uiNavigate",
							@"uri":  @"x-tivo:classicui:playback",
							@"parameters": @{
									@"fUseTrioId": 			@"true",
									@"recordingId": 		recordingId,
									@"fHideBannerOnEnter":  @"false"
									}
							};
	
	[self sendRpcRequest:@"uiNavigate"
				 monitor:NO
				withData:data
	   completionHandler:^(NSDictionary *jsonResponse, BOOL isFinal) {
		   DDLogDetail(@"got playback response: %@", jsonResponse);
		   NSString * responseString = jsonResponse[@"type"];
		   if (completionHandler) completionHandler([@"success" isEqualToString:responseString]);
	   }];

}

#pragma mark Commercial extraction
-(void) retrieveClipMetaDataFor: (NSString *) contentId withCompletionHandler: (void (^)(NSString * metaDataId, NSArray <NSNumber *> *segments)) completionHandler {
	if (contentId.length ==0 || !self.bodyID) {
		DDLogMajor (@"can't retrieve metaData for show: %@",contentId);
		if (completionHandler) completionHandler(nil, nil);
		return;
	};
	DDLogMajor(@"Getting clip data for %@", contentId);
	NSArray <NSString *> *  subArray = @[contentId];
	NSArray * showInfoResponseTemplate =
		@[@{
			  @"type": @"responseTemplate",
			  @"fieldName": @[@"recording"],
			  @"typeName": @"recordingList"
		  },@{
			  @"type":      @"responseTemplate",
			  @"fieldName": @[@"clipMetadata",@"title"],
			  @"typeName":  @"recording"}
		  ];
	
	NSDictionary * data = @{@"bodyId": self.bodyID,
							@"levelOfDetail": @"high",
							@"objectIdAndType": subArray,
							@"responseTemplate": showInfoResponseTemplate
							};
	__weak __typeof__(self) weakSelf = self;
	
	[self sendRpcRequest:@"recordingSearch"
				 monitor:NO
				withData:data
	   completionHandler:^(NSDictionary *jsonResponse, BOOL isFinal) {
		   __typeof__(self) strongSelf = weakSelf;
		   if (!strongSelf) return;
		   NSArray * responseShows = jsonResponse[@"recording"];
		   DDLogVerbose(@"Got metaData from TiVo RPC: %@", [strongSelf maskTSN:jsonResponse]);
		   if (responseShows.count == 0) {
				if (completionHandler) completionHandler(nil,nil);
				return;
			}
		   if (responseShows.count != subArray.count) {
			   DDLogMajor(@"Invalid # of TivoRPC shows: /n%@ /n%@", responseShows, subArray);
			   if (completionHandler) completionHandler(nil,nil);
			   return;
		   }
		   NSDictionary * showInfo = responseShows[0];
		   MTRPCData * rpcData = nil;
		   @synchronized (self.showMap) {
		   	 	rpcData = self.showMap[contentId];
	       }
		  [strongSelf parseMetadataID:showInfo forShow:rpcData withCompletionHandler:completionHandler];
	 }];
}

 -(void)parseMetadataID:(NSDictionary *) showInfo forShow: (MTRPCData *) rpcData  withCompletionHandler: (void (^)(NSString *, NSArray <NSNumber *> *)) completionHandler {
	NSArray * clipDataArray = showInfo[@"clipMetadata"];
	NSString * clipMetaDataId = nil;
	if ([clipDataArray isKindOfClass:[NSArray class]] && clipDataArray.count > 0) {
	   clipMetaDataId = clipDataArray[0][@"clipMetadataId"];
	}
	
	NSString * oldMetadataID = rpcData.clipMetaDataId;
	rpcData.clipMetaDataId = clipMetaDataId;

	if (clipMetaDataId.length == 0) {
		DDLogMajor(@"No skipmode metaData for %@", rpcData);
		if (completionHandler) completionHandler(nil,nil);
	} else if ([oldMetadataID isEqualToString:clipMetaDataId] && rpcData.programSegments.count > 0){
		DDLogDetail(@"No skipmode change for %@",rpcData);
		if (completionHandler) completionHandler(clipMetaDataId, rpcData.programSegments);
	} else {
		if (!oldMetadataID) {
		   DDLogMajor(@"Metadata just arrived for %@", rpcData);
		} else {
		   DDLogMajor(@"Revised commercial metadata found for %@", rpcData);
		}
		__weak __typeof__(self) weakSelf = self;
		[self retrieveSegments:rpcData.clipMetaDataId withCompletionHandler:^(NSArray * segments) {
			if (segments.count == 0) {
				DDLogReport(@"Segments failed %@ #: %@ contentId: %@", showInfo[@"title"], rpcData.recordingID, rpcData.clipMetaDataId);
				rpcData.skipModeFailed = YES;
			} else {
				DDLogMajor(@"Segments just arrived for %@ #: %@ contentId: %@", showInfo[@"title"], rpcData.recordingID, rpcData.clipMetaDataId);
				DDLogDetail(@"Segments: %@", segments);
			}
			rpcData.programSegments = segments;
		   	[weakSelf.delegate receivedRPCData:rpcData];
			if (completionHandler) completionHandler(clipMetaDataId, segments);
		}];
	}
}

-(void) retrieveSegments: (NSString *) clipMetaId withCompletionHandler: (void (^)(NSArray *)) completionHandler {
	if (clipMetaId.length == 0 ) {
		DDLogMajor (@"can't retrieve segments for nil metadata");
		if (completionHandler) completionHandler(nil);
		return;
	};
	NSDictionary * data = @{
							@"clipMetadataId": @[clipMetaId]
							};
	__weak __typeof__(self) weakSelf = self;

	[self sendRpcRequest:@"clipMetadataSearch"
				 monitor:NO
				withData:data
	   completionHandler:^(NSDictionary *jsonResponse, BOOL isFinal) {
			  NSArray * clipDatas = jsonResponse[@"clipMetadata"];
		   __typeof__(self) strongSelf = weakSelf;
		   DDLogVerbose(@"Got segment response from TiVo RPC: %@", [strongSelf maskTSN:jsonResponse]);
		   for (NSDictionary * clipdata in clipDatas) {
				  if ([clipdata isKindOfClass:[NSDictionary class]] &&
					  [clipMetaId isEqual:clipdata[@"clipMetadataId"]]) {
					  NSArray * origSegments = clipdata[@"segment"];
					  if ([origSegments isKindOfClass:[NSArray class]]) {
						  NSMutableArray * segments = [NSMutableArray arrayWithCapacity:origSegments.count];
						  for (NSDictionary * segment in origSegments) {
							  NSString * endOffset = segment[@"endOffset"];
							  NSString * beginOffset = segment[@"startOffset"];
							  if (endOffset && beginOffset ) {
								  [segments addObject: @(endOffset.longLongValue - beginOffset.longLongValue )];
							  }
						  }
						  if (completionHandler) completionHandler(segments);
						  return;
					  }
				  }
			  }
		   if (completionHandler) completionHandler(nil);
		} ];
}

//#define testJumps 1

-(void) logString:(NSString *) msg {
#ifdef testJumps
	DDLogReport(@"%@",msg);
#else
	DDLogMajor(@"%@",msg);
#endif
	
}
-(void) getRemainingPositionsInto: 	(NSMutableArray <NSNumber *> *) positions
					   badJumps: (int) badJump
						forShow: (NSString *) show
		   withCompletionHandler: (void (^)(NSArray *)) completionHandler {
	__weak __typeof__(self) weakSelf = self;
	if (badJump >= 3) {
		//not getting anywhere
		DDLogReport(@"Failing commercial retrieving due to multiple bad jumps %@", positions);
		if (completionHandler) completionHandler(positions);
		return;
	}
	long long prevPosition = positions.firstObject.longLongValue;
	[weakSelf retrievePositionWithCompletionHandler:^(long long position2, long long end2) {
		if (positions.count == 1 &&
			prevPosition - position2 > 30000 ) {
			[weakSelf logString:[NSString stringWithFormat:
				@"Commercial Long Jump from %@ to %@ for %@", @(prevPosition), @(position2), show]];
			weakSelf.longJump++;
#ifdef testJumps
			//abort after first jump if we're testing jumps
			if (completionHandler) completionHandler(positions);
			return;
#endif
		}
		
	    [weakSelf sendKeyEvent: @"play" withCompletion:^{
		//note: indenting change to avoid tower effect, each line break is a new event-driven block
		[weakSelf afterDelay:delay4 launchBlock:^{

		[weakSelf sendKeyEvent: @"channelDown" withCompletion:^{
			
		[weakSelf afterDelay:delay4 launchBlock:^{
			
		[weakSelf sendKeyEvent: @"pause" withCompletion:^{
		
		[weakSelf afterDelay:delay3 launchBlock:^{
			
		[weakSelf retrievePositionWithCompletionHandler:^(long long position, long long end) {
			
		long long jumpSize = prevPosition - position;
#ifdef testJumps
		if (jumpSize < 30000) {
			NSString * msg = [NSString stringWithFormat: @"Commercial Short Jump: %lld", jumpSize/1000];
			[self logString:msg];
			self.shortJumps++;
		} else {
			[self logString:@"Commercial Good Jump"];
			self.goodJump++;
		}
		//abort after first jump if we're testing jumps
		if (completionHandler) completionHandler(positions);
		return;
#endif
		if (jumpSize > 30000 ||
			(position > 150000 && jumpSize > 0)) {
			int recentShortJumps;
			if (jumpSize > 30000) {
				//we have moved a significant amount, so record
				[positions insertObject:@(position) atIndex:0]; //reverse in file
				[self logString:[NSString stringWithFormat:@"Good Jump from %lld to %lld for %@", prevPosition, position, show]];
				self.goodJump++;
				recentShortJumps = 0;
			} else {
				recentShortJumps = badJump+1;
				NSString * msg = [NSString stringWithFormat: @"Short Jump #%d: %lld from %lld to %lld for %@", (int)badJump, jumpSize/1000, prevPosition, position, show];
				[self logString:msg];
				self.shortJumps++;
			}

			if (position > 3000) {
				[weakSelf jumpToPosition:position-3000 withCompletionHandler:^(BOOL success) {
					if (success) {
						[weakSelf afterDelay:delay2 launchBlock:^{
							[weakSelf getRemainingPositionsInto:positions
											           badJumps:recentShortJumps
													    forShow:show
										  withCompletionHandler:completionHandler];
						} ];
					} else {
						if (completionHandler) completionHandler(positions);
					}
				} ];
			} else {
				if (completionHandler) completionHandler(positions);
			}
		} else {
			//haven't moved , so all done
			if (completionHandler) completionHandler(positions);
		}
		}];
		}];
		}];
		}];
		}];
		}];
		}];
	}];
}

-(NSArray <MTRPCData *> *) showsWaitingForSkipMode {
	return [self.skipModeQueueEDL copy];
}

-(void) findSkipModeEDLForShow:(MTRPCData *) rpcData {
	if (!rpcData) return;
	if (rpcData.skipModeFailed) {
		DDLogDetail(@"Not getting EDL for %@; Previous failure", rpcData);
		return;
	}
	if (rpcData.edlList) {
		DDLogDetail(@"Not getting EDL for %@; Already have it", rpcData);
		return;
	}
	if (!rpcData.contentID) {
		DDLogDetail(@"Not getting EDL for %@; No content ID", rpcData);
    	return;
	};
    __weak __typeof__(self) weakSelf = self;

	if ([self.skipModeQueueMetaData containsObject:rpcData] || [self.skipModeQueueEDL containsObject:rpcData]) {
		DDLogDetail(@"SkipMode Queue already waiting for: %@", rpcData);
	} else {
		DDLogDetail(@"SkipMode Queue adding: %@", rpcData);
		if (rpcData.clipMetaDataId == nil || rpcData.programSegments == nil) {
			//need metadata info first
			//really should have saved objectID
			NSRange separator = [rpcData.rpcID rangeOfString:@"|" options:0];
			if (separator.location == NSNotFound) return;
			NSString * objectId = [rpcData.rpcID substringFromIndex:NSMaxRange(separator)];
			DDLogDetail(@"SkipMode Queue getting metadata: %@", rpcData);
			[self.skipModeQueueMetaData addObject:rpcData];

			[self retrieveClipMetaDataFor:objectId withCompletionHandler:^(NSString * metaDataID, NSArray<NSNumber *> * lengths) {
				[weakSelf.skipModeQueueMetaData removeObject:rpcData];
				if (metaDataID != nil && lengths.count > 0) {
					DDLogDetail(@"SkipMode Queue got metadata; re-launching: %@", rpcData);
					[weakSelf findSkipModeEDLForShow:rpcData] ;
				} else {
					DDLogDetail(@"SkipMode Queue no metadata, ignoring: %@", rpcData);
				}
			}];
		} else {
			[self.skipModeQueueEDL addObject:rpcData];
			if (self.skipModeQueueEDL.count == 1) {
				// restore these?
				//    [self sendKeyEvent: @"nowShowing" andPause :4.0];
				//    [self sendKeyEvent: @"tivo"       andPause :4.0];
				//    [self sendKeyEvent: @"nowShowing" andPause :4.0];
				[NSNotificationCenter postNotificationNameOnMainThread:kMTNotificationTiVoCommercialing object: self.delegate  ];
				DDLogDetail(@"Getting SkipMode for: %@", rpcData);
				self.goodJump  = self.shortJumps = self.longJump = 0;
				NSString * delayString = [[NSUserDefaults standardUserDefaults] stringForKey:@"RPCTime"  ];
				if (delayString.length ==0) {
					delayString = @"2.0, 1.6, 1.0, 0.4";
				}
				NSArray <NSString *> * delays = [delayString componentsSeparatedByString:@","];
				if (delays.count > 3) {
					delay1 = delays[0].doubleValue;
					delay2 = delays[1].doubleValue;
					delay3 = delays[2].doubleValue;
					delay4 = delays[3].doubleValue;
				} else {
					delay1 = delay2 = delay3 = delay4 = delayString.doubleValue;
				}
				[self findSkipModeRecursive:@0];

			} else {
				DDLogDetail(@"Another SkipMode Already in Progress: %@", self.skipModeQueueEDL);
				[NSNotificationCenter postNotificationNameOnMainThread:kMTNotificationTiVoCommercialing object:  nil  ];
			//wait for previous ones to complete.
			}
		}
	}
}

-(void) findSkipModeRecursive: (NSNumber *) firstTryNumber {
	BOOL lastTry = firstTryNumber.intValue >= 3; //try up to three times (due to interference)
	if (self.skipModeQueueEDL.count == 0) {
		NSInteger tries = self.goodJump+self.shortJumps+self.longJump ;
		NSString * result =[NSString stringWithFormat:@"After %@ attempts with delays %0.1f, %0.1f, %0.1f, %0.1f, the results were %@ Good; %@ Short; %@ Long. %0.0f%% good",  @(tries), delay1, delay2, delay3, delay4,  @(self.goodJump), @(self.shortJumps), @(self.longJump), 100.0*self.goodJump/(float)tries];
#ifdef testJumps
		DDLogReport(@"Jump Results = %@", result);
		NSAlert * jumpAlert = [NSAlert alertWithMessageText:@"SkipMode Test" defaultButton:@"OK" alternateButton: nil otherButton:nil informativeTextWithFormat:@"%@",result];
		[jumpAlert runModal];
#else
		DDLogMajor(@"Finished SkipMode Queue; Jump Results = %@", result);
#endif

		[NSNotificationCenter postNotificationNameOnMainThread:kMTNotificationTiVoCommercialed object: self.delegate  ];
        return;
	} else if (firstTryNumber.intValue == 0 ) {
		//if firstOne, then start commercialling, otherwise just update
		[NSNotificationCenter postNotificationNameOnMainThread:kMTNotificationTiVoCommercialing object: nil  ];
	}
	MTRPCData * rpcData = self.skipModeQueueEDL[0];
	DDLogMajor(@"skipMode queue %@checking for commercials for %@", firstTryNumber.intValue == 0 ? @"" : @"re-", rpcData);
	__weak __typeof__(self) weakSelf = self;
	
	[self findSkipModePointsForShow:rpcData withCompletionHandler:^{
		__typeof__(self) strongSelf = weakSelf;
		if (rpcData.edlList.count > 0 || lastTry) {
			if (rpcData.edlList.count == 0) {
				DDLogReport(@"SkipMode EDL failure for %@", rpcData);
			}
			[strongSelf.delegate receivedRPCData:rpcData];
			if (strongSelf.skipModeQueueEDL.count > 0) {
				[strongSelf.skipModeQueueEDL removeObject:rpcData];
				DDLogDetail(@"SkipModeQueue moving on to %@",strongSelf.skipModeQueueEDL);
				[strongSelf findSkipModeRecursive:@0 ];
			} else {
				DDLogMajor(@"SkipMode Queue finished");
			}
		} else {
			//try again if we have a problem creating an EDL
#ifndef testJumps
			DDLogMajor(@"SkipMode Queue Retrying EDL list for %@", rpcData);
#endif
			[strongSelf findSkipModeRecursive:@(firstTryNumber.intValue + 1) ];
		}
    }];
}

-(void) findSkipModePointsForShow:(MTRPCData *) rpcData withCompletionHandler: (void (^)(void)) completionHandler {
	
	__weak __typeof__(self) weakSelf = self;
	if (!rpcData) return;
	//note: indenting change to avoid tower effect, each line break is a new block
	[self whatsOnSearchWithCompletion:^(MTWhatsOnType previousWhatsOn, NSString *previousRecordingID, NSString * channelNumber) {

		[weakSelf playOnTiVo:rpcData.recordingID withCompletionHandler:^(BOOL complete) {
			
		[weakSelf afterDelay:delay1 launchBlock:^{

		[weakSelf sendKeyEvent: @"pause" withCompletion:^{
		
		[weakSelf afterDelay:delay4 launchBlock:^{

		[weakSelf retrievePositionWithCompletionHandler:^(long long startingPoint, long long end) {
			
#ifdef testJumps
			DDLogReport(@"found initial Point of %@ / %@", @(startingPoint), @(end));
#else
			DDLogDetail(@"found initial Point of %@ / %@", @(startingPoint), @(end));
#endif
		if (startingPoint < 2000) startingPoint = 0;
		if (end <= 0) {
			if (rpcData.tempLength <= 0) {
				DDLogReport(@"Neither show nor RPC has correct length");
            	end = 24*3600*1000;
			} else {
				DDLogDetail(@"Correcting RPC length to %lld", (long long) rpcData.tempLength*1000);
				end = rpcData.tempLength*1000;
			}
		} else {
			if (ABS(rpcData.tempLength*1000 - end) > 2000) DDLogDetail(@"RPC shows length as  %0.1f vs showLength as %0.1f",end/1000.0, rpcData.tempLength);
			end = MIN(rpcData.tempLength*1000, end);
		}

		[weakSelf jumpToPosition:end-20000 withCompletionHandler:^(BOOL success) {
			
		[weakSelf afterDelay:delay2 launchBlock:^{
			
//		[weakSelf sendKeyEvent: @"reverse" withCompletion:^{
//
//		[weakSelf afterDelay:delay launchBlock:^{
			
		[weakSelf getRemainingPositionsInto: [NSMutableArray arrayWithObject:@(end)]
								  badJumps:0
		 							forShow:rpcData.series
					  withCompletionHandler:^(NSArray * positions) {

		DDLogDetail(@"Got positions of %@", positions);
		rpcData.edlList = [NSArray edlListFromSegments:rpcData.programSegments andStartPoints:positions];
	    if (rpcData.edlList) {
		    DDLogMajor(@"For %@, got EDL %@", rpcData, rpcData.edlList);
	    } else {
		    DDLogMajor(@"for %@, No EDL", rpcData);
	    }
	    [weakSelf sendKeyEvent: @"pause"  withCompletion:^{
			
		[weakSelf afterDelay:delay1 launchBlock:^{
		
		void (^finishUp)(void) = ^void {
			[weakSelf setBookmarkPosition:startingPoint
						   forRecordingId:rpcData.recordingID
					withCompletionHandler:^(BOOL success3){
				if (completionHandler) (completionHandler());
			}];
		};
		if (previousWhatsOn == MTWhatsOnRecording) {
			[weakSelf playOnTiVo:previousRecordingID withCompletionHandler:^(BOOL restorePlaySuccess) {
				finishUp();
			}];
		} else {
			[weakSelf jumpToPosition:startingPoint withCompletionHandler:^(BOOL success2){
				[weakSelf afterDelay:delay1 launchBlock:^{
					[weakSelf sendKeyEvent: @"liveTv" withCompletion: finishUp];
			}];
		}];
		}
		}];
	  	}];
		}];
		}];
		}];
		}];
		}];
		}];
		}];
		}];
		}];
}

#pragma mark System Interactions

-(void) receiveSleepNotification: (id) sender {
	DDLogMajor(@"RPC sleeping; terminating connection");
	[self tearDownStreams];
}

-(void) receiveWakeNotification: (id) sender {
	DDLogMajor(@"System waking");
	if ([self streamClosed: self.iStream ] ) {
		//should be closed normally; let things settle and re-open
		[self performSelector:@selector(launchServer) withObject:nil afterDelay:1];
	}
}

-(void) stopServer {
    [self sharedShutdown];
}

-(void) sharedShutdown {
    [self tearDownStreams];
    [self saveDefaults];
}

-(void) dealloc {
	self.delegate = nil;
	[self sharedShutdown];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [[[NSWorkspace sharedWorkspace] notificationCenter] removeObserver: self];
}

-(void) appWillTerminate: (id) notification {
    [self sharedShutdown];
    if (keychain != NULL) {
        SecKeychainDelete(keychain);
        keychain = NULL;
    }
}

@end


