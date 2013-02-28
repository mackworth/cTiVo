//
//  NSString+RFC3339Date.h
//  cTiVo
//
//  Created by Hugh Mackworth on 2/26/13.
//  Copyright (c) 2013 Scott Buchanan. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NSString (RFC3339Date)

-(NSDate *)dateForRFC3339DateTimeString;


@end
