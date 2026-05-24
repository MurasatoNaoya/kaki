#ifndef KAKI_HUD_H
#define KAKI_HUD_H
#import <Cocoa/Cocoa.h>

// Builds the control HUD panel (positioned, ordered front) and returns it.
NSPanel *KakiMakeHUD(void);

// Updates the Draw button's visual on/off state (called when the ⌥⌘D hotkey fires).
void KakiHUDSetDrawState(int on);

#endif
