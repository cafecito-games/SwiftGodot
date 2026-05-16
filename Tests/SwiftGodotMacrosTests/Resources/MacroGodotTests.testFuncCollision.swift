class OtherThing: SwiftGodot.Node {            
    func foo(value: Int?) { }

    static func _mproxy_foo(pInstance: UnsafeRawPointer?, arguments: borrowing SwiftGodot.Arguments) -> SwiftGodot.FastVariant? {
        do { // safe arguments access scope
            guard let object = SwiftGodot._unwrap(self, pInstance: pInstance) else {
                SwiftGodot.GD.printErr("Error calling `foo`: failed to unwrap instance \(String(describing: pInstance))")
                return nil
            }
            let arg0 = try arguments.argument(ofType: Int?.self, at: 0)
            return SwiftGodot._wrapCallableResult(object.foo(value: arg0))

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
        let arg0: Int? = try rargs.fetchArgument(at: 0)
            SwiftGodot.RawReturnWriter.writeResult(returnValue, object.foo(value: arg0)) 

        } catch {
            SwiftGodot.GD.printErr("Error calling `foo`: \(String(describing: error))")                    
        }
    }

    func foo() -> MyThing? {
        return nil
    }

    static func _mproxy_foo(pInstance: UnsafeRawPointer?, arguments: borrowing SwiftGodot.Arguments) -> SwiftGodot.FastVariant? {
        guard let object = SwiftGodot._unwrap(self, pInstance: pInstance) else {
            SwiftGodot.GD.printErr("Error calling `foo`: failed to unwrap instance \(String(describing: pInstance))")
            return nil
        }
        return SwiftGodot._wrapCallableResult(object.foo())

    }
    static func _pproxy_foo(        
    _ pInstance: UnsafeMutableRawPointer?,
    _ rargs: SwiftGodot.RawArguments,
    _ returnValue: UnsafeMutableRawPointer?) {
        guard let object = SwiftGodot._unwrap(self, pInstance: pInstance) else {
            SwiftGodot.GD.printErr("Error calling `foo`: failed to unwrap instance \(String(describing: pInstance))")
            return
        }
        SwiftGodot.RawReturnWriter.writeResult(returnValue, object.foo()) 

    }
}
