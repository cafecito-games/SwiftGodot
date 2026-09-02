import SwiftGodot

@Godot
public final class AndroidRuntimeProbe: RefCounted {
    @Callable
    public func probe() -> String {
        #if arch(arm64)
        let abi = "arm64-v8a"
        #elseif arch(x86_64)
        let abi = "x86_64"
        #else
        let abi = "unsupported"
        #endif
        return "SWIFTGODOT_ANDROID_OK:\(abi):42"
    }
}

#initSwiftExtension(cdecl: "swiftgodot_android_test_entry", types: [AndroidRuntimeProbe.self])
