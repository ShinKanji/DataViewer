import SwiftUI

struct SignalSelectedListView: View {
    @Bindable var viewModel: DataViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: Constants.channelBlockSpacing) {
            SignalListSectionHeader(
                title: String(localized: "已选信号", comment: "Selected signals section header")
            )

            if viewModel.orderedNonEmptyPlotGroups.isEmpty {
                emptySelectedHint
            } else {
                chipStrip
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .channelCandidateDropDestination(viewModel: viewModel, style: .fullFrameContentShape)
        .accessibilityIdentifier("selectedListDropTarget")
    }

    private var chipStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(viewModel.plottedGroupChipItems, id: \.id) { item in
                    PlottedGroupChip(
                        title: item.title,
                        accessibilityValue: item.subtitle
                            ?? String(localized: "单信号", comment: "Single signal accessibility value"),
                        isSelected: viewModel.isPlotGroupFullySelected(item.group),
                        onToggleSelection: { viewModel.togglePlotGroupSelection(item.group) },
                        onRemove: { viewModel.removePlotGroup(item.group.id) }
                    )
                }
            }
            .padding(.vertical, 1)
        }
        .padding(.horizontal, Constants.rowHorizontalInset)
        .accessibilityIdentifier("selectedChannelChipStrip")
    }

    private var emptySelectedHint: some View {
        Text(String(localized: "点按候选信号添加，或拖放到此",
                   comment: "Empty plot channels hint"))
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Constants.rowHorizontalInset)
            .accessibilityIdentifier("selectedListEmptyDropZone")
    }
}

private struct PlottedGroupChip: View {
    let title: String
    let accessibilityValue: String
    let isSelected: Bool
    var onToggleSelection: () -> Void
    var onRemove: () -> Void

    var body: some View {
        Button(action: onToggleSelection) {
            HStack(spacing: 4) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption2.weight(.semibold))
                }
                Text(title)
                    .font(.caption)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .frame(minHeight: 32)
            .background {
                Capsule(style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.18) : Color(.secondarySystemFill))
            }
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.accentColor.opacity(0.55) : Color.clear,
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                onToggleSelection()
            } label: {
                Label(
                    isSelected
                        ? String(localized: "取消分组选择", comment: "Deselect chip for grouping")
                        : String(localized: "选择以分组", comment: "Select chip for grouping"),
                    systemImage: isSelected ? "checkmark.circle" : "checkmark.circle.fill"
                )
            }
            Button(role: .destructive, action: onRemove) {
                Label(String(localized: "从曲线移除", comment: "Remove chip from plot"),
                      systemImage: "minus.circle")
            }
        }
        .accessibilityLabel(title)
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(String(localized: "点按选择以分组；长按更多操作", comment: "Chip accessibility hint"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
