import SwiftUI

enum EditableSecondsParser {
    static func parse(_ text: String) -> Double? {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.lowercased().hasSuffix("s") {
            trimmed = String(trimmed.dropLast()).trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }
        }
        guard let value = Double(trimmed), value.isFinite else { return nil }
        return value
    }

    static func displayText(for seconds: Double) -> String {
        "\(Int(seconds.rounded()))"
    }
}

struct EditableVisibleTimeRangeView: View {
    var start: Double
    var end: Double
    var length: Double
    var showsLength: Bool = true
    var onCommitStart: (Double) -> Void
    var onCommitEnd: (Double) -> Void

    @State private var editingEndpoint: Endpoint?
    @State private var draftText = ""
    @FocusState private var focusedEndpoint: Endpoint?

    private enum Endpoint: Hashable {
        case start
        case end
    }

    var body: some View {
        HStack(spacing: 4) {
            endpointField(.start, seconds: start, accessibilityID: "plotVisibleRangeStart")
            Text("-")
                .foregroundStyle(.secondary)
            endpointField(.end, seconds: end, accessibilityID: "plotVisibleRangeEnd")
            if showsLength {
                Text("Δt = \(Int(length.rounded()))s")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.callout)
        .monospacedDigit()
        .controlSize(.small)
        .onChange(of: start) { _, _ in cancelEditing() }
        .onChange(of: end) { _, _ in cancelEditing() }
    }

    @ViewBuilder
    private func endpointField(_ endpoint: Endpoint, seconds: Double, accessibilityID: String) -> some View {
        HStack(spacing: 0) {
            if editingEndpoint == endpoint {
                TextField("", text: $draftText)
                    .focused($focusedEndpoint, equals: endpoint)
                    .frame(width: 64)
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
                    .multilineTextAlignment(.trailing)
                    .onSubmit { commitEditing(endpoint) }
                    .accessibilityIdentifier(accessibilityID)
            } else {
                Button {
                    beginEditing(endpoint, seconds: seconds)
                } label: {
                    Text("\(EditableSecondsParser.displayText(for: seconds))s")
                }
                .glassControl(.inline, size: .compact)
                .accessibilityIdentifier(accessibilityID)
                .accessibilityHint(String(localized: "点击编辑时间", comment: "Tap to edit time hint"))
            }
            if editingEndpoint == endpoint {
                Text("s")
            }
        }
        .onChange(of: focusedEndpoint) { _, newValue in
            guard editingEndpoint == endpoint, newValue != endpoint else { return }
            commitEditing(endpoint)
        }
    }

    private func beginEditing(_ endpoint: Endpoint, seconds: Double) {
        editingEndpoint = endpoint
        draftText = EditableSecondsParser.displayText(for: seconds)
        focusedEndpoint = endpoint
    }

    private func commitEditing(_ endpoint: Endpoint) {
        guard editingEndpoint == endpoint else { return }
        defer { cancelEditing() }
        guard let parsed = EditableSecondsParser.parse(draftText) else { return }
        let rounded = parsed.rounded()
        switch endpoint {
        case .start:
            onCommitStart(rounded)
        case .end:
            onCommitEnd(rounded)
        }
    }

    private func cancelEditing() {
        editingEndpoint = nil
        draftText = ""
        focusedEndpoint = nil
    }
}
