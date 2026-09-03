class Hi: Control {
    override func _hasPoint(_ point: Vector2) -> Bool { false }

    nonisolated override open class var classInitializer: Void {
        let _ = super.classInitializer
        SwiftGodot._assumeGodotMainActor {
            _initializeClass()
        }
    }

    private static func _initializeClass() {
        guard swiftGodotShouldInitializeClass(type: Hi.self) else {
            return
        }
        let className = StringName("Hi")
        if classInitializationLevel.rawValue >= ExtensionInitializationLevel.scene.rawValue {
            // ClassDB singleton is not available prior to `.scene` level
            assert(ClassDB.classExists(class: className))
        }
    }

    nonisolated override open class func implementedOverrides () -> [StringName] {
        return super.implementedOverrides () + [
            StringName("_has_point"),
        ]
    }
}
