#ifndef SCREENPEN_BRIDGE_H
#define SCREENPEN_BRIDGE_H

// Go exports (goBeginStroke, goSnapshot, etc.) are declared in the
// cgo-generated _cgo_export.h, which bridge.m includes directly.

// RunApp starts the AppKit run loop and does not return until the app quits.
void RunApp(void);

#endif
