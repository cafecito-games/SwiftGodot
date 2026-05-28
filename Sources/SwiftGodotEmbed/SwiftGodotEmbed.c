// SwiftGodotEmbed is a no-op GDExtension whose only purpose is to be a
// registered GDExtension in the SwiftGodot Godot addon. The accompanying
// SwiftGodotEmbed.gdextension lists SwiftGodot under `[dependencies]`, which
// is what tells Godot's iOS / macOS exporters to embed SwiftGodot.framework
// into the exported app exactly once.
//
// The shim deliberately:
//   - Registers no Godot classes.
//   - Does not link against SwiftGodot. (If it did, SwiftPM would
//     statically link the entire SwiftGodot module into this binary,
//     producing a ~33 MB duplicate of SwiftGodot per platform slice.)
//   - Performs no work in its initialize / deinitialize callbacks.
//     SwiftGodot's runtime is initialized independently by whichever
//     consumer GDExtension(s) actually use it.
//
// The entry point still has to fully populate the GDExtensionInitialization
// struct Godot hands in: returning 1 without setting the initialize and
// deinitialize callbacks leaves them null, which causes Godot to log
//
//   initialize_library: Parameter "initialization.initialize" is null.
//
// once per init-level transition (CORE -> SCENE -> EDITOR) on every client
// start. The struct layout is duplicated inline so this stays a standalone C
// target with no dependency on the GDExtensionC headers target.

#include <stddef.h>
#include <stdint.h>

typedef enum {
    GDEXTENSION_INITIALIZATION_CORE = 0,
    GDEXTENSION_INITIALIZATION_SERVERS = 1,
    GDEXTENSION_INITIALIZATION_SCENE = 2,
    GDEXTENSION_INITIALIZATION_EDITOR = 3,
} GDExtensionInitializationLevel;

typedef void (*GDExtensionInitializeCallback)(void *p_userdata, GDExtensionInitializationLevel p_level);
typedef void (*GDExtensionDeinitializeCallback)(void *p_userdata, GDExtensionInitializationLevel p_level);

typedef struct {
    GDExtensionInitializationLevel minimum_initialization_level;
    void *userdata;
    GDExtensionInitializeCallback initialize;
    GDExtensionDeinitializeCallback deinitialize;
} GDExtensionInitialization;

static void swift_godot_embed_initialize(void *userdata, GDExtensionInitializationLevel level) {
    (void)userdata;
    (void)level;
}

static void swift_godot_embed_deinitialize(void *userdata, GDExtensionInitializationLevel level) {
    (void)userdata;
    (void)level;
}

uint8_t swift_godot_embed_entry_point(void *godot_get_proc_address,
                                      void *library,
                                      void *initialization) {
    (void)godot_get_proc_address;
    (void)library;

    if (initialization == NULL) {
        return 0;
    }

    GDExtensionInitialization *init = (GDExtensionInitialization *)initialization;
    init->minimum_initialization_level = GDEXTENSION_INITIALIZATION_SCENE;
    init->userdata = NULL;
    init->initialize = swift_godot_embed_initialize;
    init->deinitialize = swift_godot_embed_deinitialize;
    return 1;
}
