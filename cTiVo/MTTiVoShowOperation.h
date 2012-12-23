//
//  MTTivoShowOperation.h
//  cTiVo
//
//  Created by Scott Buchanan on 12/22/12.
//  Copyright (c) 2012 Scott Buchanan. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "MTTiVoShow.h"  

@interface MTTiVoShowOperation : NSOperation

@property (nonatomic, retain) MTTiVoShow *tiVoShow;

@end
