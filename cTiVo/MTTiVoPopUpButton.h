//
//  MTTivoPopUpButton
//  cTiVo
//
//  Created by Hugh Mackworth on 5/22/13.
//  Copyright (c) 2013 Hugh Mackworth. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "MTTiVoManager.h"

@interface MTTiVoPopUpButton : NSPopUpButton

@property (strong) id owner;
@property (nonatomic, strong) NSString * currentTivo;
-(void) refreshMenu;

@end
