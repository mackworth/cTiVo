//
//  NSTask+RunTask.h
//  cTiVo
//
//  Created by Hugh Mackworth on 1/27/19.
//  Copyright © 2019 cTiVo. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSTask (RunTask)

+(NSString *) runProgram:(NSString *) path withArguments: (NSArray <NSString *> *) arguments;


@end

NS_ASSUME_NONNULL_END
