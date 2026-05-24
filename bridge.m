#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>
#include "bridge.h"
#include "_cgo_export.h" // declares goBeginStroke, goAddPoint, ... goSnapshot, etc.

// Globals so the hotkey handler and menu can reach the window/view.
// These are allocated once in RunApp and intentionally owned for the
// process lifetime (never released under MRC).
static NSWindow *gWindow = nil;
static NSView   *gCanvas = nil;

// Borderless/non-activating panels won't become key by default, so clicks
// are dropped. Override canBecomeKeyWindow so the overlay receives mouse input.
@interface OverlayPanel : NSPanel
@end
@implementation OverlayPanel
- (BOOL)canBecomeKeyWindow { return YES; }
@end

// ---- Canvas: renders Go's snapshot and forwards mouse input to Go ----

@interface CanvasView : NSView
@end

@implementation CanvasView

- (BOOL)isFlipped { return NO; } // bottom-left origin, matches mouse coords

- (BOOL)acceptsFirstMouse:(NSEvent *)e { return YES; } // first click after focus loss still draws

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
    OSStatus installStatus =
        InstallApplicationEventHandler(&hotKeyHandler, 1, &spec, NULL, NULL);
    if (installStatus != noErr) {
        NSLog(@"screenpen: InstallApplicationEventHandler failed (status %d)",
              (int)installStatus);
    }

    // Refs are intentionally kept for the process lifetime (never unregistered).
    EventHotKeyRef toggleRef;
    EventHotKeyRef clearRef;

    // ⌥⌘D toggle draw mode.
    EventHotKeyID toggleID = { 'tgld', HOTKEY_TOGGLE };
    OSStatus toggleStatus =
        RegisterEventHotKey(kVK_ANSI_D, optionKey | cmdKey, toggleID,
                            GetApplicationEventTarget(), 0, &toggleRef);
    if (toggleStatus != noErr) {
        NSLog(@"screenpen: failed to register ⌥⌘D toggle hotkey (status %d)",
              (int)toggleStatus);
    }

    // ⌥⌘C clear.
    EventHotKeyID clearID = { 'tglc', HOTKEY_CLEAR };
    OSStatus clearStatus =
        RegisterEventHotKey(kVK_ANSI_C, optionKey | cmdKey, clearID,
                            GetApplicationEventTarget(), 0, &clearRef);
    if (clearStatus != noErr) {
        NSLog(@"screenpen: failed to register ⌥⌘C clear hotkey (status %d)",
              (int)clearStatus);
    }
}

// ---- App delegate: Dock reopen + standard app menu ----

static NSPanel *gHUD = nil; // the control HUD, created in RunApp via KakiMakeHUD

@interface KakiAppDelegate : NSObject <NSApplicationDelegate>
@end

@implementation KakiAppDelegate
// Clicking the Dock icon (when the HUD was closed/hidden) re-shows it.
- (BOOL)applicationShouldHandleReopen:(NSApplication *)app hasVisibleWindows:(BOOL)vis {
    if (gHUD) { [gHUD makeKeyAndOrderFront:nil]; }
    return YES;
}
@end

static KakiAppDelegate *gAppDelegate = nil;

// Minimal main menu so ⌘Q works in a Regular app.
static void buildAppMenu(void) {
    NSMenu *mainMenu = [[NSMenu alloc] init];
    NSMenuItem *appItem = [[NSMenuItem alloc] init];
    [mainMenu addItem:appItem];
    NSMenu *appMenu = [[NSMenu alloc] init];
    [appMenu addItemWithTitle:@"Quit Kaki"
                       action:@selector(terminate:)
                keyEquivalent:@"q"];
    [appItem setSubmenu:appMenu];
    [NSApp setMainMenu:mainMenu];
}

// ---- Entry point ----

void RunApp(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular]; // Dock app
        gAppDelegate = [[KakiAppDelegate alloc] init];
        [NSApp setDelegate:gAppDelegate];

        NSRect frame = [[NSScreen mainScreen] frame];

        gWindow = [[OverlayPanel alloc]
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

        buildAppMenu();
        registerHotKeys();

        [NSApp run];
    }
}
