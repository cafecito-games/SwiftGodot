@_spi(SwiftGodotRuntimePrivate) @testable import SwiftGodot

@MainActor func freeOrphanNode(_ node: Node) {
    guard node.isValid, let handle = node.handle else { return }
    guard extensionInterface.objectShouldDeinit(object: node) else { return }
    gi.object_destroy(handle)
}
