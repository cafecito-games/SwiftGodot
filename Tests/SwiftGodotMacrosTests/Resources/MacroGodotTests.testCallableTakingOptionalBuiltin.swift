class MyThing: SwiftGodot.RefCounted {

    nonisolated override open class var classInitializer: Void {
        let _ = super.classInitializer
        MainActor.assumeIsolated {
            _initializeClass()
        }
    }

    private static func _initializeClass() {
        guard swiftGodotShouldInitializeClass(type: MyThing.self) else {
            return
        }
        let className = StringName("MyThing")
        if classInitializationLevel.rawValue >= ExtensionInitializationLevel.scene.rawValue {
            // ClassDB singleton is not available prior to `.scene` level
            assert(ClassDB.classExists(class: className))
        }
    }

}

class OtherThing: SwiftGodot.Node {
    func do_string(value: String?) { }

    static func _mproxy_do_string(pInstance: UnsafeRawPointer?, arguments: borrowing SwiftGodot.Arguments) -> SwiftGodot.FastVariant? {
        do { // safe arguments access scope
            guard let object = SwiftGodot._unwrap(self, pInstance: pInstance) else {
                SwiftGodot.GD.printErr("Error calling `do_string`: failed to unwrap instance \(String(describing: pInstance))")
                return nil
            }
            let arg0 = try arguments.argument(ofType: String?.self, at: 0)
            return SwiftGodot._wrapCallableResult(object.do_string(value: arg0))

        } catch {
            SwiftGodot.GD.printErr("Error calling `do_string`: \(error.description)")
        }

        return nil
    }
    static func _pproxy_do_string(        
    _ pInstance: UnsafeMutableRawPointer?,
    _ rargs: SwiftGodot.RawArguments,
    _ returnValue: UnsafeMutableRawPointer?) {
        do { // safe arguments access scope
                    guard let object = SwiftGodot._unwrap(self, pInstance: pInstance) else {
                SwiftGodot.GD.printErr("Error calling `do_string`: failed to unwrap instance \(String(describing: pInstance))")
                return
            }
        let arg0: String? = try rargs.fetchArgument(at: 0)
            SwiftGodot.RawReturnWriter.writeResult(returnValue, object.do_string(value: arg0)) 

        } catch {
            SwiftGodot.GD.printErr("Error calling `do_string`: \(String(describing: error))")                    
        }
    }

    func do_int(value: Int?) {  }

    static func _mproxy_do_int(pInstance: UnsafeRawPointer?, arguments: borrowing SwiftGodot.Arguments) -> SwiftGodot.FastVariant? {
        do { // safe arguments access scope
            guard let object = SwiftGodot._unwrap(self, pInstance: pInstance) else {
                SwiftGodot.GD.printErr("Error calling `do_int`: failed to unwrap instance \(String(describing: pInstance))")
                return nil
            }
            let arg0 = try arguments.argument(ofType: Int?.self, at: 0)
            return SwiftGodot._wrapCallableResult(object.do_int(value: arg0))

        } catch {
            SwiftGodot.GD.printErr("Error calling `do_int`: \(error.description)")
        }

        return nil
    }
    static func _pproxy_do_int(        
    _ pInstance: UnsafeMutableRawPointer?,
    _ rargs: SwiftGodot.RawArguments,
    _ returnValue: UnsafeMutableRawPointer?) {
        do { // safe arguments access scope
                    guard let object = SwiftGodot._unwrap(self, pInstance: pInstance) else {
                SwiftGodot.GD.printErr("Error calling `do_int`: failed to unwrap instance \(String(describing: pInstance))")
                return
            }
        let arg0: Int? = try rargs.fetchArgument(at: 0)
            SwiftGodot.RawReturnWriter.writeResult(returnValue, object.do_int(value: arg0)) 

        } catch {
            SwiftGodot.GD.printErr("Error calling `do_int`: \(String(describing: error))")                    
        }
    }

    func get_thing() -> MyThing? {
        return nil
    }

    static func _mproxy_get_thing(pInstance: UnsafeRawPointer?, arguments: borrowing SwiftGodot.Arguments) -> SwiftGodot.FastVariant? {
        guard let object = SwiftGodot._unwrap(self, pInstance: pInstance) else {
            SwiftGodot.GD.printErr("Error calling `get_thing`: failed to unwrap instance \(String(describing: pInstance))")
            return nil
        }
        return SwiftGodot._wrapCallableResult(object.get_thing())

    }
    static func _pproxy_get_thing(        
    _ pInstance: UnsafeMutableRawPointer?,
    _ rargs: SwiftGodot.RawArguments,
    _ returnValue: UnsafeMutableRawPointer?) {
        guard let object = SwiftGodot._unwrap(self, pInstance: pInstance) else {
            SwiftGodot.GD.printErr("Error calling `get_thing`: failed to unwrap instance \(String(describing: pInstance))")
            return
        }
        SwiftGodot.RawReturnWriter.writeResult(returnValue, object.get_thing()) 

    }

    nonisolated override open class var classInitializer: Void {
        let _ = super.classInitializer
        MainActor.assumeIsolated {
            _initializeClass()
        }
    }

    private static func _initializeClass() {
        guard swiftGodotShouldInitializeClass(type: OtherThing.self) else {
            return
        }
        let className = StringName("OtherThing")
        if classInitializationLevel.rawValue >= ExtensionInitializationLevel.scene.rawValue {
            // ClassDB singleton is not available prior to `.scene` level
            assert(ClassDB.classExists(class: className))
        }
        SwiftGodot._registerMethod(
            className: className,
            name: "do_string",
            flags: .default,
            returnValue: SwiftGodot._returnValuePropInfo(Swift.Void.self),
            arguments: [
                SwiftGodot._argumentPropInfo(String?.self, name: "value")
            ],
            function: OtherThing._mproxy_do_string,
            ptrFunction: { udata, classInstance, argsPtr, retValue in
                guard let argsPtr else {
                    GD.print("Godot is not passing the arguments");
                    return
                }
                OtherThing._pproxy_do_string (classInstance, RawArguments(args: argsPtr), retValue)
            }

        )
        SwiftGodot._registerMethod(
            className: className,
            name: "do_int",
            flags: .default,
            returnValue: SwiftGodot._returnValuePropInfo(Swift.Void.self),
            arguments: [
                SwiftGodot._argumentPropInfo(Int?.self, name: "value")
            ],
            function: OtherThing._mproxy_do_int,
            ptrFunction: { udata, classInstance, argsPtr, retValue in
                guard let argsPtr else {
                    GD.print("Godot is not passing the arguments");
                    return
                }
                OtherThing._pproxy_do_int (classInstance, RawArguments(args: argsPtr), retValue)
            }

        )
        SwiftGodot._registerMethod(
            className: className,
            name: "get_thing",
            flags: .default,
            returnValue: SwiftGodot._returnValuePropInfo(MyThing?.self),
            arguments: [

            ],
            function: OtherThing._mproxy_get_thing,
            ptrFunction: { udata, classInstance, argsPtr, retValue in
                guard let argsPtr else {
                    GD.print("Godot is not passing the arguments");
                    return
                }
                OtherThing._pproxy_get_thing (classInstance, RawArguments(args: argsPtr), retValue)
            }

        )
    }
}
