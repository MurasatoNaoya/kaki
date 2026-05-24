#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>
#import "hud.h"
#import "app_bridge.h"
#include "_cgo_export.h" // go* functions

// Persimmon UI accent (柿色) — vivid sRGB so it reads true on a dark glass panel.
static NSColor *KakiAccent(void) {
    return [NSColor colorWithSRGBRed:0.945 green:0.435 blue:0.231 alpha:1.0];
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

// Glass backdrop: a light translucent sumi tint (lets the blur read through), a
// specular highlight along the top edge, and a fine bright hairline — evoking glass.
static const CGFloat kHUDRadius = 26.0;

@interface KakiBackdrop : NSView
@end
@implementation KakiBackdrop
- (void)drawRect:(NSRect)r {
    NSBezierPath *p = [NSBezierPath bezierPathWithRoundedRect:self.bounds
                                                      xRadius:kHUDRadius yRadius:kHUDRadius];
    // Light sumi tint — low alpha so the vibrancy blur shows through (glassy, not flat).
    [[NSColor colorWithSRGBRed:0.11 green:0.10 blue:0.09 alpha:0.28] set];
    [p fill];

    // Specular top highlight (light catching the top of the glass).
    [NSGraphicsContext saveGraphicsState];
    [p addClip];
    NSGradient *spec = [[NSGradient alloc] initWithColorsAndLocations:
        [NSColor colorWithSRGBRed:1 green:1 blue:1 alpha:0.12], 0.0,
        [NSColor colorWithSRGBRed:1 green:1 blue:1 alpha:0.0],  0.45,
        nil];
    [spec drawInRect:self.bounds angle:270.0]; // bright at top, fading down
    [NSGraphicsContext restoreGraphicsState];

    // Bright hairline edge.
    [[NSColor colorWithSRGBRed:1 green:1 blue:1 alpha:0.16] set];
    [p setLineWidth:1.0];
    [p stroke];
}
- (void)mouseDragged:(NSEvent *)e {
    [self.window performWindowDragWithEvent:e]; // drag the HUD by its body
}
@end

typedef struct { CGFloat r, g, b; const char *name; } KakiColor;
// Vivid sRGB presets (the pen ink uses these same components).
static const KakiColor kPresetColors[] = {
    {0.925, 0.262, 0.286, "red"},
    {0.961, 0.549, 0.122, "orange"},
    {0.969, 0.792, 0.180, "yellow"},
    {0.196, 0.745, 0.408, "green"},
    {0.200, 0.478, 0.969, "blue"},
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
    NSRect c = NSInsetRect(self.bounds, 5, 5);
    NSBezierPath *circle = [NSBezierPath bezierPathWithOvalInRect:c];
    if (self.isAdd) {
        [[NSColor colorWithSRGBRed:1 green:1 blue:1 alpha:0.32] set];
        [circle setLineWidth:1.5];
        CGFloat d[2] = {3,3}; [circle setLineDash:d count:2 phase:0];
        [circle stroke];
        NSDictionary *attr = @{ NSForegroundColorAttributeName:[NSColor colorWithSRGBRed:1 green:1 blue:1 alpha:0.6],
                                NSFontAttributeName:[NSFont systemFontOfSize:17 weight:NSFontWeightThin] };
        NSString *plus = @"+";
        NSSize sz = [plus sizeWithAttributes:attr];
        [plus drawAtPoint:NSMakePoint(NSMidX(c)-sz.width/2, NSMidY(c)-sz.height/2) withAttributes:attr];
        return;
    }
    [self.fill set];
    [circle fill];
    // Subtle top sheen on each swatch for a glassy bead look.
    [NSGraphicsContext saveGraphicsState];
    [circle addClip];
    NSGradient *sheen = [[NSGradient alloc] initWithColorsAndLocations:
        [NSColor colorWithSRGBRed:1 green:1 blue:1 alpha:0.22], 0.0,
        [NSColor colorWithSRGBRed:1 green:1 blue:1 alpha:0.0],  0.5, nil];
    [sheen drawInRect:c angle:270.0];
    [NSGraphicsContext restoreGraphicsState];

    CGFloat rr=0, gg=0, bb=0, aa=0;
    [[self.fill colorUsingColorSpace:[NSColorSpace sRGBColorSpace]]
        getRed:&rr green:&gg blue:&bb alpha:&aa];
    BOOL isWhite = (rr > 0.99 && gg > 0.99 && bb > 0.99);
    [[NSColor colorWithSRGBRed:(isWhite?0.7:1) green:(isWhite?0.7:1) blue:(isWhite?0.7:1)
                         alpha:(isWhite?0.5:0.12)] set];
    [circle setLineWidth:1.0];
    [circle stroke];

    if (self.selected) {
        NSBezierPath *ring = [NSBezierPath bezierPathWithOvalInRect:NSInsetRect(self.bounds, 1.25, 1.25)];
        [KakiAccent() set];
        [ring setLineWidth:2.5];
        [ring stroke];
    }
}
- (void)mouseDown:(NSEvent *)e { if (self.onPick) self.onPick(self.fill); }
@end

// --- Custom "+" colour-panel observer ---
static NSTextField *gColorPanelKanji = nil;

@interface KakiColorObserver : NSObject
@end
@implementation KakiColorObserver
- (void)kakiColorChanged:(NSColorPanel *)cp {
    NSColor *c = [cp.color colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
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
    NSBezierPath *bg = [NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:10 yRadius:10];
    [(self.selected ? [KakiAccent() colorWithAlphaComponent:0.22]
                    : [NSColor colorWithSRGBRed:1 green:1 blue:1 alpha:0.06]) set];
    [bg fill];
    [(self.selected ? KakiAccent() : [NSColor colorWithSRGBRed:1 green:1 blue:1 alpha:0.12]) set];
    [bg setLineWidth:1.0]; [bg stroke];
    NSRect bar = NSMakeRect(NSMidX(self.bounds)-9, NSMidY(self.bounds)-self.lineW/2, 18, self.lineW);
    NSBezierPath *line = [NSBezierPath bezierPathWithRoundedRect:bar xRadius:self.lineW/2 yRadius:self.lineW/2];
    [(self.selected ? KakiAccent() : [NSColor colorWithSRGBRed:1 green:1 blue:1 alpha:0.92]) set];
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
    NSBezierPath *bg = [NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:12 yRadius:12];
    NSColor *fill, *border, *text;
    if (self.isDraw && self.on) {
        fill = KakiAccent(); border = KakiAccent();
        text = [NSColor whiteColor];
    } else if (self.isDraw) {
        fill = [KakiAccent() colorWithAlphaComponent:0.22];
        border = [KakiAccent() colorWithAlphaComponent:0.55];
        text = [NSColor colorWithSRGBRed:0.99 green:0.78 blue:0.70 alpha:1];
    } else {
        fill = [NSColor colorWithSRGBRed:1 green:1 blue:1 alpha:0.06];
        border = [NSColor colorWithSRGBRed:1 green:1 blue:1 alpha:0.12];
        text = [NSColor colorWithSRGBRed:1 green:1 blue:1 alpha:0.92];
    }
    [fill set]; [bg fill];
    // glassy top sheen
    [NSGraphicsContext saveGraphicsState];
    [bg addClip];
    NSGradient *sheen = [[NSGradient alloc] initWithColorsAndLocations:
        [NSColor colorWithSRGBRed:1 green:1 blue:1 alpha:(self.isDraw && self.on ? 0.20 : 0.10)], 0.0,
        [NSColor colorWithSRGBRed:1 green:1 blue:1 alpha:0.0], 0.55, nil];
    [sheen drawInRect:self.bounds angle:270.0];
    [NSGraphicsContext restoreGraphicsState];
    [border set]; [bg setLineWidth:1.0]; [bg stroke];

    NSDictionary *attr = @{ NSForegroundColorAttributeName:text,
        NSFontAttributeName:[NSFont systemFontOfSize:14 weight:NSFontWeightSemibold] };
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
            a.fromValue = @0.3; a.toValue = @0.7; a.duration = 1.3;
            a.autoreverses = YES; a.repeatCount = HUGE_VALF;
            self.layer.shadowColor = KakiAccent().CGColor;
            self.layer.shadowRadius = 11; self.layer.shadowOffset = CGSizeZero;
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

@interface KakiHUDDelegate : NSObject <NSWindowDelegate>
@end
@implementation KakiHUDDelegate
- (BOOL)windowShouldClose:(NSWindow *)w { [w orderOut:nil]; return NO; }
@end
static KakiHUDDelegate *gHUDDelegate = nil;

// Helper: a borderless label with no background.
static NSTextField *KakiLabel(NSRect frame, NSFont *font, NSColor *color, NSString *text) {
    NSTextField *t = [[NSTextField alloc] initWithFrame:frame];
    [t setBezeled:NO]; [t setEditable:NO]; [t setSelectable:NO]; [t setDrawsBackground:NO];
    t.font = font; t.textColor = color; t.stringValue = text;
    return t;
}

NSPanel *KakiMakeHUD(void) {
    if (!gColorObserver) gColorObserver = [[KakiColorObserver alloc] init];

    // ---- Layout constants (bottom-left origin; no overlaps) ----
    const CGFloat W = 280, H = 308, P = 22;
    const CGFloat cell = 48, colStep = 62;            // 4 cols: x = P + col*colStep
    const CGFloat rowTop = 190, rowStep = 62;         // 2 rows: y = rowTop - row*rowStep
    const CGFloat pillY = 78,  pillH = 32, pillW = 69, pillStep = 83;
    const CGFloat btnY = 22,   btnH = 42;

    NSRect frame = NSMakeRect(0, 0, W, H);
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

    // Vibrancy (dark blur) behind the rounded glass backdrop.
    NSVisualEffectView *vfx = [[NSVisualEffectView alloc] initWithFrame:frame];
    vfx.material = NSVisualEffectMaterialHUDWindow;
    vfx.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    vfx.state = NSVisualEffectStateActive;
    vfx.wantsLayer = YES;
    vfx.layer.cornerRadius = kHUDRadius;
    vfx.layer.masksToBounds = YES;
    [panel setContentView:vfx];

    KakiBackdrop *bg = [[KakiBackdrop alloc] initWithFrame:frame];
    bg.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [vfx addSubview:bg];

    gSwatches = [NSMutableArray array];

    // --- Wordmark row (柿 kaki) ---
    gKanji = KakiLabel(NSMakeRect(P, 256, 34, 32), KakiWordmarkFont(24),
                       [NSColor whiteColor], @"柿");
    gKanji.wantsLayer = YES; // faint light hairline keeps black/white inks legible
    gKanji.layer.shadowColor = [NSColor colorWithSRGBRed:1 green:1 blue:1 alpha:0.5].CGColor;
    gKanji.layer.shadowRadius = 0.7; gKanji.layer.shadowOpacity = 1.0;
    gKanji.layer.shadowOffset = CGSizeZero;
    [bg addSubview:gKanji];
    [bg addSubview:KakiLabel(NSMakeRect(P+34, 258, 140, 26), KakiWordmarkFont(19),
                             [NSColor colorWithSRGBRed:1 green:1 blue:1 alpha:0.95], @"kaki")];

    // --- Colour grid (4 cols x 2 rows): 7 presets + "+" ---
    void (^applyColor)(CGFloat,CGFloat,CGFloat) = ^(CGFloat r, CGFloat g, CGFloat b){
        goSetColor(r, g, b, 1.0);
        gKanji.textColor = [NSColor colorWithSRGBRed:r green:g blue:b alpha:1.0];
    };
    for (int i = 0; i < kPresetCount; i++) {
        int col = i % 4, row = i / 4;
        NSRect fr = NSMakeRect(P + col*colStep, rowTop - row*rowStep, cell, cell);
        KakiSwatch *sw = [[KakiSwatch alloc] initWithFrame:fr];
        KakiColor kc = kPresetColors[i];
        sw.fill = [NSColor colorWithSRGBRed:kc.r green:kc.g blue:kc.b alpha:1.0];
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
    KakiSwatch *add = [[KakiSwatch alloc] initWithFrame:
        NSMakeRect(P + 3*colStep, rowTop - 1*rowStep, cell, cell)];
    add.isAdd = YES;
    add.onPick = ^(NSColor *c){
        for (KakiSwatch *s in gSwatches) { s.selected = NO; [s setNeedsDisplay:YES]; }
        NSColorPanel *cp = [NSColorPanel sharedColorPanel];
        gColorPanelKanji = gKanji;
        [cp setAction:@selector(kakiColorChanged:)];
        [cp setTarget:gColorObserver];
        [cp orderFront:nil];
    };
    [bg addSubview:add];

    // Default selection: red.
    ((KakiSwatch *)gSwatches[0]).selected = YES;
    applyColor(kPresetColors[0].r, kPresetColors[0].g, kPresetColors[0].b);

    // --- Width pills (thin / medium / thick = 2 / 5 / 10) ---
    gWidthPills = [NSMutableArray array];
    CGFloat widths[3] = {2, 5, 10};
    CGFloat bars[3]   = {2, 4, 8};
    for (int i = 0; i < 3; i++) {
        KakiWidthPill *pill = [[KakiWidthPill alloc] initWithFrame:
            NSMakeRect(P + i*pillStep, pillY, pillW, pillH)];
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
    KakiButton *drawBtn = [[KakiButton alloc] initWithFrame:NSMakeRect(P, btnY, 116, btnH)];
    drawBtn.title = @"Draw"; drawBtn.isDraw = YES;
    drawBtn.onClick = ^{
        int on = goToggleMode();
        ApplyDrawMode(on);
        drawBtn.on = (on != 0);
    };
    [bg addSubview:drawBtn];
    gDrawButton = drawBtn;

    KakiButton *undoBtn = [[KakiButton alloc] initWithFrame:NSMakeRect(P+116+12, btnY, 48, btnH)];
    undoBtn.title = @"↶";
    undoBtn.onClick = ^{ goUndo(); RedrawOverlay(); };
    [bg addSubview:undoBtn];

    KakiButton *clearBtn = [[KakiButton alloc] initWithFrame:NSMakeRect(P+116+12+48+12, btnY, 48, btnH)];
    clearBtn.title = @"✕";
    clearBtn.onClick = ^{ goClear(); RedrawOverlay(); };
    [bg addSubview:clearBtn];

    // Default width selection: medium (index 1).
    ((KakiWidthPill *)gWidthPills[1]).selected = YES;
    goSetWidth(5);

    // Position near top-centre of the main screen.
    NSRect scr = [[NSScreen mainScreen] visibleFrame];
    [panel setFrameOrigin:NSMakePoint(NSMidX(scr) - W/2, NSMaxY(scr) - H - 40)];
    if (!gHUDDelegate) gHUDDelegate = [[KakiHUDDelegate alloc] init];
    [panel setDelegate:gHUDDelegate];
    [panel orderFrontRegardless];
    return panel;
}
