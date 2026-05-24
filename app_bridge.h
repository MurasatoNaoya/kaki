#ifndef KAKI_APP_BRIDGE_H
#define KAKI_APP_BRIDGE_H

// Implemented in bridge.m, called from hud.m.
void ApplyDrawMode(int on); // set overlay click-through per draw mode + front it when on
void RedrawOverlay(void);    // mark the overlay canvas for redisplay

#endif
