//
//  EditorInterop.swift
//  SwiftGodot
//
//  Created by Miguel de Icaza on 12/12/25.
//
import Foundation

public class EditorInterop {
    private static func loadHelp(xmlBytes: [UInt8]) {
        if let loadHelpWithLength = gi.editor_help_load_xml_from_utf8_chars_and_len {
            xmlBytes.withUnsafeBufferPointer { buffer in
                guard let base = buffer.baseAddress else { return }
                let ptr = UnsafeRawPointer(base).bindMemory(to: CChar.self, capacity: buffer.count)
                loadHelpWithLength(ptr, Int64(buffer.count))
            }
            return
        }

        guard let loadHelp = gi.editor_help_load_xml_from_utf8_chars else {
            return
        }

        var nullTerminated = xmlBytes.map { CChar(bitPattern: $0) }
        nullTerminated.append(0)
        nullTerminated.withUnsafeBufferPointer { buffer in
            loadHelp(buffer.baseAddress)
        }
    }

    //  Gets the path to the current GDExtension library.
    public static func getLibraryPath() -> String? {
        let res = GString()
        gi.get_library_path(extensionInterface.getLibrary(), &res.content)
        return GString.stringFromGStringPtr(ptr: &res.content)
    }

    /// Adds the Godot XML documentation to the editor at runtime
    public static func loadHelp(xmlString: String) {
        GD.print("Loading from \(getLibraryPath() ?? "nil")")
        loadHelp(xmlBytes: Array(xmlString.utf8))
    }

    /// Adds the Godot XML documentation to the editor at runtime
    public static func loadHelp(buffer: [UInt8]) {
        loadHelp(xmlBytes: buffer)
    }

    /// Adds the Godot XML documentation to the editor at runtime
    static func loadHelp(fromData data: Data) {
        loadHelp(xmlBytes: [UInt8](data))
    }

    public static func loadLibraryDocs() {
        guard let basePath = getLibraryPath() else {
            return
        }
        let url = URL(fileURLWithPath: basePath)
        let parent = url.deletingLastPathComponent()
        let docs = parent.appending(components: "Resources", "doc_classes")
        if let contents = try? FileManager.default.contentsOfDirectory(at: docs, includingPropertiesForKeys: nil) {
            for file in contents {
                guard file.path().hasSuffix(".xml") else {
                    continue
                }
                if let contents = try? Data(contentsOf: file) {
                    loadHelp(fromData: contents)
                }
            }
        }
    }
}
