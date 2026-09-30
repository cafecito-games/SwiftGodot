//
//  ContainerCodable.swift
//  SwiftGodot
//
//  Codable conformances for container types:
//  VariantArray, VariantDictionary, TypedArray, TypedDictionary.
//

// MARK: - VariantArray

extension VariantArray: Encodable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        for i in 0..<Int(size()) {
            let variant = self[i]
            // A Godot nil Variant may bridge either as Swift nil or as a
            // non-nil Variant wrapper whose type is `.nil`, depending on the
            // platform ABI. Encode both representations as JSON null.
            if let variant, variant.gtype != .nil {
                try container.encode(Variant.CodableTaggedRepresentation(variant))
            } else {
                try container.encodeNil()
            }
        }
    }
}

extension VariantArray: Decodable {
    public convenience init(from decoder: Decoder) throws {
        self.init()
        var container = try decoder.unkeyedContainer()
        while !container.isAtEnd {
            if try container.decodeNil() {
                append(nil)
            } else {
                let tagged = try container.decode(Variant.CodableTaggedRepresentation.self)
                append(tagged.toVariant())
            }
        }
    }
}

// MARK: - VariantDictionary

extension VariantDictionary {
    struct CodableEntryRepresentation: Codable {
        var key: Variant.CodableTaggedRepresentation?
        var value: Variant.CodableTaggedRepresentation?
    }
}

extension VariantDictionary: Encodable {
    public func encode(to encoder: Encoder) throws {
        let allKeys = keys()
        var container = encoder.unkeyedContainer()
        for i in 0..<Int(allKeys.size()) {
            let k: Variant? = allKeys[i]
            let keyTagged: Variant.CodableTaggedRepresentation?
            if let k, k.gtype != .nil {
                keyTagged = try Variant.CodableTaggedRepresentation(k)
            } else {
                keyTagged = nil
            }
            let v: Variant? = k.flatMap { key in
                Variant(takingOver: self[key])
            }
            let valueTagged: Variant.CodableTaggedRepresentation?
            if let v, v.gtype != .nil {
                valueTagged = try Variant.CodableTaggedRepresentation(v)
            } else {
                valueTagged = nil
            }
            let entry = CodableEntryRepresentation(key: keyTagged, value: valueTagged)
            try container.encode(entry)
        }
    }
}

extension VariantDictionary: Decodable {
    public convenience init(from decoder: Decoder) throws {
        self.init()
        var container = try decoder.unkeyedContainer()
        while !container.isAtEnd {
            let entry = try container.decode(CodableEntryRepresentation.self)
            if let keyTagged = entry.key {
                let key = keyTagged.toVariant()
                if let valueTagged = entry.value {
                    self[key] = valueTagged.toVariant().toFastVariant()
                } else {
                    self[key] = nil
                }
            }
        }
    }
}

// MARK: - TypedArray

extension TypedArray: Encodable where Element: Encodable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        for i in 0..<array.count {
            try container.encode(self[i])
        }
    }
}

extension TypedArray: Decodable where Element: Decodable {
    public init(from decoder: Decoder) throws {
        self.init()
        var container = try decoder.unkeyedContainer()
        while !container.isAtEnd {
            append(try container.decode(Element.self))
        }
    }
}

// MARK: - TypedDictionary

extension TypedDictionary: Encodable where Key: Encodable, Value: Encodable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        for (key, value) in self {
            var entryContainer = container.nestedContainer(keyedBy: TypedDictionaryCodingKeys.self)
            try entryContainer.encode(key, forKey: .key)
            try entryContainer.encode(value, forKey: .value)
        }
    }
}

extension TypedDictionary: Decodable where Key: Decodable, Value: Decodable {
    public init(from decoder: Decoder) throws {
        self.init(_wrapping: VariantDictionary())
        var container = try decoder.unkeyedContainer()
        while !container.isAtEnd {
            let entryContainer = try container.nestedContainer(keyedBy: TypedDictionaryCodingKeys.self)
            let key = try entryContainer.decode(Key.self, forKey: .key)
            let value = try entryContainer.decode(Value.self, forKey: .value)
            _ = set(key: key, value: value)
        }
    }
}

private enum TypedDictionaryCodingKeys: String, CodingKey {
    case key
    case value
}
