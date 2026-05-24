#import <Cocoa/Cocoa.h>
#import "hud.h"
#import "app_bridge.h"
#include "_cgo_export.h" // go* functions

// Persimmon UI accent (柿色).
static NSColor *KakiAccent(void) {
    return [NSColor colorWithCalibratedRed:0.878 green:0.388 blue:0.227 alpha:1.0];
}

// Wordmark font: bundled Shippori Mincho if available, else a system serif.
static NSFont *KakiWordmarkFont(CGFloat size) {
    NSFont *f = [NSFont fontWithName:@"Shippori Mincho SemiBold" size:size];
    if (!f) f = [NSFont fontWithName:@"Shippori Mincho" size:size];
    if (!f) f = [NSFont fontWithName:@"Hiragino Mincho ProN" size:size];
    if (!f) f = [NSFont fontWithDescriptor:
        [[NSFontDescriptor fontDescriptorWithName:@"Times New Roman" size:size]
            fontDescriptorWithSymbolicTraits:NSFontDescriptorTraitBold] size:size];
    return f;
}

// Drag-anywhere background view with a rounded, bordered fill over the vibrancy layer.
@interface KakiBackdrop : NSView
@end
@implementation KakiBackdrop
- (void)drawRect:(NSRect)r {
    NSBezierPath *p = [NSBezierPath bezierPathWithRoundedRect:self.bounds
                                                      xRadius:22 yRadius:22];
    [[NSColor colorWithCalibratedWhite:0.11 alpha:0.55] set]; // sumi tint over vibrancy
    [p fill];
    [[NSColor colorWithCalibratedWhite:1.0 alpha:0.07] set];  // hairline edge
    [p setLineWidth:1.0];
    [p stroke];
}
- (void)mouseDragged:(NSEvent *)e {
    [self.window performWindowDragWithEvent:e]; // drag the HUD by its body
}
@end

NSPanel *KakiMakeHUD(void) {
    NSRect frame = NSMakeRect(0, 0, 268, 300); // height refined as controls are added
    NSPanel *panel = [[NSPanel alloc]
        initWithContentRect:frame
                  styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel
                    backing:NSBackingStoreBuffered
                      defer:NO];
    [panel setOpaque:NO];
    [panel setBackgroundColor:[NSColor clearColor]];
    [panel setHasShadow:YES];
    [panel setLevel:NSStatusWindowLevel + 2]; // above the overlay (overlay is +1)
    [panel setCollectionBehavior:
        NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorStationary];
    [panel setMovableByWindowBackground:YES];

    // Vibrancy (dark blur) behind a rounded content view.
    NSVisualEffectView *vfx = [[NSVisualEffectView alloc] initWithFrame:frame];
    vfx.material = NSVisualEffectMaterialHUDWindow;
    vfx.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    vfx.state = NSVisualEffectStateActive;
    vfx.wantsLayer = YES;
    vfx.layer.cornerRadius = 22;
    vfx.layer.masksToBounds = YES;
    [panel setContentView:vfx];

    KakiBackdrop *bg = [[KakiBackdrop alloc] initWithFrame:frame];
    bg.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [vfx addSubview:bg];

    // Position near top-centre of the main screen.
    NSRect scr = [[NSScreen mainScreen] visibleFrame];
    NSPoint origin = NSMakePoint(NSMidX(scr) - frame.size.width/2,
                                 NSMaxY(scr) - frame.size.height - 40);
    [panel setFrameOrigin:origin];
    [panel orderFrontRegardless];
    return panel;
}

void KakiHUDSetDrawState(int on) { (void)on; /* wired in Task 5 */ }
