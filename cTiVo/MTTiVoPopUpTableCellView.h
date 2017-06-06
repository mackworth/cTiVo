//
//  MTTiVoPopUpTableCellView
//  cTiVo
//
//  Created by Hugh Mackworth on 5/22/13.
//  Copyright (c) 2013 Hugh Mackworth. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "MTTiVoPopUpButton.h"

@interface MTTiVoPopUpTableCellView : NSTableCellView

@property (strong, nonatomic, readonly) MTTiVoPopUpButton *popUpButton;

- (id)initWithFrame:(NSRect)frame withTarget:(id)target withAction:(SEL)selector;

@end
