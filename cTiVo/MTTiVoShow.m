//
//  MTTiVoShow.m
//  cTiVo
//
//  Created by Scott Buchanan on 12/18/12.
//  Copyright (c) 2012 Scott Buchanan. All rights reserved.
//
// Class for handling individual TiVo Shows

#import "MTTiVoShow.h"

@implementation MTTiVoShow

-(id)init
{
    self = [super init];
    if (self) {
        activeTask = nil;
        _showID = 0;
        _showStatus = @"";
		targetFilePath = nil;
		sourceFilePath = nil;
    }
    return self;
}


#pragma mark - Download decrypt and encode Methods

-(void)download
{
    NSURLRequest *thisRequest = [NSURLRequest requestWithURL:[NSURL URLWithString:_urlString ]];
    activeURLConnection = [NSURLConnection connectionWithRequest:thisRequest delegate:self];
    targetFilePath = [NSString stringWithFormat:@"%@%@.tivo",_downloadDirectory ,_title];
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm createFileAtPath:targetFilePath contents:[NSData data] attributes:nil];
    activeFile = [NSFileHandle fileHandleForWritingAtPath:targetFilePath];
    [activeURLConnection start];
    dataDownloaded = 0.0;
    _downloadStatus = kMTStatusDownloading;
	_showStatus = @"Downloading";
}

-(void)decrypt
{
	targetFilePath = [NSString stringWithFormat:@"/tmp/decoding%@.txt",_title];
	[[NSFileManager defaultManager] createFileAtPath:targetFilePath contents:[NSData data] attributes:nil];
	activeFile = [NSFileHandle fileHandleForWritingAtPath:targetFilePath];
	activeTask = [[NSTask alloc] init];
	[activeTask setLaunchPath:[[NSBundle mainBundle] pathForResource:@"tivodecode" ofType:@""]];
	[activeTask setStandardOutput:activeFile];
	[activeTask setStandardError:activeFile];
	//Find the source file size
	sourceFilePath = [NSString stringWithFormat:@"%@/%@.tivo",_downloadDirectory,_title];
	NSFileHandle *sourceFileHandle = [NSFileHandle fileHandleForReadingAtPath:sourceFilePath];
	_fileSize = (double)[sourceFileHandle seekToEndOfFile];
	
    // tivodecode -m0636497662 -o Two\ and\ a\ Half\ Men.mpg -v Two\ and\ a\ Half\ Men.TiVo
    
	NSArray *arguments = [NSArray arrayWithObjects:
						  [NSString stringWithFormat:@"-m%@",_mediaKey],
						  [NSString stringWithFormat:@"-o%@%@.tivo.mpg",_downloadDirectory,_title],
						  @"-v",
						  [NSString stringWithFormat:@"%@%@.tivo",_downloadDirectory,_title],
						  nil];
    _processProgress = 0.0;
 	[[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationProgressUpdated object:nil];
   _downloadStatus = kMTStatusDecrypting;
	_showStatus = @"Decrypting";
	[activeTask setArguments:arguments];
	[activeTask launch];
	[self performSelector:@selector(trackDecrypts) withObject:nil afterDelay:0.3];
	
}

-(void)trackDecrypts
{
	if (![activeTask isRunning]) {
		_processProgress = 1.0;
		[[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationProgressUpdated object:nil];
        _downloadStatus = kMTStatusDecrypted;
		NSError *thisError = nil;
		[[NSFileManager defaultManager] removeItemAtPath:sourceFilePath error:&thisError];
		sourceFilePath = nil;
		targetFilePath = nil;
		activeTask = nil;
       [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationDecryptDidFinish object:nil];
		return;
	}
	NSString *readFile = [NSString stringWithFormat:@"/tmp/decoding%@.txt",_title];
	NSFileHandle *readFileHandle = [NSFileHandle fileHandleForReadingAtPath:readFile];
	unsigned long long fileSize = [readFileHandle seekToEndOfFile];
	if (fileSize > 100) {
		[readFileHandle seekToFileOffset:(fileSize-100)];
		NSData *tailOfFile = [readFileHandle readDataOfLength:100];
		NSString *data = [[NSString alloc] initWithData:tailOfFile encoding:NSUTF8StringEncoding];
		NSArray *lines = [data componentsSeparatedByString:@"\n"];
		data = [lines objectAtIndex:lines.count-2];
		lines = [data componentsSeparatedByString:@":"];
		double position = [[lines objectAtIndex:0] doubleValue];
		_processProgress = position/_fileSize;
		[[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationProgressUpdated object:nil];
       
	}
	[self performSelector:@selector(trackDecrypts) withObject:nil afterDelay:0.3];
    
    [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationProgressUpdated object:nil];
	
	
}

-(void)encode
{
	targetFilePath = [NSString stringWithFormat:@"/tmp/encoding%@.txt",_title];
	sourceFilePath = [NSString stringWithFormat:@"%@/%@.tivo.mpg",_downloadDirectory,_title];
	[[NSFileManager defaultManager] createFileAtPath:targetFilePath contents:[NSData data] attributes:nil];
	activeFile = [NSFileHandle fileHandleForWritingAtPath:targetFilePath];
	activeTask = [[NSTask alloc] init];
//	NSDictionary *selectedFormat = [programEncoding objectForKey:kMTSelectedFormat];
	NSMutableArray *arguments = [NSMutableArray array];
	if ([(NSString *)[_encodeFormat objectForKey:@"encoderUsed"] caseInsensitiveCompare:@"mencoder"] == NSOrderedSame ) {
        
		[activeTask setLaunchPath:[[NSBundle mainBundle] pathForResource:@"mencoder" ofType:@""]];
		[arguments addObject:sourceFilePath];  //start with the input file
		[arguments addObjectsFromArray:[[_encodeFormat objectForKey:@"encoderVideoOptions"] componentsSeparatedByString:@" "]];
		[arguments addObjectsFromArray:[[_encodeFormat objectForKey:@"encoderAudioOptions"] componentsSeparatedByString:@" "]];
		[arguments addObjectsFromArray:[[_encodeFormat objectForKey:@"encoderOtherOptions"] componentsSeparatedByString:@" "]];
		[arguments addObject:@"-o"];
		[arguments addObject:[NSString stringWithFormat:@"%@/%@%@",_downloadDirectory,_title,[_encodeFormat objectForKey:@"filenameExtension"]]];
		
	}
	if ([(NSString *)[_encodeFormat objectForKey:@"encoderUsed"] caseInsensitiveCompare:@"HandBrake"] == NSOrderedSame ) {
		[activeTask setLaunchPath:[[NSBundle mainBundle] pathForResource:@"HandBrakeCLI" ofType:@""]];
		[arguments addObject:sourceFilePath];  //start with the input file
		[arguments addObject:[NSString stringWithFormat:@"-o%@/%@%@",_downloadDirectory,_title,[_encodeFormat objectForKey:@"filenameExtension"]]];  //add the output file
		[arguments addObject:[_encodeFormat objectForKey:@"encoderVideoOptions"]];
		if ([_encodeFormat objectForKey:@"encoderAudioOptions"] && ((NSString *)[_encodeFormat objectForKey:@"encoderAudioOptions"]).length) {
			[arguments addObject:[_encodeFormat objectForKey:@"encoderAudioOptions"]];
		}
		if ([_encodeFormat objectForKey:@"encoderOtherOptions"] && ((NSString *)[_encodeFormat objectForKey:@"encoderOtherOptions"]).length) {
			[arguments addObject:[_encodeFormat objectForKey:@"encoderOtherOptions"]];
		}
	}
	[activeTask setArguments:arguments];
	[activeTask setStandardOutput:activeFile];
	[activeTask setStandardError:[NSFileHandle fileHandleForWritingAtPath:@"/dev/null"]];
    _processProgress = 0.0;
	[[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationProgressUpdated object:nil];
	[activeTask launch];
    _downloadStatus = kMTStatusEncoding;
	_showStatus = @"Encoding";
	[self performSelector:@selector(trackEncodes) withObject:nil afterDelay:0.5];
	
}

-(void)trackEncodes
{
	if (![activeTask isRunning]) {
        _processProgress = 1.0;
        [[NSFileManager defaultManager] removeItemAtPath:sourceFilePath error:nil];
		sourceFilePath = nil;
		targetFilePath = nil;
		activeTask = nil;
        _showStatus = @"Complete";
        _downloadStatus = kMTStatusDone;
		[[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationProgressUpdated object:nil];
        [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationEncodeDidFinish object:nil];
		return;
	}
	NSString *readFile = [NSString stringWithFormat:@"/tmp/encoding%@.txt",_title];
	NSFileHandle *readFileHandle = [NSFileHandle fileHandleForReadingAtPath:readFile];
	unsigned long long fileSize = [readFileHandle seekToEndOfFile];
	if (fileSize > 100) {
		[readFileHandle seekToFileOffset:(fileSize-100)];
		NSData *tailOfFile = [readFileHandle readDataOfLength:100];
		NSString *data = [[NSString alloc] initWithData:tailOfFile encoding:NSUTF8StringEncoding];
		if ([(NSString *)[_encodeFormat objectForKey:@"encoderUsed"] caseInsensitiveCompare:@"mencoder"] == NSOrderedSame) {
			NSRegularExpression *percents = [NSRegularExpression regularExpressionWithPattern:@"\\((.*?)\\%\\)" options:NSRegularExpressionCaseInsensitive error:nil];
			NSArray *values = [percents matchesInString:data options:NSMatchingWithoutAnchoringBounds range:NSMakeRange(0, data.length)];
			NSTextCheckingResult *lastItem = [values lastObject];
			NSRange valueRange = [lastItem rangeAtIndex:1];
			_processProgress = [[data substringWithRange:valueRange] doubleValue]/100.0;
			[[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationProgressUpdated object:nil];
		}
		if ([(NSString *)[_encodeFormat objectForKey:@"encoderUsed"] caseInsensitiveCompare:@"HandBrake"] == NSOrderedSame) {
			NSRegularExpression *percents = [NSRegularExpression regularExpressionWithPattern:@" ([\\d.]*?) \\% " options:NSRegularExpressionCaseInsensitive error:nil];
			NSArray *values = [percents matchesInString:data options:NSMatchingWithoutAnchoringBounds range:NSMakeRange(0, data.length)];
			if (values.count) {
				NSTextCheckingResult *lastItem = [values lastObject];
				NSRange valueRange = [lastItem rangeAtIndex:1];
				_processProgress = [[data substringWithRange:valueRange] doubleValue]/102.0;
				[[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationProgressUpdated object:nil];
			}
		}
		
	}
	[self performSelector:@selector(trackEncodes) withObject:nil afterDelay:0.5];
    [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationProgressUpdated object:nil];	
}

-(BOOL)cancel
{
    BOOL ret = YES;
    if (_downloadStatus != kMTStatusNew && _downloadStatus != kMTStatusDone) {
		//Put alert here
		NSAlert *myAlert = [NSAlert alertWithMessageText:[NSString stringWithFormat:@"Do you want to cancel Download of %@",_title] defaultButton:@"No" alternateButton:@"Yes" otherButton:nil informativeTextWithFormat:@""];
		myAlert.alertStyle = NSCriticalAlertStyle;
		NSInteger result = [myAlert runModal];
		if (result == NSAlertAlternateReturn) {
			NSFileManager *fm = [NSFileManager defaultManager];
			if (_downloadStatus == kMTStatusDownloading && activeURLConnection) {
				[activeURLConnection cancel];
				activeURLConnection = nil;
				[fm removeItemAtPath:targetFilePath error:nil];
			} else if(activeTask && [activeTask isRunning]) {
				[activeTask terminate];
				[fm removeItemAtPath:sourceFilePath error:nil];
				[fm removeItemAtPath:targetFilePath error:nil];
			}
		} else {
			ret = NO;
		}

    }
    return ret;
}

#pragma mark - NSURL Delegate Methods

-(void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data
{
		[activeFile writeData:data];
        //        NSLog(@"Data Downloaded = %lf",dataDownloaded);
		dataDownloaded += data.length;
		_processProgress = dataDownloaded/_fileSize;
	[[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationProgressUpdated object:nil];
}

- (BOOL)connection:(NSURLConnection *)connection canAuthenticateAgainstProtectionSpace:(NSURLProtectionSpace *)protectionSpace {
    return [protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust];
}

- (void)connection:(NSURLConnection *)connection didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge {
    //    [challenge.sender useCredential:[NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust] forAuthenticationChallenge:challenge];
    [challenge.sender useCredential:[NSURLCredential credentialWithUser:@"tivo" password:_mediaKey persistence:NSURLCredentialPersistencePermanent] forAuthenticationChallenge:challenge];
    [challenge.sender continueWithoutCredentialForAuthenticationChallenge:challenge];
}

-(void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error
{
    NSLog(@"URL Connection Failed with error %@",error);
	_downloadStatus = kMTStatusNew;
	activeURLConnection = nil;
}


-(void)connectionDidFinishLoading:(NSURLConnection *)connection
{
    [activeFile closeFile];
    _downloadStatus = kMTStatusDownloaded  ;
	activeURLConnection = nil;
    [[NSNotificationCenter defaultCenter] postNotificationName:kMTNotificationDownloadDidFinish object:nil];
}

#pragma mark - Memory Management



@end
