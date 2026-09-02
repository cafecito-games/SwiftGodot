package games.cafecito.swiftgodot.test

import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin

class SwiftGodotAndroidTestPlugin(godot: Godot) : GodotPlugin(godot) {
    override fun getPluginName() = "SwiftGodotAndroidTest"

    override fun getPluginGDExtensionLibrariesPaths() =
        setOf("res://addons/SwiftGodotAndroidTest/SwiftGodotAndroidTest.gdextension")
}
