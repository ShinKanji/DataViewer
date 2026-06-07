import SwiftUI

enum SignalComputeOperation: String, CaseIterable, Identifiable {
    case scale
    case deriv
    case integ
    case movmean
    case dejump

    var id: String { rawValue }

    var title: String {
        switch self {
        case .scale: return String(localized: "倍率", comment: "Scale operation title")
        case .deriv: return String(localized: "求导 d/dt", comment: "Derivative operation title")
        case .integ: return String(localized: "积分 ∫dt", comment: "Integration operation title")
        case .movmean: return String(localized: "滑动平均", comment: "Moving average operation title")
        case .dejump: return String(localized: "去跳点", comment: "Jump point removal operation title")
        }
    }

    var segmentedTitle: String {
        switch self {
        case .scale:
            String(localized: "倍率", comment: "Short scale operation label for segmented control")
        case .deriv:
            String(localized: "求导", comment: "Short derivative operation label for segmented control")
        case .integ:
            String(localized: "积分", comment: "Short integration operation label for segmented control")
        case .movmean:
            String(localized: "滑动平均", comment: "Short moving average operation label for segmented control")
        case .dejump:
            String(localized: "去跳点", comment: "Short jump removal operation label for picker")
        }
    }
}

enum SignalComputePresentation {
    case sheet
    case embedded
}

struct SignalComputeSheet: View {
    @Bindable var viewModel: DataViewModel
    @Environment(\.dismiss) private var dismiss

    var presentation: SignalComputePresentation = .sheet

    @State private var operation: SignalComputeOperation = .scale
    @State private var selectedChannelID: UUID?
    @State private var multiplierText = "1"
    @State private var windowText = "10"
    @State private var jumpThresholdText = ""
    @State private var validationMessage: String?
    @State private var successMessage: String?
    @State private var operationChangeTrigger = 0

    init(viewModel: DataViewModel, presentation: SignalComputePresentation = .sheet) {
        self.viewModel = viewModel
        self.presentation = presentation
        _selectedChannelID = State(
            initialValue: Self.defaultSelectedChannelID(in: viewModel)
        )
    }

    var body: some View {
        ScrollView {
            if showsComputeUnavailable {
                ContentUnavailableView(
                    computeUnavailableTitle,
                    systemImage: "function",
                    description: Text(computeUnavailableDescription)
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 48)
            } else {
                VStack(alignment: .leading, spacing: Constants.sectionSpacing) {
                    configurationPanel
                    if operation == .scale {
                        resetPanel
                    }
                }
                .padding(20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .modifier(SignalComputeNavigationTitleModifier(presentation: presentation))
        .toolbar {
            switch presentation {
            case .sheet:
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "关闭", comment: "Close sheet button")) { dismiss() }
                        .glassControl(.toolbar)
                        .accessibilityIdentifier("signalComputeCloseButton")
                }
                ToolbarItem(placement: .confirmationAction) {
                    applyButton
                }
            case .embedded:
                ToolbarItem(placement: .confirmationAction) {
                    applyButton
                }
            }
        }
        .onChange(of: viewModel.computeSourceChannelChoices.map(\.id)) { _, _ in
            syncSelectedChannelID()
        }
        .onChange(of: operation) { _, _ in
            validationMessage = nil
            successMessage = nil
            operationChangeTrigger += 1
        }
        .sensoryFeedback(.selection, trigger: operationChangeTrigger)
    }

    private var showsComputeUnavailable: Bool {
        if operation == .dejump {
            return viewModel.jumpRemovalTargetChannelIDs().isEmpty
        }
        return viewModel.computeSourceChannelChoices.isEmpty
    }

    private var computeUnavailableTitle: String {
        if operation == .dejump {
            return String(localized: "暂无已选原始信号", comment: "No selected raw signals for jump removal")
        }
        return String(localized: "暂无可用信号", comment: "No available signals")
    }

    private var computeUnavailableDescription: String {
        if operation == .dejump {
            return String(
                localized: "请先在已选信号区添加原始信号",
                comment: "Jump removal signal selection hint"
            )
        }
        return String(
            localized: "请先在候选或已选区选择信号",
            comment: "Signal selection hint"
        )
    }

    private var applyButton: some View {
        Button(String(localized: "应用", comment: "Apply operation button")) { applyOperation() }
            .glassControl(.primary)
            .disabled(isApplyDisabled)
            .accessibilityIdentifier("signalComputeApplyButton")
    }

    private static func defaultSelectedChannelID(in viewModel: DataViewModel) -> UUID? {
        let choices = viewModel.computeSourceChannelChoices
        let preferred = viewModel.defaultComputeSourceChannelID()
        let validIDs = Set(choices.map(\.id))
        if let preferred, validIDs.contains(preferred) {
            return preferred
        }
        return choices.first?.id
    }

    private func syncSelectedChannelID() {
        let validIDs = Set(viewModel.computeSourceChannelChoices.map(\.id))
        if let selectedChannelID, validIDs.contains(selectedChannelID) {
            return
        }
        selectedChannelID = Self.defaultSelectedChannelID(in: viewModel)
    }

    private var isApplyDisabled: Bool {
        if operation == .dejump {
            return viewModel.jumpRemovalTargetChannelIDs().isEmpty
        }
        return selectedChannelID == nil || viewModel.computeSourceChannelChoices.isEmpty
    }

    private var configurationPanel: some View {
        VStack(alignment: .leading, spacing: Constants.controlSpacing) {
            Text(String(localized: "配置", comment: "Configuration section title"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: Constants.controlSpacing) {
                Text(String(localized: "运算类型", comment: "Operation type section title"))
                    .font(.headline)

                Picker(
                    String(localized: "运算类型", comment: "Operation type picker"),
                    selection: $operation
                ) {
                    ForEach(SignalComputeOperation.allCases) { item in
                        Text(item.segmentedTitle).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("signalComputeOperationPicker")
            }

            if operation == .dejump {
                dejumpTargetSummary
            } else {
                VStack(alignment: .leading, spacing: Constants.controlSpacingTight) {
                    Text(String(localized: "源信号", comment: "Source signal label"))
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.secondary)
                    Picker(String(localized: "源信号", comment: "Source signal picker"),
                           selection: $selectedChannelID) {
                        ForEach(viewModel.computeSourceChannelChoices) { descriptor in
                            Text(viewModel.plotSeriesName(for: descriptor))
                                .tag(Optional(descriptor.id))
                        }
                    }
                    .labelsHidden()
                    .accessibilityIdentifier("signalComputeChannelPicker")
                }
            }

            switch operation {
            case .scale:
                scaleParameterFields
            case .movmean:
                movingAverageParameterFields
            case .dejump:
                dejumpParameterFields
            case .deriv, .integ:
                EmptyView()
            }

            if let validationMessage {
                Text(validationMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
            if let successMessage {
                Text(successMessage)
                    .font(.callout)
                    .foregroundStyle(.green)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Constants.sectionSpacing)
        .padding(.vertical, Constants.standardPadding)
        .contentSurface(.editingPanel)
    }

    private var scaleParameterFields: some View {
        Group {
            VStack(alignment: .leading, spacing: Constants.controlSpacingTight) {
                Text(String(localized: "倍率乘数", comment: "Scale multiplier field label"))
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
                panelTextField(String(localized: "例如 3.6", comment: "Multiplier placeholder"),
                              text: $multiplierText, accessibilityID: "signalComputeMultiplierField")
                    .keyboardType(.decimalPad)
            }

            if let channelID = selectedChannelID {
                LabeledContent(String(localized: "当前倍率", comment: "Current scale value")) {
                    Text(formatScale(viewModel.effectiveScale(for: channelID)))
                        .monospacedDigit()
                }
                .font(.subheadline)
            }
        }
    }

    private var movingAverageParameterFields: some View {
        VStack(alignment: .leading, spacing: Constants.controlSpacingTight) {
            Text(String(localized: "窗口采样点数", comment: "Moving average window size label"))
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
            panelTextField(String(localized: "例如 10", comment: "Window size placeholder"),
                          text: $windowText, accessibilityID: "signalComputeWindowField")
                .keyboardType(.numberPad)
        }
    }

    private var dejumpTargetSummary: some View {
        VStack(alignment: .leading, spacing: Constants.controlSpacingTight) {
            Text(String(localized: "目标信号", comment: "Jump removal target signals label"))
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)

            let targets = viewModel.jumpRemovalTargetChannels()
            Text(
                String(
                    format: String(
                        localized: "将对 %lld 条已选原始信号去跳点",
                        comment: "Jump removal target count summary"
                    ),
                    targets.count
                )
            )
            .font(.subheadline)

            if !targets.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(targets) { descriptor in
                        Text(viewModel.plotSeriesName(for: descriptor))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .accessibilityIdentifier("signalComputeDejumpTargetList")
            }
        }
    }

    private var dejumpParameterFields: some View {
        VStack(alignment: .leading, spacing: Constants.controlSpacingTight) {
            Text(String(localized: "跳变阈值", comment: "Jump threshold field label"))
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
            panelTextField(
                String(localized: "留空为自动", comment: "Auto jump threshold placeholder"),
                text: $jumpThresholdText,
                accessibilityID: "signalComputeJumpThresholdField"
            )
            .keyboardType(.decimalPad)
        }
    }

    private func panelTextField(
        _ placeholder: String,
        text: Binding<String>,
        accessibilityID: String
    ) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background {
                RoundedRectangle(cornerRadius: Constants.textFieldCornerRadius, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            }
            .accessibilityIdentifier(accessibilityID)
    }

    private var resetPanel: some View {
        VStack(alignment: .leading, spacing: Constants.controlSpacing) {
            Text(String(localized: "重置", comment: "Reset section title"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            LiquidGlassButtonGroup {
                HStack(spacing: Constants.controlSpacingTight) {
                    Button(String(localized: "重置该通道", comment: "Reset channel scale button")) {
                        if let channelID = selectedChannelID {
                            viewModel.resetChannelScale(channelID: channelID)
                        }
                    }
                    .glassControl(.secondary, size: .compact)
                    .disabled(selectedChannelID == nil)
                    .accessibilityIdentifier("signalComputeResetChannelButton")

                    Button(String(localized: "全部重置", comment: "Reset all scales button"),
                           role: .destructive) {
                        viewModel.resetAllChannelScales()
                    }
                    .glassControl(.destructive, size: .compact)
                    .disabled(viewModel.channelValueScales.isEmpty)
                    .accessibilityIdentifier("signalComputeResetAllButton")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Constants.sectionSpacing)
        .padding(.vertical, Constants.standardPadding)
        .contentSurface(.editingPanel)
    }

    private func applyOperation() {
        validationMessage = nil
        successMessage = nil

        if operation == .dejump {
            applyDejumpOperation()
            return
        }

        guard let channelID = selectedChannelID else { return }

        switch operation {
        case .scale:
            guard let multiplier = parseDouble(multiplierText) else {
                validationMessage = String(localized: "请输入有效数字",
                                          comment: "Invalid multiplier error")
                return
            }
            viewModel.applyChannelScale(channelID: channelID, multiplier: multiplier)
            multiplierText = "1"
            successMessage = String(localized: "倍率已应用", comment: "Scale applied success")

        case .deriv:
            do {
                _ = try viewModel.registerDerivedChannel(parentID: channelID, op: .deriv)
                successMessage = String(localized: "已加入候选", comment: "Added to candidates success")
            } catch {
                validationMessage = error.localizedDescription
            }

        case .integ:
            do {
                _ = try viewModel.registerDerivedChannel(parentID: channelID, op: .integ)
                successMessage = String(localized: "已加入候选", comment: "Added to candidates success")
            } catch {
                validationMessage = error.localizedDescription
            }

        case .movmean:
            guard let window = parseInt(windowText), window >= 1 else {
                validationMessage = String(localized: "窗口必须为 ≥ 1 的整数",
                                          comment: "Invalid window size error")
                return
            }
            do {
                _ = try viewModel.registerDerivedChannel(
                    parentID: channelID,
                    op: .movmean,
                    windowSamples: window
                )
                successMessage = String(localized: "已加入候选", comment: "Added to candidates success")
            } catch {
                validationMessage = error.localizedDescription
            }

        case .dejump:
            break
        }
    }

    private func applyDejumpOperation() {
        let manualThreshold: Double?
        switch parseOptionalThreshold(jumpThresholdText) {
        case .some(let value):
            manualThreshold = value
        case nil:
            validationMessage = String(
                localized: "请输入有效正数阈值，或留空使用自动阈值",
                comment: "Invalid jump threshold error"
            )
            return
        }

        Task {
            let result = await viewModel.removeJumpPointsFromSelectedChannels(
                manualThreshold: manualThreshold
            )
            await MainActor.run {
                presentDejumpResult(result)
            }
        }
    }

    private func presentDejumpResult(_ result: JumpPointRemovalResult) {
        if result.processedCount == 0, !result.skippedUnavailable.isEmpty {
            validationMessage = String(
                localized: "无法估算跳变阈值，请尝试手动输入",
                comment: "Jump removal threshold estimation failed"
            )
            return
        }

        if result.removedTotal == 0 {
            successMessage = String(
                format: String(
                    localized: "未发现跳点（%lld 条信号）",
                    comment: "No jump points removed success"
                ),
                result.processedCount
            )
            return
        }

        successMessage = String(
            format: String(
                localized: "已剔除 %lld 个跳点（%lld 条信号）",
                comment: "Jump removal success"
            ),
            result.removedTotal,
            result.processedCount
        )
    }

    private func parseOptionalThreshold(_ text: String) -> Double?? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .some(nil) }
        guard let value = Double(trimmed), value.isFinite, value > 0 else { return nil }
        return .some(value)
    }

    private func parseDouble(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let value = Double(trimmed), value.isFinite, value != 0 else {
            return nil
        }
        return value
    }

    private func parseInt(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let value = Int(trimmed), value >= 1 else { return nil }
        return value
    }

    private func formatScale(_ scale: Double) -> String {
        String(format: "%.6g×", scale)
    }
}

private struct SignalComputeNavigationTitleModifier: ViewModifier {
    let presentation: SignalComputePresentation

    func body(content: Content) -> some View {
        if presentation == .sheet {
            content
                .navigationTitle(String(localized: "计算", comment: "Compute sheet title"))
                .navigationBarTitleDisplayMode(.inline)
        } else {
            content
        }
    }
}
