/*
     File: DragDropImageView.m 
 Abstract: Custom subclass of NSImageView with support for drag and drop operations. 
  Version: 1.1 
  
 Copyright (C) 2011 Apple Inc. All Rights Reserved. 
  
 */

#import "DragDropImageView.h"
@interface DragDropImageView ()
@property (nonatomic, assign) BOOL highlight;
@end


@implementation DragDropImageView


NSString *kPrivateDragUTI = @"com.pinetreesw.cocoadraganddrop";

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self setup];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) {
        [self setup];
    }
    return self;
}

- (void)setup {
    [self registerForDraggedTypes:[NSImage imagePasteboardTypes]];
    self.allowDrag = YES;
    self.allowDrop = YES;
    self.highlight = NO;
}

#pragma mark - Destination Operations

- (NSDragOperation)draggingEntered:(id <NSDraggingInfo>)sender {
    if (!self.allowDrop || sender.draggingSource == self)
        return NSDragOperationNone;
    /*------------------------------------------------------
        method called whenever a drag enters our drop zone
     --------------------------------------------------------*/
            // Check if the pasteboard contains image data and source/user wants it copied
    if ( [NSImage canInitWithPasteboard:[sender draggingPasteboard]] &&
             [sender draggingSourceOperationMask] &
             NSDragOperationCopy ) {
            
            //highlight our drop zone
        self.highlight=YES;
            
        [self setNeedsDisplay: YES];
    
            /* When an image from one window is dragged over another, we want to resize the dragging item to
             * preview the size of the image as it would appear if the user dropped it in. */
        [sender enumerateDraggingItemsWithOptions:NSDraggingItemEnumerationConcurrent 
            forView:self
            classes:[NSArray arrayWithObject:[NSPasteboardItem class]] 
            searchOptions:@{}
            usingBlock:^(NSDraggingItem *draggingItem, NSInteger idx, BOOL *stop) {
                
                    /* Only resize a dragging item if it originated from one of our windows.  To do this,
                     * we declare a custom UTI that will only be assigned to dragging items we created.  Here
                     * we check if the dragging item can represent our custom UTI.  If it can't we stop. */
                if ( ![[[draggingItem item] types] containsObject:kPrivateDragUTI] ) {
                    
                    *stop = YES;
                    
                } else {
                        /* In order for the dragging item to actually resize, we have to reset its contents.
                         * The frame is going to be the destination view's bounds.  (Coordinates are local 
                         * to the destination view here).
                         * For the contents, we'll grab the old contents and use those again.  If you wanted
                         * to perform other modifications in addition to the resize you could do that here. */
                    [draggingItem setDraggingFrame:self.bounds contents:[[[draggingItem imageComponents] objectAtIndex:0] contents]];
                }
            }];
        
        //accept data as a copy operation
        return NSDragOperationCopy;
    }
    
    return NSDragOperationNone;
}

- (void)draggingExited:(id <NSDraggingInfo>)sender {
    /*------------------------------------------------------
       method called whenever a drag exits our drop zone
    --------------------------------------------------------*/
        //remove highlight of the drop zone
    self.highlight=NO;
    
    [self setNeedsDisplay: YES];
}

-(void)drawRect:(NSRect)rect {
    /*------------------------------------------------------
        draw method is overridden to do drop highlighing
    --------------------------------------------------------*/
        //do the usual draw operation to display the image
    [super drawRect:rect];
    
    if ( self.highlight ) {
            //highlight by overlaying a gray border
        [[NSColor grayColor] set];
        [NSBezierPath setDefaultLineWidth: 5];
        [NSBezierPath strokeRect: rect];
    }
}

- (BOOL)prepareForDragOperation:(id <NSDraggingInfo>)sender {
    /*------------------------------------------------------
        method to determine if we can accept the drop
    --------------------------------------------------------*/
        //finished with the drag so remove any highlighting
    self.highlight=NO;
    
    [self setNeedsDisplay: YES];
    
        //check to see if we can accept the data
    return [NSImage canInitWithPasteboard: [sender draggingPasteboard]];
} 

- (BOOL)performDragOperation:(id <NSDraggingInfo>)sender {

    NSPasteboard *pboard = [sender draggingPasteboard];
    if ([NSImage canInitWithPasteboard: [sender draggingPasteboard]]) {
        NSImage * image = [[NSImage alloc] initWithPasteboard:pboard];
        if (image) {
            if ([self.delegate respondsToSelector:@selector(dropComplete:)]) {
                [self.delegate dropComplete:image];
            }
            return YES;
        } else {
            return NO;
        }
    }
    return NO;
}

- (NSRect)windowWillUseStandardFrame:(NSWindow *)window defaultFrame:(NSRect)newFrame {
    /*------------------------------------------------------
       delegate operation to set the standard window frame
    --------------------------------------------------------*/
        //get window frame size
    NSRect ContentRect=self.window.frame;
    
        //set it to the image frame size
    ContentRect.size=[[self image] size];
    
    return [NSWindow frameRectForContentRect:ContentRect styleMask: [window styleMask]];
};

#pragma mark - Source Operations

-(NSImage *) snapShot {
    NSData * data = [self dataWithPDFInsideRect:self.bounds];
    NSImage * image = [[NSImage alloc] initWithData:data];
    return image ?: [[NSImage alloc] init];
}

- (void)mouseDown:(NSEvent*)event {
    if (self.allowDrag) {
        NSPasteboardItem * pasteboardItem = [[NSPasteboardItem alloc] init];
        [pasteboardItem setDataProvider:self forTypes:@[NSPasteboardTypeTIFF ]];
        NSDraggingItem * draggingItem = [[NSDraggingItem alloc] initWithPasteboardWriter:pasteboardItem];
        [draggingItem setDraggingFrame:self.bounds contents:[self snapShot]];
        NSDraggingSession *draggingSession =[self beginDraggingSessionWithItems:@[draggingItem]
                                                                          event:event
                                                                         source:self];
        draggingSession.animatesToStartingPositionsOnCancelOrFail = YES;

        draggingSession.draggingFormation = NSDraggingFormationNone;

    }
}

-(void) draggingSession:(NSDraggingSession *)session endedAtPoint:(NSPoint)screenPoint operation:(NSDragOperation)operation {
    if (operation == NSDragOperationDelete) {
        if ([self.delegate respondsToSelector:@selector(dropComplete:)]) {
            [self.delegate dropComplete:nil];
        }
    }

}


- (NSDragOperation)draggingSession:(NSDraggingSession *)session sourceOperationMaskForDraggingContext:(NSDraggingContext)context
{
    /*------------------------------------------------------
     NSDraggingSource protocol method.  Returns the types of operations allowed in a certain context.
     --------------------------------------------------------*/
    switch (context) {
        case NSDraggingContextOutsideApplication:
            return NSDragOperationCopy | NSDragOperationDelete;
            
            //by using this fall through pattern, we will remain compatible if the contexts get more precise in the future.
        case NSDraggingContextWithinApplication:
        default:
            return NSDragOperationCopy;
            break;
    }
}

- (BOOL)acceptsFirstMouse:(NSEvent *)event
{
    /*------------------------------------------------------
     accept activation click as click in window
     --------------------------------------------------------*/
    //so source doesn't have to be the active window
    return YES;
}


- (void)pasteboard:(NSPasteboard *)sender item:(NSPasteboardItem *)item provideDataForType:(NSString *)type
{
    /*------------------------------------------------------
       	method called by pasteboard to support promised 
        drag types.
    --------------------------------------------------------*/
        //sender has accepted the drag and now we need to send the data for the type we promised
    if ( [type compare: NSPasteboardTypeTIFF] == NSOrderedSame ) {
        
            //set data for TIFF type on the pasteboard as requested
        [sender setData:[[self image] TIFFRepresentation] forType:NSPasteboardTypeTIFF];
        
    } else if ( [type compare: NSPasteboardTypePDF] == NSOrderedSame ) {
        
            //set data for PDF type on the pasteboard as requested
        [sender setData:[self dataWithPDFInsideRect:[self bounds]] forType:NSPasteboardTypePDF];
    }
    
}
@end
