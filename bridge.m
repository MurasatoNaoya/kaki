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

// ---- Global hotkeys (Carbon — no Accessibility permission needed) ----

enum { HOTKEY_TOGGLE = 1, HOTKEY_CLEAR = 2 };

static OSStatus hotKeyHandler(EventHandlerCallRef next, EventRef e, void *ud) {
    (void)next; (void)ud;
    EventHotKeyID hk;
    GetEventParameter(e, kEventParamDirectObject, typeEventHotKeyID, NULL,
                      sizeof(hk), NULL, &hk);

    if (hk.id == HOTKEY_TOGGLE) {
        int on = goToggleMode();
        // Drawing on => capture mouse; off => clicks pass through.
        [gWindow setIgnoresMouseEvents:(on ? NO : YES)];
        if (on) {
            [gWindow makeKeyAndOrderFront:nil];
        }
    } else if (hk.id == HOTKEY_CLEAR) {
        goClear();
        [gCanvas setNeedsDisplay:YES];
    }
    return noErr;
}

static void registerHotKeys(void) {
    EventTypeSpec spec = { kEventClassKeyboard, kEventHotKeyPressed };
    InstallApplicationEventHandler(&hotKeyHandler, 1, &spec, NULL, NULL);

    EventHotKeyRef ref;
    // ⌥⌘D toggle draw mode. kVK_ANSI_D == 2.
    EventHotKeyID toggleID = { 'tgld', HOTKEY_TOGGLE };
    RegisterEventHotKey(2, optionKey | cmdKey, toggleID,
                        GetApplicationEventTarget(), 0, &ref);

    // ⌥⌘C clear. kVK_ANSI_C == 8.
    EventHotKeyID clearID = { 'tglc', HOTKEY_CLEAR };
    RegisterEventHotKey(8, optionKey | cmdKey, clearID,
                        GetApplicationEventTarget(), 0, &ref);
}

// ---- Entry point ----

void RunApp(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        // Accessory => menu-bar agent: no dock icon, does not steal focus.
        [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];

        NSRect frame = [[NSScreen mainScreen] frame];

        gWindow = [[NSPanel alloc]
            initWithContentRect:frame
                      styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel
                        backing:NSBackingStoreBuffered
                          defer:NO];
        [gWindow setOpaque:NO];
        [gWindow setBackgroundColor:[NSColor clearColor]];
        [gWindow setLevel:NSStatusWindowLevel + 1]; // float above normal windows
        [gWindow setIgnoresMouseEvents:YES];         // start in pass-through (draw off)
        [gWindow setHasShadow:NO];
        [gWindow setCollectionBehavior:
            NSWindowCollectionBehaviorCanJoinAllSpaces |
            NSWindowCollectionBehaviorStationary];

        gCanvas = [[CanvasView alloc] initWithFrame:frame];
        [gWindow setContentView:gCanvas];
        [gWindow orderFrontRegardless];

        buildStatusItem();
        registerHotKeys();

        [NSApp run];
    }
}
