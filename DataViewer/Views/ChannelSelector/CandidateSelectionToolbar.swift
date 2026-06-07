import SwiftUI

struct CandidateSelectionBottomBar: View {
    @Bindable var viewModel: DataViewModel
    var onCancel: () -> Void
    var onAdd: () -> Void

    private var selectionCount: Int {
        viewModel.selectedCandidateIDs.count
    }

    var body: some View {
        HStack(spacing: Constants.controlSpacing) {
            Button(String(localized: "取消", comment: "Cancel candidate selection button"), action: onCancel)
                .glassControl(.toolbar)

            Spacer()

            Text(selectionSummary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityLabel(selectionSummary)

            Spacer()

            Button(String(localized: "添加到曲线", comment: "Add selected candidates to plot button"), action: onAdd)
                .glassControl(.primary)
                .disabled(selectionCount == 0)
                .accessibilityIdentifier("addSelectedCandidatesButton")
        }
        .padding(.horizontal, Constants.toolbarHorizontalInset)
        .padding(.vertical, Constants.toolbarVerticalInset)
        .liquidGlassToolbarBackground()
        .accessibilityIdentifier("candidateSelectionBottomBar")
    }

    private var selectionSummary: String {
        String(
            format: String(localized: "已选 %lld 项", comment: "Candidate selection count"),
            Int64(selectionCount)
        )
    }
}
