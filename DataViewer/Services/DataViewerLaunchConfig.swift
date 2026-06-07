import Foundation

enum DataViewerLaunchConfig {
    static let uiTestingArgument = "-uiTesting"
    static let testDataDirectoryKey = "TESTDATA_DIR"

    static let sampleDataFileName = "sample_timeseries.txt"

    static func uiTestDataFileURL(in directory: URL) -> URL {
        directory.appendingPathComponent(sampleDataFileName)
    }

    static var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains(uiTestingArgument)
            || ProcessInfo.processInfo.environment["UITEST_BOOTSTRAP"] == "1"
    }

    static var testDataDirectory: URL? {
        guard let path = ProcessInfo.processInfo.environment[testDataDirectoryKey], !path.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    @MainActor
    static func applyIfNeeded(to viewModel: DataViewModel) async {
        guard isUITesting, let directory = testDataDirectory else { return }
        guard FileManager.default.fileExists(atPath: directory.path) else {
            viewModel.statusMessage = String(localized: "UI 测试目录不存在", comment: "UI test directory missing error")
            return
        }
        await viewModel.bootstrapUITestFixtures(from: directory)
    }
}
