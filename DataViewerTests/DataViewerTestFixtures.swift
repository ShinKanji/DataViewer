import Foundation

enum DataViewerTestFixtures {
    static func requireTestData(_ relativePath: String) throws -> URL {
        let url = testDataDirectory.appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw FixtureError.missing(relativePath)
        }
        return url
    }

    static var testDataDirectory: URL {
        if let env = ProcessInfo.processInfo.environment["TESTDATA_DIR"], !env.isEmpty {
            return URL(fileURLWithPath: env, isDirectory: true)
        }
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("testdata", isDirectory: true)
    }

    enum FixtureError: Error, CustomStringConvertible {
        case missing(String)

        var description: String {
            switch self {
            case .missing(let path): "Missing test fixture: \(path)"
            }
        }
    }
}
