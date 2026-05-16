//
//  ObjectExtensions.swift
//  SwiftGodot
//
//  Created by Miguel de Icaza on 11/13/25.
//

extension Object: CustomStringConvertible {
    nonisolated public var description: String {
        "\(type(of: self))(handle: \(String(describing: handle)))"
    }

    @MainActor
    public var godotDescription: String {
        toString().description
    }
}
