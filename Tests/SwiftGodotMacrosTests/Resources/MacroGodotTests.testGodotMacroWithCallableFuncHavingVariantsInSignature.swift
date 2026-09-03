private class TestNode: Node {
    func foo(variant: Variant?) -> Variant? {
        return variant
    }

    static func _mproxy_foo(pInstance: UnsafeRawPointer?, arguments: borrowing SwiftGodot.Arguments) -> SwiftGodot.FastVariant? {
        do { // safe arguments access scope
            guard let object = SwiftGodot._unwrap(self, pInstance: pInstance) else {
                SwiftGodot.GD.printErr("Error calling `foo`: failed to unwrap instance \(String(describing: pInstance))")
                return nil
            }
            let arg0 = try arguments.argument(ofType: Variant?.self, at: 0)
            return SwiftGodot._wrapCallableResult(object.foo(variant: arg0))

        } catch {
            SwiftGodot.GD.printErr("Error calling `foo`: \(error.description)")
        }

        return nil
    }
    static func _pproxy_foo(        
    _ pInstance: UnsafeMutableRawPointer?,
    _ rargs: SwiftGodot.RawArguments,
    _ returnValue: UnsafeMutableRawPointer?) {
        do { // safe arguments access scope
                    guard let object = SwiftGodot._unwrap(self, pInstance: pInstance) else {
                SwiftGodot.GD.printErr("Error calling `foo`: failed to unwrap instance \(String(describing: pInstance))")
                return
            }
        let arg0: Variant? = try rargs.fetchArgument(at: 0)
            SwiftGodot.RawReturnWriter.writeResult(returnValue, object.foo(variant: arg0)) 

        } catch {
            SwiftGodot.GD.printErr("Error calling `foo`: \(String(describing: error))")                    
        }
    }

    nonisolated override open class var classInitializer: Void {
        let _ = super.classInitializer
        SwiftGodot._assumeGodotMainActor {
            _initializeClass()
        }
    }

    private static func _initializeClass() {
        guard swiftGodotShouldInitializeClass(type: TestNode.self) else {
            return
        }
        let className = StringName("TestNode")
        if classInitializationLevel.rawValue >= ExtensionInitializationLevel.scene.rawValue {
            // ClassDB singleton is not available prior to `.scene` level
            assert(ClassDB.classExists(class: className))
        }
        SwiftGodot._registerMethod(
            className: className,
            name: "foo",
            flags: .default,
            returnValue: SwiftGodot._returnValuePropInfo(Variant?.self),
            arguments: [
                SwiftGodot._argumentPropInfo(Variant?.self, name: "variant")
            ],
            function: TestNode._mproxy_foo,
            ptrFunction: { udata, classInstance, argsPtr, retValue in
                guard let argsPtr else {
                    GD.print("Godot is not passing the arguments");
                    return
                }
                TestNode._pproxy_foo (classInstance, RawArguments(args: argsPtr), retValue)
            }

        )
    }
}
