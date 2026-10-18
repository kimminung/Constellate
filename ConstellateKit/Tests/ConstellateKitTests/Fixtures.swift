import Foundation
import Testing
@testable import ConstellateKit

/// Access to the bundled fixture project (`Fixtures/MiniApp`).
enum Fixtures {
    static var miniAppURL: URL {
        get throws {
            let root = try #require(Bundle.module.url(forResource: "Fixtures", withExtension: nil))
            return root.appendingPathComponent("MiniApp", isDirectory: true)
        }
    }

    static func source(_ relativePath: String) throws -> String {
        let url = try miniAppURL.appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// 1-based line number of the first line containing `needle`.
    static func lineNumber(of needle: String, in source: String, after: Int = 0) -> Int? {
        for (i, line) in source.split(separator: "\n", omittingEmptySubsequences: false).enumerated() where i + 1 > after {
            if line.contains(needle) { return i + 1 }
        }
        return nil
    }
}
