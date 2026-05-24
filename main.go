package main

/*
#include "bridge.h"
*/
import "C"

import "runtime"

func init() {
	// AppKit must own the main OS thread.
	runtime.LockOSThread()
}

func main() {
	C.RunApp()
}
