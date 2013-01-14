//
//  MTFormat.h
//  cTiVo
//
//  Created by Scott Buchanan on 1/12/13.
//  Copyright (c) 2013 Scott Buchanan. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface MTFormat : NSObject <NSCopying> {
	NSArray *keys;
}

@property (nonatomic, retain) NSString	*formatDescription,
										*filenameExtension,
										*encoderUsed,
										*name,
										*encoderVideoOptions,
										*encoderAudioOptions,
										*encoderOtherOptions,
										*inputFileFlag,
										*outputFileFlag,
										*regExProgress;

@property (nonatomic, retain) NSNumber	*comSkip,
										*iTunes,
										*mustDownloadFirst,
										*isFactoryFormat;

@property (nonatomic, retain) NSAttributedString *attributedFormatDescription;


+(MTFormat *)formatWithDictionary:(NSDictionary *)format;

-(NSDictionary *)toDictionary;
-(BOOL)isSame:(MTFormat *)testFormat;

@end
