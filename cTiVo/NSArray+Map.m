//
//  NSArray+Map.m
//  cTiVo
//
//  Created by Hugh Mackworth on 9/2/16.
//  Copyright © 2016 cTiVo. All rights reserved.
//

#import "NSArray+Map.h"

@implementation NSArray (Map)

- (NSArray *)mapObjectsUsingBlock:(id (^)(id obj, NSUInteger idx))block {
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:[self count]];
    [self enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        id newObj = block(obj, idx);
        if (newObj) {
            [result addObject: newObj ];
        }
    }];
    return [result copy];
}

- (instancetype)arrayByRemovingObject:(id)object {
	return [self filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"SELF != %@", object]];
}

@end
