import SwiftGodot

// SwiftGodotEmbed is a no-op GDExtension whose only purpose is to force Godot's
// iOS/macOS exporters to embed SwiftGodot.framework / SwiftGodot.xcframework
// into the exported application. It registers no Godot classes.
//
// The accompanying SwiftGodotEmbed.gdextension lists SwiftGodot under
// `[dependencies]`, so downstream Swift-based GDExtensions installed alongside
// the SwiftGodot addon no longer need to declare SwiftGodot themselves. This
// avoids the duplicate-embed conflict that arises when multiple consumer
// extensions each list the same SwiftGodot path.

private func setupScene(level: ExtensionInitializationLevel) {
    // intentionally empty
}

@_cdecl("swift_godot_embed_entry_point")
public func swift_godot_embed_entry_point(
    godotGetProcAddr: OpaquePointer?,
    libraryPtr: OpaquePointer?,
    extensionPtr: OpaquePointer?
) -> UInt8 {
    guard let godotGetProcAddr, let libraryPtr, let extensionPtr else {
        return 0
    }
    initializeSwiftModule(
        godotGetProcAddr,
        libraryPtr,
        extensionPtr,
        initHook: setupScene,
        deInitHook: { _ in }
    )
    return 1
}
