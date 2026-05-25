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

// Spatial-standard spring (M3-style motion token): stiffness 180, damping ratio ~0.8,
// mass 1. Slight overshoot, settles cleanly. Used for spatial moves like the selection ring.
static CASpringAnimation *KakiSpatialScale(CGFloat from, CGFloat to) {
    CASpringAnimation *a = [CASpringAnimation animationWithKeyPath:@"transform.scale"];
    a.mass = 1.0; a.stiffness = 180.0; a.damping = 21.5; a.initialVelocity = 0.0;
    a.fromValue = @(from); a.toValue = @(to);
    a.duration = a.settlingDuration;
    return a;
}

// Spatial-standard spring on layer position (same token as KakiSpatialScale:
// stiffness 180, damping 21.5, mass 1). Used to glide the width indicator.
static CASpringAnimation *KakiSpatialPosition(CGPoint from, CGPoint to) {
    CASpringAnimation *a = [CASpringAnimation animationWithKeyPath:@"position"];
    a.mass = 1.0; a.stiffness = 180.0; a.damping = 21.5; a.initialVelocity = 0.0;
    a.fromValue = [NSValue valueWithPoint:NSPointFromCGPoint(from)];
    a.toValue = [NSValue valueWithPoint:NSPointFromCGPoint(to)];
    a.duration = a.settlingDuration;
    return a;
}

// Effect token (colour/opacity): a short ease-in-ease-out cross-fade with NO
// overshoot. Adds a fade CATransition to the view's backing layer so the next
// redraw dissolves in. Honours Reduce Motion (caller should still set final state).
static void KakiEffectFade(NSView *v, CGFloat dur) {
    if (!v) return;
    if ([[NSWorkspace sharedWorkspace] accessibilityDisplayShouldReduceMotion]) return;
    v.wantsLayer = YES;
    CATransition *t = [CATransition animation];
    t.type = kCATransitionFade;
    t.duration = dur;
    t.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [v.layer addAnimation:t forKey:@"kakiEffectFade"];
}

// Content container layered over the Liquid Glass surface. The glass itself
// supplies the translucency, refraction and edge lighting, so this view stays
// transparent — only a whisper-fine hairline to crisp the rounded edge.
static const CGFloat kHUDRadius = 16.0;

@interface KakiBackdrop : NSView
@end
@implementation KakiBackdrop
- (void)drawRect:(NSRect)r {
    // Fully transparent: no fill, no hairline. The clear glass surface is the
    // only backdrop, so the panel reads as see-through, not a grey tile.
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
@property (nonatomic, retain) CAShapeLayer *ring;  // offset selection ring (spring-animated)
@end

@implementation KakiSwatch
- (instancetype)initWithFrame:(NSRect)f {
    if ((self = [super initWithFrame:f])) {
        self.wantsLayer = YES;
        _ring = [CAShapeLayer layer];
        _ring.frame = self.bounds;
        _ring.fillColor = NULL;
        _ring.strokeColor = KakiAccent().CGColor;
        _ring.lineWidth = 2.0;
        _ring.opacity = 0.0;          // a gap between the bead and the ring
        CGMutablePathRef p = CGPathCreateMutable();
        CGPathAddEllipseInRect(p, NULL, NSInsetRect(self.bounds, 2, 2));
        _ring.path = p; CGPathRelease(p);
        [self.layer addSublayer:_ring];
    }
    return self;
}
- (void)setSelected:(BOOL)selected {
    _selected = selected;
    if (!_ring || self.isAdd) return;
    _ring.transform = CATransform3DIdentity;
    _ring.opacity = selected ? 1.0 : 0.0;
    if ([[NSWorkspace sharedWorkspace] accessibilityDisplayShouldReduceMotion]) return;
    CABasicAnimation *o = [CABasicAnimation animationWithKeyPath:@"opacity"];
    o.duration = 0.12;
    if (selected) {
        o.fromValue = @0.0; o.toValue = @1.0;
        [_ring addAnimation:KakiSpatialScale(0.55, 1.0) forKey:@"pop"]; // spatial standard
    } else {
        o.fromValue = @1.0; o.toValue = @0.0;
    }
    [_ring addAnimation:o forKey:@"fade"];
}
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
    // Selection ring is a spring-animated sublayer (see setSelected:), not drawn here.
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
    if (gColorPanelKanji) {
        KakiEffectFade(gKanji, 0.18); // cross-fade the glyph recolour, no overshoot
        gColorPanelKanji.textColor = c;
    }
}
@end
static KakiColorObserver *gColorObserver = nil;

static NSMutableArray *gWidthPills = nil;
// Shared selection highlight that springs across to the chosen width pill.
// Sits at the bottom of the backdrop's layer, behind the pill views.
static CALayer *gWidthInd = nil;

@interface KakiWidthPill : NSView
@property (nonatomic) CGFloat lineW;     // visual bar thickness
@property (nonatomic) CGFloat penW;      // value passed to goSetWidth
@property (nonatomic) BOOL selected;
@property (nonatomic, copy) void (^onPick)(void);
@end
@implementation KakiWidthPill
- (void)drawRect:(NSRect)r {
    // The selection highlight is now the shared moving indicator layer (gWidthInd)
    // behind the pills, so each pill draws only its neutral width bar.
    NSRect bar = NSMakeRect(NSMidX(self.bounds)-9, NSMidY(self.bounds)-self.lineW/2, 18, self.lineW);
    NSBezierPath *line = [NSBezierPath bezierPathWithRoundedRect:bar xRadius:self.lineW/2 yRadius:self.lineW/2];
    [[NSColor colorWithSRGBRed:1 green:1 blue:1 alpha:0.92] set];
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
        // Effect token: cross-fade the persimmon fill instead of snapping.
        KakiEffectFade(self, 0.18);
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

// Timer-driven spatial spring for the HUD entrance. We animate the window
// frame ORIGIN (not the glass layer, which glitches the Liquid Glass effect):
// the panel starts ~28px above its target and settles down while fading in.
// Uses the spatial-standard token (k=180, c=21.5, m=1) integrated at 1/120s.
@interface KakiEntranceAnimator : NSObject
@property (nonatomic, retain) NSWindow *win;
@property (nonatomic) NSPoint target;   // final frame origin
@property (nonatomic) CGFloat offset;   // current y offset above target
@property (nonatomic) CGFloat vel;      // y-offset velocity
@property (nonatomic, retain) NSTimer *timer;
@end
@implementation KakiEntranceAnimator
- (void)start {
    self.timer = [NSTimer scheduledTimerWithTimeInterval:(1.0/120.0)
                                                  target:self selector:@selector(tick:)
                                                userInfo:nil repeats:YES];
}
- (void)tick:(NSTimer *)t {
    const CGFloat k = 180.0, c = 21.5, m = 1.0, dt = 1.0/120.0;
    // Spring toward offset 0 (target). a = (-k*x - c*v) / m.
    CGFloat a = (-k * self.offset - c * self.vel) / m;
    self.vel += a * dt;
    self.offset += self.vel * dt;
    // Ramp alpha toward 1 as the panel approaches its resting place (28px travel).
    CGFloat prog = 1.0 - fmin(1.0, fabs(self.offset) / 28.0);
    self.win.alphaValue = prog;
    [self.win setFrameOrigin:NSMakePoint(self.target.x, self.target.y + self.offset)];
    if (fabs(self.offset) < 0.3 && fabs(self.vel) < 0.3) {
        [self.win setFrameOrigin:self.target];
        self.win.alphaValue = 1.0;
        [self.timer invalidate]; self.timer = nil;
    }
}
@end
static KakiEntranceAnimator *gEntranceAnimator = nil;

// Helper: a borderless label with no background.
static NSTextField *KakiLabel(NSRect frame, NSFont *font, NSColor *color, NSString *text) {
    NSTextField *t = [[NSTextField alloc] initWithFrame:frame];
    [t setBezeled:NO]; [t setEditable:NO]; [t setSelectable:NO]; [t setDrawsBackground:NO];
    t.font = font; t.textColor = color; t.stringValue = text;
    return t;
}

NSPanel *KakiMakeHUD(void) {
    if (!gColorObserver) gColorObserver = [[KakiColorObserver alloc] init];

    // ---- Smoke Bar: one compact dark-glass row, controls grouped left to right ----
    const CGFloat H = 52, P = 14, cy = H / 2.0;
    const CGFloat sd = 24, sgap = 4;            // swatch box + gap
    const CGFloat pw = 30, ph = 26, pgap = 5;   // width pill
    const CGFloat bh = 30, dw = 58, iw = 30, cw = 24; // button heights / widths
    const CGFloat g = 8, gg = 14;               // item gap / group gap

    // First pass: place items left to right, accumulate total width.
    CGFloat x = P;
    CGFloat xWord  = x; x += 26 + g;
    CGFloat xSw    = x; x += (kPresetCount + 1) * (sd + sgap) - sgap + gg; // presets + "+"
    CGFloat xPill  = x; x += 3 * pw + 2 * pgap + gg;
    CGFloat xDraw  = x; x += dw + g;
    CGFloat xUndo  = x; x += iw + g;
    CGFloat xClear = x; x += iw + gg;
    CGFloat xClose = x; x += cw;
    const CGFloat W = x + P;

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

    // Smoke: dark-tinted Liquid Glass so the bar stays legible over bright screens.
    NSGlassEffectView *glass = [[NSGlassEffectView alloc] initWithFrame:frame];
    glass.cornerRadius = kHUDRadius;
    glass.style = NSGlassEffectViewStyleClear;
    glass.tintColor = [NSColor colorWithSRGBRed:0.05 green:0.05 blue:0.07 alpha:0.55];
    [panel setContentView:glass];

    KakiBackdrop *bg = [[KakiBackdrop alloc] initWithFrame:frame];
    bg.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    bg.wantsLayer = YES; // hosts the moving width-indicator layer
    glass.contentView = bg;

    gSwatches = [NSMutableArray array];

    // 柿 wordmark, recoloured to the active pen colour (light hairline keeps it legible).
    gKanji = KakiLabel(NSMakeRect(xWord, cy - 14, 26, 28), KakiWordmarkFont(20),
                       [NSColor whiteColor], @"柿");
    gKanji.wantsLayer = YES;
    gKanji.layer.shadowColor = [NSColor colorWithSRGBRed:1 green:1 blue:1 alpha:0.5].CGColor;
    gKanji.layer.shadowRadius = 0.7; gKanji.layer.shadowOpacity = 1.0;
    gKanji.layer.shadowOffset = CGSizeZero;
    [bg addSubview:gKanji];

    void (^applyColor)(CGFloat,CGFloat,CGFloat) = ^(CGFloat r, CGFloat gn, CGFloat b){
        goSetColor(r, gn, b, 1.0);
        KakiEffectFade(gKanji, 0.18); // cross-fade the glyph recolour, no overshoot
        gKanji.textColor = [NSColor colorWithSRGBRed:r green:gn blue:b alpha:1.0];
    };

    // Colour swatches (7 presets + custom "+"), inline.
    CGFloat sy = cy - sd / 2.0;
    for (int i = 0; i < kPresetCount; i++) {
        KakiSwatch *sw = [[KakiSwatch alloc] initWithFrame:
            NSMakeRect(xSw + i*(sd+sgap), sy, sd, sd)];
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
    KakiSwatch *add = [[KakiSwatch alloc] initWithFrame:
        NSMakeRect(xSw + kPresetCount*(sd+sgap), sy, sd, sd)];
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
    ((KakiSwatch *)gSwatches[0]).selected = YES;
    applyColor(kPresetColors[0].r, kPresetColors[0].g, kPresetColors[0].b);

    // Width pills (thin / medium / thick = 2 / 5 / 10).
    gWidthPills = [NSMutableArray array];
    CGFloat widths[3] = {2, 5, 10};
    CGFloat bars[3]   = {2, 4, 8};
    CGFloat py = cy - ph / 2.0;

    // Shared selection highlight: a persimmon-tinted rounded rect sized to one
    // pill, inserted at the bottom of the backdrop's layer so the pill views
    // (added next) sit in front of it. Positioned at the default pill (index 1).
    gWidthInd = [CALayer layer];
    gWidthInd.bounds = CGRectMake(0, 0, pw, ph);
    gWidthInd.cornerRadius = 10.0;
    gWidthInd.backgroundColor = [KakiAccent() colorWithAlphaComponent:0.22].CGColor;
    gWidthInd.borderColor = KakiAccent().CGColor;
    gWidthInd.borderWidth = 1.0;
    // Centre of pill index 1, in the backdrop's (flipped-NO) layer coordinates.
    gWidthInd.position = CGPointMake(xPill + 1*(pw+pgap) + pw/2.0, py + ph/2.0);
    [bg.layer insertSublayer:gWidthInd atIndex:0];

    for (int i = 0; i < 3; i++) {
        CGPoint centre = CGPointMake(xPill + i*(pw+pgap) + pw/2.0, py + ph/2.0);
        KakiWidthPill *pill = [[KakiWidthPill alloc] initWithFrame:
            NSMakeRect(xPill + i*(pw+pgap), py, pw, ph)];
        pill.lineW = bars[i]; pill.penW = widths[i];
        pill.onPick = ^{
            for (KakiWidthPill *p in gWidthPills) p.selected = NO;
            pill.selected = YES;
            // Spatial token: glide the shared highlight to this pill's centre.
            if (![[NSWorkspace sharedWorkspace] accessibilityDisplayShouldReduceMotion]) {
                CGPoint from = gWidthInd.position;
                [gWidthInd addAnimation:KakiSpatialPosition(from, centre) forKey:@"slide"];
            }
            gWidthInd.position = centre;
            goSetWidth(pill.penW);
        };
        [gWidthPills addObject:pill];
        [bg addSubview:pill];
    }
    ((KakiWidthPill *)gWidthPills[1]).selected = YES;
    goSetWidth(5);

    // Actions: Draw (toggle) / Undo / Clear, with distinct glyphs.
    CGFloat by = cy - bh / 2.0;
    KakiButton *drawBtn = [[KakiButton alloc] initWithFrame:NSMakeRect(xDraw, by, dw, bh)];
    drawBtn.title = @"Draw"; drawBtn.isDraw = YES;
    drawBtn.onClick = ^{ int on = goToggleMode(); ApplyDrawMode(on); drawBtn.on = (on != 0); };
    [bg addSubview:drawBtn];
    gDrawButton = drawBtn;

    KakiButton *undoBtn = [[KakiButton alloc] initWithFrame:NSMakeRect(xUndo, by, iw, bh)];
    undoBtn.title = @"↶";
    undoBtn.onClick = ^{ goUndo(); RedrawOverlay(); };
    [bg addSubview:undoBtn];

    KakiButton *clearBtn = [[KakiButton alloc] initWithFrame:NSMakeRect(xClear, by, iw, bh)];
    clearBtn.title = @"⌫";
    clearBtn.onClick = ^{ goClear(); RedrawOverlay(); };
    [bg addSubview:clearBtn];

    // Close (hides the bar; reopen from the Dock icon). Distinct from Clear's ⌫.
    KakiButton *closeBtn = [[KakiButton alloc] initWithFrame:NSMakeRect(xClose, by, cw, bh)];
    closeBtn.title = @"×";
    closeBtn.onClick = ^{ [panel orderOut:nil]; };
    [bg addSubview:closeBtn];

    // Position near top-centre of the main screen.
    NSRect scr = [[NSScreen mainScreen] visibleFrame];
    NSPoint targetOrigin = NSMakePoint(NSMidX(scr) - W/2, NSMaxY(scr) - H - 40);
    if (!gHUDDelegate) gHUDDelegate = [[KakiHUDDelegate alloc] init];
    [panel setDelegate:gHUDDelegate];

    if ([[NSWorkspace sharedWorkspace] accessibilityDisplayShouldReduceMotion]) {
        // Reduce Motion: place at target and show, no entrance animation.
        [panel setFrameOrigin:targetOrigin];
        panel.alphaValue = 1.0;
        [panel orderFrontRegardless];
    } else {
        // Entrance (spatial): start 28px above the target (screen y is up) and
        // faded out, order front, then spring the frame ORIGIN down while fading
        // in. We move the window, never the glass layer, to keep the glass clean.
        [panel setFrameOrigin:NSMakePoint(targetOrigin.x, targetOrigin.y + 28.0)];
        panel.alphaValue = 0.0;
        [panel orderFrontRegardless];
        gEntranceAnimator = [[KakiEntranceAnimator alloc] init];
        gEntranceAnimator.win = panel;
        gEntranceAnimator.target = targetOrigin;
        gEntranceAnimator.offset = 28.0;
        gEntranceAnimator.vel = 0.0;
        [gEntranceAnimator start];
    }
    return panel;
}
