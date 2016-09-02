//
//  NSArray+Map.h
//  cTiVo
//
//  Created by Hugh Mackworth on 9/2/16.
//  Copyright © 2016 cTiVo. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NSArray (Map)

- (NSArray *)mapObjectsUsingBlock:(id (^)(id obj, NSUInteger idx))block;

@end
