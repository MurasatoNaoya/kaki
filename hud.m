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

typedef struct { CGFloat r, g, b; const char *name; } KakiColor;
static const KakiColor kPresetColors[] = {
    {0.898, 0.282, 0.302, "red"},
    {0.961, 0.510, 0.122, "orange"},
    {0.949, 0.757, 0.180, "yellow"},
    {0.184, 0.682, 0.369, "green"},
    {0.184, 0.435, 0.929, "blue"},
    {0.000, 0.000, 0.000, "black"},
    {1.000, 1.000, 1.000, "white"},
};
static const int kPresetCount = 7;

// The 柿 wordmark label, recoloured to the active pen colour.
static NSTextField *gKanji = nil;
// All swatch views, so selection (ring) is mutually exclusive.
static NSMutableArray *gSwatches = nil;

@interface KakiSwatch : NSView
@property (nonatomic) NSColor *fill;
@property (nonatomic) BOOL selected;
@property (nonatomic) BOOL isAdd;      // the "+" custom-picker cell
@property (nonatomic, copy) void (^onPick)(NSColor *);
@end

@implementation KakiSwatch
- (void)drawRect:(NSRect)r {
    NSRect c = NSInsetRect(self.bounds, 4, 4);
    NSBezierPath *circle = [NSBezierPath bezierPathWithOvalInRect:c];
    if (self.isAdd) {
        [[NSColor colorWithCalibratedWhite:0.5 alpha:1.0] set];
        [circle setLineWidth:1.5];
        CGFloat d[2] = {3,3}; [circle setLineDash:d count:2 phase:0];
        [circle stroke];
        NSDictionary *attr = @{ NSForegroundColorAttributeName:[NSColor colorWithCalibratedWhite:0.72 alpha:1],
                                NSFontAttributeName:[NSFont systemFontOfSize:15 weight:NSFontWeightThin] };
        NSString *plus = @"+";
        NSSize sz = [plus sizeWithAttributes:attr];
        [plus drawAtPoint:NSMakePoint(NSMidX(c)-sz.width/2, NSMidY(c)-sz.height/2) withAttributes:attr];
        return;
    }
    [self.fill set];
    [circle fill];
    [[NSColor colorWithCalibratedWhite:(self.fill == NSColor.whiteColor ? 0.6 : 0.0) alpha:0.35] set];
    [circle setLineWidth:1.0];
    [circle stroke];
    if (self.selected) {
        NSBezierPath *ring = [NSBezierPath bezierPathWithOvalInRect:NSInsetRect(self.bounds, 1, 1)];
        [KakiAccent() set];
        [ring setLineWidth:2.0];
        [ring stroke];
    }
}
- (void)mouseDown:(NSEvent *)e { if (self.onPick) self.onPick(self.fill); }
@end

// --- Custom "+" colour-panel observer (Task 4 Step 3) ---
static NSTextField *gColorPanelKanji = nil;

@interface KakiColorObserver : NSObject
@end
@implementation KakiColorObserver
- (void)kakiColorChanged:(NSColorPanel *)cp {
    NSColor *c = [cp.color colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]];
    if (!c) return;
    goSetColor(c.redComponent, c.greenComponent, c.blueComponent, 1.0);
    if (gColorPanelKanji) gColorPanelKanji.textColor = c;
}
@end
static KakiColorObserver *gColorObserver = nil;

NSPanel *KakiMakeHUD(void) {
    if (!gColorObserver) gColorObserver = [[KakiColorObserver alloc] init];

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

    gSwatches = [NSMutableArray array];

    // --- Wordmark row (柿 kaki) ---
    gKanji = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 258, 30, 28)];
    [gKanji setBezeled:NO]; [gKanji setEditable:NO]; [gKanji setSelectable:NO];
    [gKanji setDrawsBackground:NO];
    gKanji.font = KakiWordmarkFont(20);
    gKanji.stringValue = @"柿";
    // light hairline so dark/black inks stay legible on the dark panel
    gKanji.wantsLayer = YES;
    gKanji.layer.shadowColor = [NSColor colorWithCalibratedWhite:1 alpha:0.5].CGColor;
    gKanji.layer.shadowRadius = 0.6; gKanji.layer.shadowOpacity = 1.0;
    gKanji.layer.shadowOffset = CGSizeZero;
    [bg addSubview:gKanji];

    NSTextField *name = [[NSTextField alloc] initWithFrame:NSMakeRect(50, 260, 120, 24)];
    [name setBezeled:NO]; [name setEditable:NO]; [name setSelectable:NO]; [name setDrawsBackground:NO];
    name.font = KakiWordmarkFont(18);
    name.textColor = [NSColor colorWithCalibratedWhite:0.94 alpha:1.0];
    name.stringValue = @"kaki";
    [bg addSubview:name];

    // --- Colour grid (4 columns x 2 rows): 7 presets + "+" ---
    CGFloat gx = 20, gy = 150, cell = 52, gap = 6;
    void (^applyColor)(CGFloat,CGFloat,CGFloat) = ^(CGFloat r, CGFloat g, CGFloat b){
        goSetColor(r, g, b, 1.0);
        gKanji.textColor = [NSColor colorWithCalibratedRed:r green:g blue:b alpha:1.0];
    };
    for (int i = 0; i < kPresetCount; i++) {
        int col = i % 4, row = i / 4;
        NSRect fr = NSMakeRect(gx + col*(cell+gap), gy - row*(cell+gap), cell, cell);
        KakiSwatch *sw = [[KakiSwatch alloc] initWithFrame:fr];
        KakiColor kc = kPresetColors[i];
        sw.fill = [NSColor colorWithCalibratedRed:kc.r green:kc.g blue:kc.b alpha:1.0];
        sw.onPick = ^(NSColor *c){
            for (KakiSwatch *s in gSwatches) s.selected = NO;
            sw.selected = YES;
            for (KakiSwatch *s in gSwatches) [s setNeedsDisplay:YES];
            applyColor(kc.r, kc.g, kc.b);
        };
        [gSwatches addObject:sw];
        [bg addSubview:sw];
    }
    // "+" custom-picker cell at grid index 7 (col 3, row 1)
    NSRect addFr = NSMakeRect(gx + 3*(cell+gap), gy - 1*(cell+gap), cell, cell);
    KakiSwatch *add = [[KakiSwatch alloc] initWithFrame:addFr];
    add.isAdd = YES;
    add.onPick = ^(NSColor *c){
        for (KakiSwatch *s in gSwatches) { s.selected = NO; [s setNeedsDisplay:YES]; }
        NSColorPanel *cp = [NSColorPanel sharedColorPanel];
        [cp setTarget:nil];
        [cp orderFront:nil];
        // Observe colour changes via a one-off target set in Task 4 Step 3.
        gColorPanelKanji = gKanji; // see Step 3
        [cp setAction:@selector(kakiColorChanged:)];
        [cp setTarget:gColorObserver];
    };
    [bg addSubview:add];

    // Default selection: red.
    ((KakiSwatch *)gSwatches[0]).selected = YES;
    applyColor(kPresetColors[0].r, kPresetColors[0].g, kPresetColors[0].b);

    // Position near top-centre of the main screen.
    NSRect scr = [[NSScreen mainScreen] visibleFrame];
    NSPoint origin = NSMakePoint(NSMidX(scr) - frame.size.width/2,
                                 NSMaxY(scr) - frame.size.height - 40);
    [panel setFrameOrigin:origin];
    [panel orderFrontRegardless];
    return panel;
}

void KakiHUDSetDrawState(int on) { (void)on; /* wired in Task 5 */ }
