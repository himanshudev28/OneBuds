import SwiftUI

/// Small coloured rounded-square icon, as in System Settings' sidebar.
struct SidebarIcon: View {
    let item: SidebarItem

    var body: some View {
        Image(systemName: item.symbol)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 20, height: 20)
            .background(item.tint.gradient, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .accessibilityHidden(true)
    }
}
