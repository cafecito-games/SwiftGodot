import Foundation

extension Data {

    init(url: URL) throws {
        try self.init(contentsOf: url)
    }
}
