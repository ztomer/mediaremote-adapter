// Copyright (c) 2025 Jonas van den Berg
// This file is licensed under the BSD 3-Clause License.

#import "globals.h"

#import "utility/helpers.h"

static MediaRemote *s_mediaRemote = NULL;
static dispatch_queue_t s_serialdispatchQueue;

static void initGlobals() {
    s_mediaRemote = [[MediaRemote alloc] init];
    if (!s_mediaRemote) {
        fail(@"Failed to initialize MediaRemote Framework");
        return;
    }
    s_serialdispatchQueue = dispatch_queue_create(
        "mediaremote-adapter.serial-dispatch-queue", DISPATCH_QUEUE_SERIAL);
}

static void ensureGlobals() {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      initGlobals();
    });
}

MediaRemote *mra_globals_mediaRemote(void) {
    ensureGlobals();
    return s_mediaRemote;
}

dispatch_queue_t mra_globals_serialdispatchQueue(void) {
    ensureGlobals();
    return s_serialdispatchQueue;
}
