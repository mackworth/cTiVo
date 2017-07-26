/*
     File: DragDropImageView.h
 Abstract: Custom subclass of NSImageView with support for drag and drop operations.
  Version: 1.1
 
 Copyright (C) 2011 Apple Inc. All Rights Reserved.
 
 */

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

@protocol DragDropImageViewDelegate;

@interface DragDropImageView : NSImageView <NSDraggingSource, NSDraggingDestination, NSPasteboardItemDataProvider>

IBInspectable @property (nonatomic, assign) BOOL allowDrag;
IBInspectable @property (nonatomic, assign) BOOL allowDrop;
IBInspectable@property (nonatomic, assign) IBOutlet id<DragDropImageViewDelegate> delegate;

@end

@protocol DragDropImageViewDelegate <NSObject>

- (void)dropComplete:(NSImage *) image;

@end
