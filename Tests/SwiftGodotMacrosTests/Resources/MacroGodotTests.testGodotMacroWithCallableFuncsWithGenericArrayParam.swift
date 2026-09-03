class MultiplierNode: Node {
    func multiply(_ integers: Array<Int>) -> Int {
        integers.reduce(into: 1) { $0 *= $1 }
    }

    static func _mproxy_multiply(pInstance: UnsafeRawPointer?, arguments: borrowing SwiftGodot.Arguments) -> SwiftGodot.FastVariant? {
        do { // safe arguments access scope
            guard let object = SwiftGodot._unwrap(self, pInstance: pInstance) else {
                SwiftGodot.GD.printErr("Error calling `multiply`: failed to unwrap instance \(String(describing: pInstance))")
                return nil
            }
            let arg0 = try arguments.argument(ofType: Array<Int>.self, at: 0)
            return SwiftGodot._wrapCallableResult(object.multiply(arg0))

        } catch {
            SwiftGodot.GD.printErr("Error calling `multiply`: \(error.description)")
        }

        return nil
    }
    static func _pproxy_multiply(        
    _ pInstance: UnsafeMutableRawPointer?,
    _ rargs: SwiftGodot.RawArguments,
    _ returnValue: UnsafeMutableRawPointer?) {
        do { // safe arguments access scope
                    guard let object = SwiftGodot._unwrap(self, pInstance: pInstance) else {
                SwiftGodot.GD.printErr("Error calling `multiply`: failed to unwrap instance \(String(describing: pInstance))")
                return
            }
        let arg0: Array<Int> = try rargs.fetchArgument(at: 0)
            SwiftGodot.RawReturnWriter.writeResult(returnValue, object.multiply(arg0)) 

        } catch {
            SwiftGodot.GD.printErr("Error calling `multiply`: \(String(describing: error))")                    
        }
    }

    nonisolated override open class var classInitializer: Void {
        let _ = super.classInitializer
        MainActor.assumeIsolated {
            _initializeClass()
        }
    }

    private static func _initializeClass() {
        guard swiftGodotShouldInitializeClass(type: MultiplierNode.self) else {
            return
        }
        let className = StringName("MultiplierNode")
        if classInitializationLevel.rawValue >= ExtensionInitializationLevel.scene.rawValue {
            // ClassDB singleton is not available prior to `.scene` level
            assert(ClassDB.classExists(class: className))
        }
        SwiftGodot._registerMethod(
            className: className,
            name: "multiply",
            flags: .default,
            returnValue: SwiftGodot._returnValuePropInfo(Int.self),
            arguments: [
                SwiftGodot._argumentPropInfo(Array<Int>.self, name: "integers")
            ],
            function: MultiplierNode._mproxy_multiply,
            ptrFunction: { udata, classInstance, argsPtr, retValue in
                guard let argsPtr else {
                    GD.print("Godot is not passing the arguments");
                    return
                }
                MultiplierNode._pproxy_multiply (classInstance, RawArguments(args: argsPtr), retValue)
            }

        )
    }
}
