package games.cafecito.swiftgodot

import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin

class SwiftGodotPlugin(godot: Godot) : GodotPlugin(godot) {
    override fun getPluginName() = "SwiftGodot"

    override fun getPluginGDExtensionLibrariesPaths() =
        setOf("res://addons/SwiftGodot/SwiftGodotEmbed.gdextension")
}
