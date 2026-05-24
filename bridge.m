#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>
#include "bridge.h"
#include "_cgo_export.h" // declares goBeginStroke, goAddPoint, ... goSnapshot, etc.

// Globals so the hotkey handler and menu can reach the window/view.
static NSWindow *gWindow = nil;
static NSView   *gCanvas = nil;

// ---- Canvas: renders Go's snapshot and forwards mouse input to Go ----

@interface CanvasView : NSView
@end

@implementation CanvasView

- (BOOL)isFlipped { return NO; } // bottom-left origin, matches mouse coords

- (void)drawRect:(NSRect)dirtyRect {
    [[NSColor clearColor] set];
    NSRectFill(dirtyRect);

    int n = 0;
    double *buf = goSnapshot(&n);
    if (buf == NULL || n < 1) {
        if (buf) goFreeSnapshot(buf);
        return;
    }

    int i = 0;
    int strokeCount = (int)buf[i++];
    for (int s = 0; s < strokeCount; s++) {
        double r = buf[i++], g = buf[i++], b = buf[i++], a = buf[i++];
        double width = buf[i++];
        int pts = (int)buf[i++];

        NSBezierPath *path = [NSBezierPath bezierPath];
        [path setLineWidth:width];
        [path setLineCapStyle:NSLineCapStyleRound];
        [path setLineJoinStyle:NSLineJoinStyleRound];

        for (int p = 0; p < pts; p++) {
            double x = buf[i++], y = buf[i++];
            if (p == 0) {
                [path moveToPoint:NSMakePoint(x, y)];
            } else {
                [path lineToPoint:NSMakePoint(x, y)];
            }
        }
        [[NSColor colorWithCalibratedRed:r green:g blue:b alpha:a] set];
        [path stroke];
    }
    goFreeSnapshot(buf);
}

- (void)mouseDown:(NSEvent *)e {
    NSPoint p = [self convertPoint:[e locationInWindow] fromView:nil];
    goBeginStroke(p.x, p.y);
    [self setNeedsDisplay:YES];
}

- (void)mouseDragged:(NSEvent *)e {
    NSPoint p = [self convertPoint:[e locationInWindow] fromView:nil];
    goAddPoint(p.x, p.y);
    [self setNeedsDisplay:YES];
}

- (void)mouseUp:(NSEvent *)e {
    goEndStroke();
    [self setNeedsDisplay:YES];
}

@end
