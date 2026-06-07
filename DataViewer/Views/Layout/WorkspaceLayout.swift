import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

enum WorkspaceLayout: Equatable, Sendable {
    case tabbed
    case split

    var isTabbed: Bool { self == .tabbed }
    var isSplit: Bool { self == .split }

    var isPhoneCompact: Bool { isTabbed }
    var isWide: Bool { isSplit }

    static func current(contentSize: CGSize) -> WorkspaceLayout {
        guard contentSize.width > 0, contentSize.height > 0 else {
            return .tabbed
        }
        #if canImport(UIKit)
        // iPad 全屏横屏时两轴均为 regular，需用窗口尺寸判断横竖屏。
        if UIDevice.current.userInterfaceIdiom == .pad,
           contentSize.width > contentSize.height {
            return .split
        }
        #endif
        return .tabbed
    }
}

private struct WorkspaceLayoutKey: EnvironmentKey {
    static let defaultValue: WorkspaceLayout = .tabbed
}

extension EnvironmentValues {
    var workspaceLayout: WorkspaceLayout {
        get { self[WorkspaceLayoutKey.self] }
        set { self[WorkspaceLayoutKey.self] = newValue }
    }
}

extension View {
    func workspaceLayout(_ layout: WorkspaceLayout) -> some View {
        environment(\.workspaceLayout, layout)
    }
}

extension WorkspaceLayout {
    func select(phone: String, wide: String) -> String {
        isTabbed ? phone : wide
    }
}
