//
//  MTTiVoShow.h
//  cTiVo
//
//  Created by Scott Buchanan on 12/18/12.
//  Copyright (c) 2012 Scott Buchanan. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface MTTiVoShow : NSObject {
    NSFileHandle *activeFile;
    double dataDownloaded;
    NSTask *activeTask;
	NSURLConnection *activeURLConnection;
	NSString *sourceFilePath, *targetFilePath;
}

@property (nonatomic, strong) NSString *urlString, *downloadDirectory, *mediaKey, *title, *description, *showStatus;
@property (nonatomic, strong) NSURL *URL;
@property int downloadStatus, showID;
@property double processProgress; //Should be between 0 and 1
@property double fileSize;  //Size on TiVo;
@property (nonatomic, strong) NSDictionary *encodeFormat;
@property (nonatomic, strong) NSNetService *tiVo;


-(BOOL)cancel;
-(void)download;
-(void)decrypt;
-(void)encode;



@end
