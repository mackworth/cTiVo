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
#import "Crashlytics/Crashlytics.h"
#ifdef DEBUG
#define CLSLog NSLog
#endif
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
@property (nonatomic, assign) BOOL firstLaunch;

@property (nonatomic, strong) NSMutableData * remainingData; //data left over from last write
@property (nonatomic, strong) NSMutableData * incomingData;
@property (nonatomic, assign) BOOL iStreamAnchor, oStreamAnchor;
@property (class, nonatomic, strong) NSArray * myCerts;

@property (nonatomic, strong) NSMutableDictionary < NSString *, MTRPCData *> *showMap;
@property (nonatomic, strong) NSMutableDictionary < NSString *, NSString *>  *seriesImages;

@property (nonatomic, strong) NSTimer * deadmanTimer; //check connection good every few minutes

typedef void (^ReadBlock)(NSDictionary *, BOOL);
@property (nonatomic, strong) NSMutableDictionary <NSNumber *, ReadBlock > * readBlocks;
@property (nonatomic, strong) NSMutableDictionary <NSNumber *, NSDictionary* > * requests; //debug only
@end

@implementation MTTivoRPC

__DDLOGHERE__

static NSArray * _myCerts = nil;        //across all TiVos; never deallocated
SecKeychainRef keychain = NULL;  //

+(void) setMyCerts:(NSArray *)myCerts {
    if (myCerts != _myCerts) {
        _myCerts = [myCerts copy];
    }
}

+(NSArray *) myCerts {
    NSString * password = @"LwrbLEFYvG";
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
                                            (UInt32)(password.length),
                                            password.UTF8String,
                                            FALSE,
                                            NULL,
                                            &keychain);
        if (status != errSecSuccess) {
            DDLogReport(@"Could not create temporary keychain \"%@\": [%d] %@", keychainPath, (int)status, securityErrorMessageString(status));
        }

        NSDictionary * optionsDictionary = @{(id)kSecImportExportPassphrase: password,
                                             (id)kSecImportExportKeychain:   (__bridge id)keychain};
        CFArrayRef p12Items = NULL;
        OSStatus result = SecPKCS12Import((__bridge CFDataRef)p12Data, (__bridge CFDictionaryRef)optionsDictionary, &p12Items);
        if(result != noErr) {
            DDLogReport(@"Error on pkcs12 import: %d", result);
        } else {
            CFDictionaryRef identityDict = CFArrayGetValueAtIndex(p12Items, 0);
            SecIdentityRef identityApp =(SecIdentityRef)CFDictionaryGetValue(identityDict,kSecImportItemIdentity);

            // the certificates array, containing the identity then the root certificate
            NSMutableArray * chain =  CFDictionaryGetValue(identityDict, @"chain");
            _myCerts = @[(__bridge_transfer id)identityApp, chain[1], chain[2]];
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
        SecKeychainUnlock(keychain, (UInt32)password.length, password.UTF8String, TRUE);
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

-(instancetype) initServer: (NSString *)serverAddress tsn: (NSString *) tsn onPort: (int32_t) port andMAK:(NSString *) mediaAccessKey{
    if (!serverAddress.length) return nil;
    if ((self = [super init])){
        self.hostName = serverAddress;
        self.tiVoSerialNumber = tsn;
        self.hostPort = port;
        self.mediaAccessKey = mediaAccessKey;
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
    self.firstLaunch = YES;
    [self launchServer];
    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver: self
                                                           selector: @selector(receiveWakeNotification:)
                                                               name: NSWorkspaceDidWakeNotification object: NULL];
    [[NSNotificationCenter defaultCenter] addObserver:self
        selector:@selector(appWillTerminate:) 
            name:NSApplicationWillTerminateNotification 
          object:nil];
}

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
            if (!_seriesImages[title]) {
                _seriesImages[title] = rpcInfo.imageURL;
            }
        }
    }
    return _seriesImages;
}

-(NSString *) defaultsKey {
    return [NSString stringWithFormat:@"%@ - %@", kMTRPCMap, self.tiVoSerialNumber ?:@"unknown"];
}

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
         self.deadmanTimer = [NSTimer scheduledTimerWithTimeInterval:12 target:self selector:@selector(checkStreamStatus) userInfo:nil repeats:YES];
         DDLogMajor(@"Launching RPC streams for %@", self.delegate);
        [iStream open];
         [oStream open];
     }
//     [self performSelector:@selector(checkStreamStatus) withObject:nil afterDelay:3];
 }
-(BOOL) isActive {
    return self.iStream.streamStatus == NSStreamStatusOpen;
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
        NSUInteger i  = 0;

        CLSLog(@"Stream failure: %@",@(self.iStream.streamStatus));
        i++;
        i++;
        CLSLog(@"Stream error: %@",self.oStream.streamError.description);
        i++;
        i++;
        [self.deadmanTimer invalidate];
        i++;
        i++;
        self.deadmanTimer = nil;
        NSInteger seconds;
        i++;
        i++;

        i++;
        i++;
        i++;
        i++;
        [self tearDownStreams];
        if (self.delegate.isReachable) {
            CLSLog(@"Trying again; retry #%@ ; ",@(self.retries));
            switch (self.retries) {
                case 0: seconds = 10; break;
                case 1: seconds = 30; break;
                case 2: seconds = 60; break;
                case 3: seconds = 300; break;
                default: seconds = 900; break;
            }
            CLSLog(@"Stream failed, but reachable: %@ (failure #%@); Trying again in %@ seconds",self.oStream.streamError.description, @(self.retries), @(seconds));
            DDLogMajor(@"Stream failed, but reachable: %@ (failure #%@); Trying again in %@ seconds",self.oStream.streamError.description, @(self.retries), @(seconds));
            [self performSelector:@selector(launchServer) withObject:nil afterDelay:seconds];
            self.retries ++;
       } else {
           CLSLog(@"Stream failed, and unreachable: %@ (failure #%@); Awaiting reachability",self.oStream.streamError.description, @(self.retries) );
           DDLogMajor(@"Stream failed, and unreachable: %@ (failure #%@); Awaiting reachability",self.oStream.streamError.description, @(self.retries) );
        }
    }
}

-(void) tearDownStreams {
    [self.iStream setDelegate: nil];
    [self.iStream close];
    [self.oStream setDelegate: nil];
    [self.oStream close];

    [self.readBlocks removeAllObjects];
    self.incomingData.length = 0;
    self.remainingData.length = 0;
    self.authenticationLaunched = NO;
    self.firstLaunch = YES;
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
                            DDLogDetail(@"Final for %@; %d remaining", @(rpcID), (int)self.readBlocks.count-1);
                        } else {
                            DDLogDetail(@"Not final for %@", @(rpcID));
                        }
                    }
                    if (isFinal) {
                        [NSNotificationCenter postNotificationNameOnMainThread:kMTNotificationTiVoUpdated  object:self.delegate];
                    }
                    if ([jsonData[@"type"] isEqualToString:@"error"]) {
                        DDLogReport(@"Error: error JSON response. %@\n%@\n%@", headers, readPacket, jsonData);
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
                CLSLog(@"%@ Failed read==> closed connection? %@: %@", streamName, @(len), [theStream streamError]);
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
            CLSLog(@"StreamError on %@: %@", streamName, [theStream streamError]);
            [self checkStreamStatus];
            break;
        }
        case NSStreamEventEndEncountered: {
            DDLogMajor(@"%@ Stream End", streamName);
            CLSLog(@"%@ Stream End", streamName);
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

    if (self.tiVoSerialNumber.length > 0) {
        NSString * outString = data.description;
        NSString * maskedKey = [NSString stringWithFormat: @"<<%@ SerialNumber>", self.delegate.description];
        return [outString stringByReplacingOccurrencesOfString: self.tiVoSerialNumber
                                               withString: maskedKey];
    } else {
        return @"";
    }

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
    [self.requests setObject:finalData forKey:@(self.rpcID)];
    DDLogVerbose(@"RPC Packet: %@\n%@\n", headers, [self maskTSN:[data  maskMediaKeys]]);
    @synchronized (self.remainingData) {
        [self.remainingData appendData:request];
    }
    @synchronized (self.readBlocks) {
        self.readBlocks[@(self.rpcID)] = [completionHandler copy];
    }
    if (!monitor) {
        [NSNotificationCenter postNotificationNameOnMainThread:kMTNotificationTiVoUpdating  object:self.delegate];
    }
    [self reallyWriteData];
}

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
    [self sendRpcRequest:@"bodyAuthenticate"
                 monitor:NO
                withData:data
       completionHandler:^(NSDictionary *jsonResponse, BOOL isFinal) {
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
               if (!self.bodyID) {
                   [self getBodyID];
               } else {
                   [self getAllShows];
               }
           } else {
               DDLogReport(@"RPC Authentication failure!");
               [self sharedShutdown];
           }
    }];
}

-(void) getBodyID {
    NSDictionary * data =  @{@"bodyId": @"-" };
    DDLogDetail(@"Calling BodyID");

    [self sendRpcRequest:@"bodyConfigSearch"
                 monitor:NO
                withData:data
       completionHandler:^(NSDictionary *jsonResponse, BOOL isFinal) {
           DDLogVerbose(@"BodyID from TiVo RPC: %@",[self maskTSN: jsonResponse]);
           NSArray * bodyConfigs = jsonResponse[@"bodyConfig"];
           if (bodyConfigs.count > 0) {
               NSDictionary * bodyConfig = (NSDictionary *)bodyConfigs[0];
               //could also get userDiskSize and userDiskUsed here
               NSString * bodyId = bodyConfig[@"bodyId"];
               if (bodyId) {
                   self.bodyID =bodyId;
                   DDLogVerbose(@"Got BodyID");
                   self.tiVoSerialNumber = bodyId;
                   [self.delegate setTiVoSerialNumber:bodyId];
                   [self getAllShows];
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
    NSDictionary * data = @{@"flatten": @"true",
                            @"format": @"idSequence",
                            @"bodyId": self.bodyID
                            };
    [self sendRpcRequest:@"recordingFolderItemSearch"
                 monitor: YES
                withData:data
       completionHandler:^(NSDictionary *jsonResponse, BOOL isFinal) {
           //This will be called every time the TiVo List changes, so first Launch differentiates the very first time.
           DDLogVerbose(@"Got All Shows from TiVo RPC: %@", [self maskTSN:jsonResponse]);
           NSArray <NSString *> * shows = jsonResponse[@"objectIdAndType"];
           BOOL isFirstLaunch = self.firstLaunch;
           self.firstLaunch = NO;
           DDLogDetail (@"Got %lu shows from TiVo", shows.count);
           if (!self.showMap) {
               self.showMap = [NSMutableDictionary dictionaryWithCapacity:shows.count];
               [self getShowInfoForShows: shows];
           } else {
               NSMutableArray <NSString *> *lookupDetails = [NSMutableArray array];
               NSMutableArray <NSString *> * newIDs = [NSMutableArray array];
               NSMutableArray <NSNumber *> * indices = [NSMutableArray array];
               NSMutableDictionary < NSString *, MTRPCData *> *deletedShows = [self.showMap mutableCopy];
               [shows enumerateObjectsUsingBlock:^(NSString *  _Nonnull objectID, NSUInteger idx, BOOL * _Nonnull stop) {
                   if (!self.showMap[objectID]) {
                       [newIDs addObject:objectID];
                       [lookupDetails addObject:objectID];
                       [indices addObject:@(idx)];
                   } else {
                       //have seen before, so don't lookup, but also don't delete
                       [deletedShows removeObjectForKey:objectID];
                       if (isFirstLaunch && !self.showMap[objectID].imageURL) {
                           //saved last time without having finished checking the art
                           [lookupDetails addObject:objectID];
                       }
                   }
               }
                ];
               for (NSString * objectID in deletedShows) {
                   [self.showMap removeObjectForKey:objectID];
               }
               [self getShowInfoForShows: lookupDetails];
               if (!isFirstLaunch) {
                   [self.delegate tivoReportsNewShows:newIDs atTiVoIndices:indices andDeletedShows:deletedShows];
               }
           }
       } ];
}

-(void) reloadShowInfoForID: (NSString *) showID {
    if (!showID) return;
    MTRPCData * rpcData = self.showMap[showID];
    if (rpcData) {
        if (rpcData.series){
            [self.seriesImages removeObjectForKey:rpcData.series];
        }
        [self.showMap removeObjectForKey:showID];
    }
    [self getShowInfoForShows:@[showID]];
}

//static NSArray * showInfoResponseTemplate = nil;

-(void) getShowInfoForShows: (NSArray <NSString *> *) requestShows  {
    if (requestShows.count ==0) return;
    if (!self.bodyID) return;
    const int idsPerCall = 10;
    const float minTimePerCall = 1.0;
    NSArray <NSString *> *  subArray = nil;
    BOOL lastBatch = idsPerCall >= requestShows.count;
    if ( lastBatch) {
        subArray = requestShows;
    } else {
        subArray = [requestShows subarrayWithRange:NSMakeRange(0, idsPerCall)];
        NSArray <NSString *> * restArray = [requestShows subarrayWithRange:NSMakeRange(idsPerCall, requestShows.count -idsPerCall)];
        [self performSelector:@selector(getShowInfoForShows:) withObject:restArray afterDelay:minTimePerCall];
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
    [self sendRpcRequest:@"recordingSearch"
             monitor:NO
            withData:data
   completionHandler:^(NSDictionary *jsonResponse, BOOL isFinal) {
       NSArray * responseShows = jsonResponse[@"recording"];
       DDLogVerbose(@"Got ShowInfo from TiVo RPC: %@", [self maskTSN:jsonResponse]);
       if (responseShows.count == 0) return;
       if (responseShows.count != subArray.count) {
           DDLogMajor(@"Invalid # of TivoRPC shows: /n%@ /n%@", responseShows, subArray);
           return;
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
           rpcData.series = (NSString *)showInfo[@"title"];
//           NSString * mimeType = (NSString *)showInfo[@"mimeType"];  doesn't work!
//           if ([@"video/mpg2" isEqualToString:mimeType] ){
//               rpcData.format = MPEGFormatMP2;
//           } else if ([@"video/mpg4" isEqualToString:mimeType] ){
//               rpcData.format = MPEGFormatMP4;
//           } else {
//               rpcData.format = MPEGFormatOther;
//           }

           rpcData.rpcID = [NSString stringWithFormat: @"%@|%@", self.hostName, objectId];
           @synchronized (self.showMap) {
               [self.showMap setObject:rpcData forKey:objectId];
           }
           //very annoying that TiVo won't send over image information with the rest of the show info.
           NSString * imageURL = self.seriesImages[rpcData.series]; //tivo only has series images
           if (imageURL) {
               rpcData.imageURL = imageURL;
               [self.delegate receivedRPCData:rpcData];
           } else {
               NSString * contentId = showInfo[@"contentId"];
               if (contentId.length) {
                    [showsWithoutImage addObject:contentId];
                    [showsObjectIDs addObject:objectId];
                }
           }
           objectIDIndex++;
       }
       [self getImageFor:showsWithoutImage withObjectIds: showsObjectIDs];
           //leave some time for imageURLS, then save defaults.
       if (lastBatch) {
           dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
               [self saveDefaults];
           });
       }
   } ];
}

-(MTRPCData *) rpcDataForID: (NSString *) idString {
    @synchronized (self.showMap) {
        return self.showMap[idString];
    }
}

static NSArray * imageResponseTemplate = nil;

-(void) getImageFor: (NSArray <NSString *> *) contentIds withObjectIds: (NSArray <NSString *> *) objectIds {
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

    [self sendRpcRequest:@"contentSearch"
                 monitor:NO
                withData:data
       completionHandler:^(NSDictionary *jsonResponse, BOOL isFinal) {
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
                @synchronized (self.showMap) {
                   episodeInfo = self.showMap[objectIds[index]];
                   episodeInfo.imageURL  = imageURL;  //if none available, still mark as ""
                   NSString * title= episodeInfo.series;
                   if (!_seriesImages[title]) {
                       _seriesImages[title] = imageURL;
                   }
                }
                [self.delegate receivedRPCData:episodeInfo];
           }
       }
    }];
}

-(void) deleteShowsWithRecordIds: (NSArray <NSString *> *) recordingIds {
    if (recordingIds.count ==0) return;

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

-(void) receiveWakeNotification: (id) sender {
    [self checkStreamStatus];
}

-(void) stopServer {
    [self sharedShutdown];
}

-(void) sharedShutdown {
    [self.deadmanTimer invalidate]; self.deadmanTimer = nil;
    [self tearDownStreams];
    [self saveDefaults];
}

-(void) dealloc {
    [self sharedShutdown];
}

-(void) appWillTerminate: (id) notification {
    [self sharedShutdown];
    SecKeychainDelete(keychain);
    keychain = NULL;
}

@end


