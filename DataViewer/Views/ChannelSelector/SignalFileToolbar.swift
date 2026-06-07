import SwiftUI

struct SignalFileToolbar: View {
    @Bindable var viewModel: DataViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lastAnnouncedPhaseLabel: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Constants.sectionSpacing) {
            Text(String(localized: "数据文件", comment: "File toolbar section title"))
                .font(.headline)

            ImportFileRow(viewModel: viewModel)

            LoadingProgressRow(
                viewModel: viewModel,
                lastAnnouncedPhaseLabel: $lastAnnouncedPhaseLabel,
                reduceMotion: reduceMotion
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding([.horizontal, .bottom, .top], Constants.panelPadding)
    }
}

private struct ImportFileRow: View {
    @Bindable var viewModel: DataViewModel

    var body: some View {
        HStack(alignment: .center, spacing: Constants.controlSpacing) {
            Button(String(localized: "导入数据…", comment: "Import data button"), systemImage: "folder") {
                viewModel.requestImportData()
            }
            .glassControl(.primary)
            .accessibilityIdentifier("importDataButton")

            if let url = viewModel.dataFileURL {
                MarqueeText(text: url.lastPathComponent)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("importedFileNamesMarquee")
            }
        }
    }
}

private struct LoadingProgressRow: View {
    @Bindable var viewModel: DataViewModel
    @Binding var lastAnnouncedPhaseLabel: String?
    var reduceMotion: Bool

    var body: some View {
        if viewModel.loadingProgress != nil || viewModel.isLoading {
            HStack(alignment: .center, spacing: Constants.standardPadding) {
                if let progress = viewModel.loadingProgress {
                    LoadingProgressBar(fraction: progress.fraction)
                    Text(progress.phaseLabel)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .layoutPriority(1)
                } else if viewModel.isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .frame(minHeight: 16)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(String(localized: "数据加载", comment: "Data loading accessibility label"))
            .accessibilityValue(viewModel.loadingProgress.map { loadingAccessibilityValue(for: $0) } ?? "")
            .accessibilityIdentifier("loadingProgressStatus")
            .onChange(of: viewModel.loadingProgress?.phaseLabel) { _, newValue in
                guard let newValue, newValue != lastAnnouncedPhaseLabel else { return }
                lastAnnouncedPhaseLabel = newValue
                if !reduceMotion {
                    UIAccessibility.post(notification: .announcement, argument: newValue)
                }
            }
        }
    }

    private func loadingAccessibilityValue(for progress: LoadingProgressState) -> String {
        let percent = Int((progress.fraction * 100).rounded())
        return "\(progress.phaseLabel)，\(percent)%"
    }
}

private struct LoadingProgressBar: View {
    var fraction: Double

    var body: some View {
        let clamped = min(max(fraction, 0), 1)
        ProgressView(value: clamped, total: 1.0)
            .progressViewStyle(.linear)
            .frame(width: 96)
    }
}
