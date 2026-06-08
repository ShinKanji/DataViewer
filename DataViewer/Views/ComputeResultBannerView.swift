import SwiftUI

enum ComputeResultFeedbackKind: Equatable, Sendable {
    case success
    case info
    case error
}

struct ComputeResultFeedback: Identifiable, Equatable {
    let id = UUID()
    let kind: ComputeResultFeedbackKind
    let message: String
}

struct ComputeResultBannerView: View {
    let feedback: ComputeResultFeedback

    var body: some View {
        Label {
            Text(feedback.message)
                .font(.subheadline)
                .foregroundStyle(messageColor)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        } icon: {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
        }
        .padding(.horizontal, Constants.toolbarHorizontalInset)
        .padding(.vertical, Constants.toolbarVerticalInset)
        .liquidGlassFloatingPanel(cornerRadius: Constants.cornerRadius)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier("computeResultBanner")
    }

    private var iconName: String {
        switch feedback.kind {
        case .success:
            "checkmark.circle.fill"
        case .info:
            "info.circle.fill"
        case .error:
            "exclamationmark.triangle.fill"
        }
    }

    private var iconColor: Color {
        switch feedback.kind {
        case .success:
            .green
        case .info:
            .secondary
        case .error:
            .orange
        }
    }

    private var messageColor: Color {
        switch feedback.kind {
        case .success, .error:
            .primary
        case .info:
            .secondary
        }
    }

    private var accessibilityLabel: String {
        let prefix: String
        switch feedback.kind {
        case .success:
            prefix = String(localized: "成功", comment: "Success feedback accessibility prefix")
        case .info:
            prefix = String(localized: "提示", comment: "Info feedback accessibility prefix")
        case .error:
            prefix = String(localized: "错误", comment: "Error feedback accessibility prefix")
        }
        return "\(prefix)，\(feedback.message)"
    }
}
