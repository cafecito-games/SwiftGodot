final class MyData: Resource {

    nonisolated override public class var classInitializer: Void {
        let _ = super.classInitializer
        SwiftGodot._assumeGodotMainActor {
            _initializeClass()
        }
    }

    private static func _initializeClass() {
        guard swiftGodotShouldInitializeClass(type: MyData.self) else {
            return
        }
        let className = StringName("MyData")
        if classInitializationLevel.rawValue >= ExtensionInitializationLevel.scene.rawValue {
            // ClassDB singleton is not available prior to `.scene` level
            assert(ClassDB.classExists(class: className))
        }
    }
}
final class MyClass: Node {
    var data: MyData = .init()

    static func _mproxy_set_data(pInstance: UnsafeRawPointer?, arguments: borrowing SwiftGodot.Arguments) -> SwiftGodot.FastVariant? {
        guard let object = _unwrap(self, pInstance: pInstance) else {
            SwiftGodot.GD.printErr("Error calling setter for data: failed to unwrap instance \(String(describing: pInstance))")
            return nil
        }

        SwiftGodot._invokeSetter(arguments, "data", object.data) {
            object.data = $0
        }
        return nil
    }

    static func _mproxy_get_data(pInstance: UnsafeRawPointer?, arguments: borrowing SwiftGodot.Arguments) -> SwiftGodot.FastVariant? {
        guard let object = _unwrap(self, pInstance: pInstance) else {
            SwiftGodot.GD.printErr("Error calling getter for data: failed to unwrap instance \(String(describing: pInstance))")
            return nil
        }

        return SwiftGodot._invokeGetter(object.data)
    }

    nonisolated override public class var classInitializer: Void {
        let _ = super.classInitializer
        SwiftGodot._assumeGodotMainActor {
            _initializeClass()
        }
    }

    private static func _initializeClass() {
        guard swiftGodotShouldInitializeClass(type: MyClass.self) else {
            return
        }
        let className = StringName("MyClass")
        if classInitializationLevel.rawValue >= ExtensionInitializationLevel.scene.rawValue {
            // ClassDB singleton is not available prior to `.scene` level
            assert(ClassDB.classExists(class: className))
        }
        SwiftGodot._registerPropertyWithGetterSetter(
            className: className,
            info: SwiftGodot._propInfo(
                at: \MyClass.data,
                name: "data",
                userHint: nil,
                userHintStr: nil,
                userUsage: nil
            ),
            getterName: "get_data",
            setterName: "set_data",
            getterFunction: MyClass._mproxy_get_data,
            setterFunction: MyClass._mproxy_set_data
        )
    }
}
