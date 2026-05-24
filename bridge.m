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

// ---- Menu bar: colour, width, clear, quit ----

static NSStatusItem *gStatusItem = nil;

@interface MenuController : NSObject
@end

@implementation MenuController

- (void)setRed:(id)s   { goSetColor(1, 0, 0, 1); }
- (void)setGreen:(id)s { goSetColor(0, 0.7, 0, 1); }
- (void)setBlue:(id)s  { goSetColor(0, 0, 1, 1); }
- (void)setYellow:(id)s{ goSetColor(1, 0.85, 0, 1); }

- (void)setThin:(id)s   { goSetWidth(2); }
- (void)setMedium:(id)s { goSetWidth(5); }
- (void)setThick:(id)s  { goSetWidth(10); }

- (void)clearAll:(id)s {
    goClear();
    [gCanvas setNeedsDisplay:YES];
}

- (void)quit:(id)s { [NSApp terminate:nil]; }

@end

static MenuController *gMenuController = nil;

static void buildStatusItem(void) {
    gStatusItem = [[NSStatusBar systemStatusBar]
        statusItemWithLength:NSVariableStatusItemLength];
    gStatusItem.button.title = @"✎";

    gMenuController = [[MenuController alloc] init];
    NSMenu *menu = [[NSMenu alloc] init];

    NSMenu *colorMenu = [[NSMenu alloc] init];
    [colorMenu addItemWithTitle:@"Red"    action:@selector(setRed:)    keyEquivalent:@""].target = gMenuController;
    [colorMenu addItemWithTitle:@"Green"  action:@selector(setGreen:)  keyEquivalent:@""].target = gMenuController;
    [colorMenu addItemWithTitle:@"Blue"   action:@selector(setBlue:)   keyEquivalent:@""].target = gMenuController;
    [colorMenu addItemWithTitle:@"Yellow" action:@selector(setYellow:) keyEquivalent:@""].target = gMenuController;
    NSMenuItem *colorItem = [[NSMenuItem alloc] initWithTitle:@"Colour" action:nil keyEquivalent:@""];
    [colorItem setSubmenu:colorMenu];
    [menu addItem:colorItem];

    NSMenu *widthMenu = [[NSMenu alloc] init];
    [widthMenu addItemWithTitle:@"Thin"   action:@selector(setThin:)   keyEquivalent:@""].target = gMenuController;
    [widthMenu addItemWithTitle:@"Medium" action:@selector(setMedium:) keyEquivalent:@""].target = gMenuController;
    [widthMenu addItemWithTitle:@"Thick"  action:@selector(setThick:)  keyEquivalent:@""].target = gMenuController;
    NSMenuItem *widthItem = [[NSMenuItem alloc] initWithTitle:@"Width" action:nil keyEquivalent:@""];
    [widthItem setSubmenu:widthMenu];
    [menu addItem:widthItem];

    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"Clear (⌥⌘C)" action:@selector(clearAll:) keyEquivalent:@""].target = gMenuController;
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"Quit" action:@selector(quit:) keyEquivalent:@""].target = gMenuController;

    gStatusItem.menu = menu;
}
