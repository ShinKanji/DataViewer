import SwiftUI

struct TimeCoordinateMapper {
    let domain: ClosedRange<Double>

    func xPosition(for time: Double, width: CGFloat) -> CGFloat {
        let span = max(domain.upperBound - domain.lowerBound, 0.001)
        let ratio = (time - domain.lowerBound) / span
        return CGFloat(ratio) * width
    }

    func time(for x: CGFloat, width: CGFloat) -> Double {
        let ratio = Double(min(max(x / width, 0), 1))
        return domain.lowerBound + ratio * (domain.upperBound - domain.lowerBound)
    }
}

struct Constants {
    static let cornerRadius: CGFloat = 24.0
    static let standardPadding: CGFloat = 14.0
    static let leadingContentInset: CGFloat = 26.0
    static let safeAreaPadding: CGFloat = 30.0

    static let controlSpacingTight: CGFloat = 8.0
    static let controlSpacing: CGFloat = 12.0
    static let sectionSpacing: CGFloat = 16.0
    static let toolbarHorizontalInset: CGFloat = 16.0
    static let toolbarVerticalInset: CGFloat = 12.0
    static let toastBottomInset: CGFloat = 12.0

    static let chartCornerRadius: CGFloat = 12.0
    static let gripCornerRadius: CGFloat = 9.0
    static let smallCornerRadius: CGFloat = 8.0
    static let textFieldCornerRadius: CGFloat = 6.0

    static let minRowHeight: CGFloat = 44.0
    static let rowVerticalInset: CGFloat = 8.0
    static let rowHorizontalInset: CGFloat = 14.0
    static let listSectionSpacing: CGFloat = 8.0

    static let channelBlockSpacing: CGFloat = 14.0
    static let channelBlockTitleTopPadding: CGFloat = 8.0

    static let panelPadding: CGFloat = 14.0

    static let sidebarMinWidth: CGFloat = 280.0
    static let sidebarIdealWidth: CGFloat = 320.0
    static let sidebarMaxWidth: CGFloat = 400.0

    static let plotGroupSpacing: CGFloat = 14.0

    static let glassButtonGroupSpacing: CGFloat = controlSpacingTight
    static let plotHeaderVerticalPadding: CGFloat = toolbarVerticalInset
    static let plotHeaderHorizontalPadding: CGFloat = toolbarHorizontalInset
    static let headerButtonSpacing: CGFloat = controlSpacingTight

    static let editingBackgroundStyle = Material.ultraThickMaterial
}
