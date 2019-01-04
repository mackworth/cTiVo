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

@property (nonatomic, strong) NSString	*formatDescription,
										*filenameExtension,
										*encoderUsed,
										*name,
                                        *encoderVideoOptions,
                                        *encoderAudioOptions,
                                        *encoderOtherOptions,
                                        *encoderEarlyVideoOptions,
                                        *encoderEarlyAudioOptions,
                                        *encoderEarlyOtherOptions,
                                        *encoderLateVideoOptions,
                                        *encoderLateAudioOptions,
                                        *encoderLateOtherOptions,
										*inputFileFlag,
										*outputFileFlag,
										*edlFlag,
										*comSkipOptions,
										*captionOptions,
										*regExProgress;

@property (nonatomic, readonly) NSString *transportStreamExtension;

@property (nonatomic, strong) NSNumber	*comSkip,
										*iTunes,
										*mustDownloadFirst,
                                        *isHidden,
										*isFactoryFormat;

@property (nonatomic, readonly) NSAttributedString *attributedFormatDescription;

@property (nonatomic, readonly) BOOL canAddToiTunes, canSimulEncode, isAvailable, canSkip, canAcceptMetaData, canMarkCommercials, isTestPS, isEncryptedDownload, testsForAudioOnly, isDeprecated, canDuplicate;
@property (nonatomic, strong) NSString * pathForExecutable;

@property (nonatomic, strong) NSString * formerName;//only used to update existing format objects when name is edited.


+(MTFormat *)formatWithDictionary:(NSDictionary *)format;
+(MTFormat *) formatWithEncFile: (NSString *) filename;

-(NSDictionary *)toDictionary;
-(BOOL)isSame:(MTFormat *)testFormat;

-(NSAttributedString *) attributedFormatStringForFont:(NSFont *) font;
-(void)checkAndUpdateFormatName:(NSArray *)formatList;


@end
