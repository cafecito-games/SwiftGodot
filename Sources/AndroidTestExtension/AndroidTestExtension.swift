import SwiftGodot

@Godot
public final class AndroidRuntimeProbe: RefCounted {
    private var mainActorHopCompleted = false

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

    /// Exercises declared isolation inside the generated bindings by constructing,
    /// mutating, reading and freeing an engine object.
    @Callable(autoSnakeCase: true)
    public func probeNodeApi() -> String {
        let node = Node()
        node.name = "SwiftGodotProbe"
        let observed = String(node.name)
        node.free()
        guard observed == "SwiftGodotProbe" else {
            return "SWIFTGODOT_ANDROID_NODE_API_FAIL:\(observed)"
        }
        return "SWIFTGODOT_ANDROID_NODE_API_OK"
    }

    /// Starts a task that leaves the main actor and comes back to it. Both the initial job and
    /// the resumption are enqueued on the main executor, which the engine thread must drain.
    @Callable(autoSnakeCase: true)
    public func startMainActorHop() {
        Task {
            await Task.detached {}.value
            mainActorHopCompleted = true
        }
    }

    @Callable(autoSnakeCase: true)
    public func isMainActorHopCompleted() -> Bool {
        mainActorHopCompleted
    }
}

#initSwiftExtension(cdecl: "swiftgodot_android_test_entry", types: [AndroidRuntimeProbe.self])
