//
//  MTTVDBManager.h
//  cTiVo
//
//  Created by Hugh Mackworth on 6/30/17.
//  Copyright © 2017 cTiVo. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "MTTiVoShow.h"

@interface MTTVDB : NSObject

+ (MTTVDB *)sharedManager;

-(void) getTheTVDBDetails: (MTTiVoShow *) show;
-(void) retrieveArtworkForShow: (MTTiVoShow *) show cacheVersion: (BOOL) cache;

-(void) reloadTVDBInfo:(MTTiVoShow *) show;
-(void) resetAll;  //destroys all caches
-(void) saveDefaults; //writes caches to userdefaults
-(NSString *) stats;
-(BOOL) isActive;

-(NSString *) seriesIDsForShow: (MTTiVoShow *) show;

@end
