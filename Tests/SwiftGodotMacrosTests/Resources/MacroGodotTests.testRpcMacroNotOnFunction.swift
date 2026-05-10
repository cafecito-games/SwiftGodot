class MultiplayerNode: Node {
    var notAFunction: Int = 0

    nonisolated override open class var classInitializer: Void {
        let _ = super.classInitializer
        MainActor.assumeIsolated {
            _initializeClass()
        }
    }

    private static func _initializeClass() {
        guard swiftGodotShouldInitializeClass(type: MultiplayerNode.self) else {
            return
        }
        let className = StringName("MultiplayerNode")
        if classInitializationLevel.rawValue >= ExtensionInitializationLevel.scene.rawValue {
            // ClassDB singleton is not available prior to `.scene` level
            assert(ClassDB.classExists(class: className))
        }
    }
}
