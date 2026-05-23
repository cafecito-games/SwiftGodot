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
//   - Performs no initialization. SwiftGodot's runtime is initialized
//     independently by whichever consumer GDExtension(s) actually use it.
//
// Godot only requires the entry point to return a non-zero "initialized"
// status; the three opaque pointers are intentionally ignored.

#include <stdint.h>

uint8_t swift_godot_embed_entry_point(void *godot_get_proc_address,
                                      void *library,
                                      void *initialization) {
    (void)godot_get_proc_address;
    (void)library;
    (void)initialization;
    return 1;
}
