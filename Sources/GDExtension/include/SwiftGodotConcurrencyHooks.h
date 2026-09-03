//
//  SwiftGodotConcurrencyHooks.h
//
//  Trampolines for the Swift concurrency runtime hooks that bind the main actor
//  to Godot's engine thread. Only implemented on Android; see the .c file.
//

#ifndef SwiftGodotConcurrencyHooks_h
#define SwiftGodotConcurrencyHooks_h

#include <stdbool.h>

/// Installs the checkIsolated, isIsolatingCurrentContext and enqueueMainExecutor hooks.
/// Returns NULL on success, otherwise the name of the library or symbol that could not be found.
const char *swiftgodot_install_concurrency_hooks(void);

#endif /* SwiftGodotConcurrencyHooks_h */
