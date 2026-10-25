// Copyright (c) 2025 Jonas van den Berg
// This file is licensed under the BSD 3-Clause License.

#ifndef MEDIAREMOTEADAPTER_ADAPTER_GLOBALS_H
#define MEDIAREMOTEADAPTER_ADAPTER_GLOBALS_H

#import <CoreFoundation/CoreFoundation.h>
#import <dispatch/dispatch.h>

#import "private/MediaRemote.h"

// Initialized on first use, not at load (local patch 0002): the framework is linked into host
// applications as well as loaded by the perl script, and a host must not have MediaRemote loaded,
// or the process exited, by dyld.
extern MediaRemote* mra_globals_mediaRemote(void);
extern dispatch_queue_t mra_globals_serialdispatchQueue(void);
#define g_mediaRemote (mra_globals_mediaRemote())
#define g_serialdispatchQueue (mra_globals_serialdispatchQueue())

#endif // MEDIAREMOTEADAPTER_ADAPTER_GLOBALS_H
