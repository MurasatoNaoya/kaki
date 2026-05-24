#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>
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
@property (nonatomic, retain) NSColor *fill;
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
    CGFloat rr=0, gg=0, bb=0, aa=0;
    [[self.fill colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]]
        getRed:&rr green:&gg blue:&bb alpha:&aa];
    BOOL isWhite = (rr > 0.99 && gg > 0.99 && bb > 0.99);
    [[NSColor colorWithCalibratedWhite:(isWhite ? 0.6 : 0.0) alpha:0.35] set];
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

static NSMutableArray *gWidthPills = nil;

@interface KakiWidthPill : NSView
@property (nonatomic) CGFloat lineW;     // visual bar thickness
@property (nonatomic) CGFloat penW;      // value passed to goSetWidth
@property (nonatomic) BOOL selected;
@property (nonatomic, copy) void (^onPick)(void);
@end
@implementation KakiWidthPill
- (void)drawRect:(NSRect)r {
    NSBezierPath *bg = [NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:11 yRadius:11];
    [(self.selected ? [KakiAccent() colorWithAlphaComponent:0.18]
                    : [NSColor colorWithCalibratedWhite:1 alpha:0.035]) set];
    [bg fill];
    [(self.selected ? KakiAccent() : [NSColor colorWithCalibratedWhite:1 alpha:0.07]) set];
    [bg setLineWidth:1.0]; [bg stroke];
    NSRect bar = NSMakeRect(NSMidX(self.bounds)-9, NSMidY(self.bounds)-self.lineW/2, 18, self.lineW);
    NSBezierPath *line = [NSBezierPath bezierPathWithRoundedRect:bar xRadius:self.lineW/2 yRadius:self.lineW/2];
    [(self.selected ? KakiAccent() : [NSColor colorWithCalibratedWhite:0.94 alpha:1]) set];
    [line fill];
}
- (void)mouseDown:(NSEvent *)e { if (self.onPick) self.onPick(); }
@end

@interface KakiButton : NSView
@property (nonatomic, copy) NSString *title;
@property (nonatomic) BOOL isDraw;       // the persimmon toggle button
@property (nonatomic) BOOL on;           // draw on/off
@property (nonatomic, copy) void (^onClick)(void);
@end
@implementation KakiButton
- (void)drawRect:(NSRect)r {
    NSBezierPath *bg = [NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:13 yRadius:13];
    NSColor *fill, *border, *text;
    if (self.isDraw && self.on) {
        fill = KakiAccent(); border = [KakiAccent() colorWithAlphaComponent:1];
        text = [NSColor whiteColor];
    } else if (self.isDraw) {
        fill = [KakiAccent() colorWithAlphaComponent:0.16];
        border = [KakiAccent() colorWithAlphaComponent:0.4];
        text = [NSColor colorWithCalibratedRed:0.96 green:0.82 blue:0.77 alpha:1];
    } else {
        fill = [NSColor colorWithCalibratedWhite:1 alpha:0.035];
        border = [NSColor colorWithCalibratedWhite:1 alpha:0.07];
        text = [NSColor colorWithCalibratedWhite:0.94 alpha:1];
    }
    [fill set]; [bg fill];
    [border set]; [bg setLineWidth:1.0]; [bg stroke];
    NSDictionary *attr = @{ NSForegroundColorAttributeName:text,
        NSFontAttributeName:[NSFont systemFontOfSize:13 weight:NSFontWeightMedium] };
    NSSize sz = [self.title sizeWithAttributes:attr];
    [self.title drawAtPoint:NSMakePoint(NSMidX(self.bounds)-sz.width/2, NSMidY(self.bounds)-sz.height/2)
              withAttributes:attr];
}
- (void)mouseDown:(NSEvent *)e { if (self.onClick) self.onClick(); }
- (void)setOn:(BOOL)on {
    _on = on;
    if (self.isDraw) {
        self.wantsLayer = YES;
        if (on) {
            CABasicAnimation *a = [CABasicAnimation animationWithKeyPath:@"shadowOpacity"];
            a.fromValue = @0.25; a.toValue = @0.6; a.duration = 1.3;
            a.autoreverses = YES; a.repeatCount = HUGE_VALF;
            self.layer.shadowColor = KakiAccent().CGColor;
            self.layer.shadowRadius = 10; self.layer.shadowOffset = CGSizeZero;
            [self.layer addAnimation:a forKey:@"pulse"];
        } else {
            [self.layer removeAnimationForKey:@"pulse"];
            self.layer.shadowOpacity = 0;
        }
    }
    [self setNeedsDisplay:YES];
}
@end

static KakiButton *gDrawButton = nil;

void KakiHUDSetDrawState(int on) {
    if (gDrawButton) gDrawButton.on = (on != 0);
}

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

    // --- Width pills (thin / medium / thick = 2 / 5 / 10) ---
    gWidthPills = [NSMutableArray array];
    CGFloat wy = 86, ww = 76, wgap = 6;
    CGFloat widths[3] = {2, 5, 10};
    CGFloat bars[3]   = {2, 4, 8};
    for (int i = 0; i < 3; i++) {
        NSRect fr = NSMakeRect(20 + i*(ww+wgap), wy, ww, 34);
        KakiWidthPill *pill = [[KakiWidthPill alloc] initWithFrame:fr];
        pill.lineW = bars[i]; pill.penW = widths[i];
        pill.onPick = ^{
            for (KakiWidthPill *p in gWidthPills) p.selected = NO;
            pill.selected = YES;
            for (KakiWidthPill *p in gWidthPills) [p setNeedsDisplay:YES];
            goSetWidth(pill.penW);
        };
        [gWidthPills addObject:pill];
        [bg addSubview:pill];
    }

    // --- Action buttons: Draw (toggle) / Undo / Clear ---
    KakiButton *drawBtn = [[KakiButton alloc] initWithFrame:NSMakeRect(20, 40, 110, 40)];
    drawBtn.title = @"Draw"; drawBtn.isDraw = YES;
    drawBtn.onClick = ^{
        int on = goToggleMode();
        ApplyDrawMode(on);
        drawBtn.on = (on != 0);
    };
    [bg addSubview:drawBtn];
    gDrawButton = drawBtn;

    KakiButton *undoBtn = [[KakiButton alloc] initWithFrame:NSMakeRect(136, 40, 52, 40)];
    undoBtn.title = @"↶";
    undoBtn.onClick = ^{ goUndo(); RedrawOverlay(); };
    [bg addSubview:undoBtn];

    KakiButton *clearBtn = [[KakiButton alloc] initWithFrame:NSMakeRect(194, 40, 54, 40)];
    clearBtn.title = @"✕";
    clearBtn.onClick = ^{ goClear(); RedrawOverlay(); };
    [bg addSubview:clearBtn];

    // Default width selection: medium (index 1).
    ((KakiWidthPill *)gWidthPills[1]).selected = YES;
    goSetWidth(5);

    // Position near top-centre of the main screen.
    NSRect scr = [[NSScreen mainScreen] visibleFrame];
    NSPoint origin = NSMakePoint(NSMidX(scr) - frame.size.width/2,
                                 NSMaxY(scr) - frame.size.height - 40);
    [panel setFrameOrigin:origin];
    [panel orderFrontRegardless];
    return panel;
}
