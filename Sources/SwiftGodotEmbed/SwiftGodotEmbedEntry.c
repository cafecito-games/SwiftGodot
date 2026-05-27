#include <stdint.h>

#include "gdextension_interface.h"

// No-op GDExtension entry point.
//
// SwiftGodotEmbed exists solely so Godot's iOS/macOS exporters see a
// registered GDExtension that declares SwiftGodot under `[dependencies]`,
// which causes SwiftGodot.framework to be embedded into the exported app
// exactly once. The extension itself registers nothing.
//
// This entry point is implemented in C rather than Swift on purpose. An
// equivalent Swift implementation that delegates to SwiftGodot's
// `initializeSwiftModule` gets dead-stripped by cross-module optimization
// (the body collapses to `return 1`), leaving `r_initialization->initialize`
// unset. Godot then logs:
//
//   initialize_library: Parameter "initialization.initialize" is null.
//
// at every initialization-level transition. Implementing the entry in C
// makes the pointer writes opaque to the Swift optimizer and guarantees the
// `GDExtensionInitialization` struct is fully populated.

static void swift_godot_embed_initialize(void *userdata, GDExtensionInitializationLevel level) {
    (void)userdata;
    (void)level;
}

static void swift_godot_embed_deinitialize(void *userdata, GDExtensionInitializationLevel level) {
    (void)userdata;
    (void)level;
}

uint8_t swift_godot_embed_entry_point(
    GDExtensionInterfaceGetProcAddress p_get_proc_address,
    GDExtensionClassLibraryPtr p_library,
    GDExtensionInitialization *r_initialization
) {
    (void)p_get_proc_address;
    (void)p_library;

    if (r_initialization == 0) {
        return 0;
    }

    r_initialization->minimum_initialization_level = GDEXTENSION_INITIALIZATION_SCENE;
    r_initialization->userdata = 0;
    r_initialization->initialize = swift_godot_embed_initialize;
    r_initialization->deinitialize = swift_godot_embed_deinitialize;
    return 1;
}
