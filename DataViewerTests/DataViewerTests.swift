import Foundation
import Testing
@testable import DataViewer

struct DataViewerTests {

    @Test func validatesSupportedTextExtensions() throws {
        let txt = try DataViewerTestFixtures.requireTestData("sample_timeseries.txt")
        #expect(DataFileClassifier.isSupported(txt))
        let result = DataFileClassifier.validate(txt)
        if case .valid = result {
            #expect(Bool(true))
        } else {
            Issue.record("Expected valid tabular text file")
        }
    }

    @Test func rejectsUnsupportedExtension() {
        let url = URL(fileURLWithPath: "/tmp/sample.json")
        #expect(!DataFileClassifier.isSupported(url))
    }

    @Test func parsesTabularTextCatalog() throws {
        let url = try DataViewerTestFixtures.requireTestData("sample_timeseries.txt")
        let descriptors = try TabularTextParser.parseCatalog(from: url)
        #expect(descriptors.count == 2)
        #expect(descriptors.contains { $0.columnName == "Temp" })
        #expect(descriptors.contains { $0.columnName == "Pressure" })
    }

    @Test func loadsTabularTextColumn() throws {
        let url = try DataViewerTestFixtures.requireTestData("sample_timeseries.txt")
        let catalog = try TabularTextParser.parseCatalog(from: url)
        guard let temp = catalog.first(where: { $0.columnName == "Temp" }) else {
            Issue.record("Missing Temp column")
            return
        }
        let series = try TabularTextParser.loadColumn(from: url, columnIndex: temp.columnIndex)
        #expect(series.values.count == 21)
        #expect(series.values.first == 20.0)
    }

    @Test @MainActor func openDataFileLoadsCatalog() async throws {
        let vm = DataViewModel()
        let url = try DataViewerTestFixtures.requireTestData("sample_timeseries.txt")
        vm.openDataFile(url)
        await vm.loadCatalog()
        #expect(vm.dataFileURL?.lastPathComponent == "sample_timeseries.txt")
        #expect(vm.candidateChannels.count == 2)
    }
}
