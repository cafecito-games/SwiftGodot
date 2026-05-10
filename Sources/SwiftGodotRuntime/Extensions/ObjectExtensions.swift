//
//  ObjectExtensions.swift
//  SwiftGodot
//
//  Created by Miguel de Icaza on 11/13/25.
//

extension Object: CustomStringConvertible {
    nonisolated public var description: String {
        MainActor.assumeIsolated { toString().description }
    }
}
