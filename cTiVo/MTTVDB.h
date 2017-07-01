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

-(void) resetAll;  //destroys all caches
-(void) saveDefaults; //writes caches to userdefaults

-(void)getTheTVDBDetails: (MTTiVoShow *) show;

-(void) rememberArtWork: (NSString *) newArtwork forSeries: (NSString *) seriesId;

-(NSString *) stats;
-(BOOL) isActive;

-(NSString *) seriesIDsForShow: (MTTiVoShow *) show;

@end
