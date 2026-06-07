import SwiftUI
import UniformTypeIdentifiers

struct ChannelSelectorView: View {
    @Bindable var viewModel: DataViewModel
    @State private var isCandidateSelectionMode = false
    @State private var lastBulkAddTrigger = 0

    private static let allowedImportTypes: [UTType] = [.plainText, .commaSeparatedText, .text]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SignalFileToolbar(viewModel: viewModel)
            ContentSectionSeparator()
            SignalBrowserView(
                viewModel: viewModel,
                isCandidateSelectionMode: $isCandidateSelectionMode
            )
            .frame(minHeight: 0, maxHeight: .infinity)
            .layoutPriority(0)
            ContentSectionSeparator()
            PlotGroupingPanel(viewModel: viewModel)
                .layoutPriority(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LiquidGlassStyleResolver.platformSidebarBackground())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { candidateSelectionToolbar }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if isCandidateSelectionMode {
                CandidateSelectionBottomBar(
                    viewModel: viewModel,
                    onCancel: cancelCandidateSelection,
                    onAdd: addSelectedCandidatesFromSelectionMode
                )
            } else if let toast = viewModel.channelActionToast {
                ChannelActionToastView(
                    toast: toast,
                    onUndo: { viewModel.undoLastChannelMutation() }
                )
                .padding(.horizontal, Constants.toolbarHorizontalInset)
                .padding(.bottom, Constants.toastBottomInset)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.channelActionToast?.id)
        .sensoryFeedback(.success, trigger: lastBulkAddTrigger)
        .fileImporter(
            isPresented: $viewModel.isShowingDataImporter,
            allowedContentTypes: Self.allowedImportTypes,
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result, handler: viewModel.handleImportedFile)
        }
    }

    @ToolbarContentBuilder
    private var candidateSelectionToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            if isCandidateSelectionMode {
                Button(String(localized: "完成", comment: "Done candidate selection button")) {
                    cancelCandidateSelection()
                }
                .accessibilityIdentifier("candidateSelectionDoneButton")
            } else if !viewModel.availableCandidates.isEmpty {
                Button(String(localized: "选择", comment: "Enter candidate selection mode button")) {
                    isCandidateSelectionMode = true
                }
                .accessibilityIdentifier("candidateSelectionModeButton")
            }
        }
    }

    private func cancelCandidateSelection() {
        isCandidateSelectionMode = false
        viewModel.selectedCandidateIDs.removeAll()
    }

    private func addSelectedCandidatesFromSelectionMode() {
        let ids = Array(viewModel.selectedCandidateIDs)
        guard viewModel.addCandidatesToPlot(ids) else { return }
        lastBulkAddTrigger += 1
        isCandidateSelectionMode = false
        viewModel.selectedCandidateIDs.removeAll()
    }

    private func handleFileImport(
        _ result: Result<[URL], Error>,
        handler: (URL) -> Void
    ) {
        switch result {
        case .success(let urls):
            if let url = urls.first {
                handler(url)
            }
        case .failure(let error):
            viewModel.errorMessage = error.localizedDescription
        }
    }
}
