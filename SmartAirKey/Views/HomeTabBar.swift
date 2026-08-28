import SwiftUI

/// Which tab of the home screen is showing. "Profile" isn't a tab view — it's an
/// action (sign-out) — so it's not part of this enum.
enum HomeTab: Hashable {
    case home
    case house
}

/// Bottom tab bar. "Home" and "Building" switch the content above; "Profile"
/// surfaces sign-out. On iOS 26+ the bar is a top-rounded Liquid Glass sheet;
/// below iOS 26 it's a flat material with a hairline shadow.
struct HomeTabBar: View {

    @Binding var selected: HomeTab
    /// Called when the user taps "Profile".
    let onProfile: () -> Void

    var body: some View {
        HStack(alignment: .center) {
            Button { selected = .home } label: {
                item(icon: "square.stack.fill", title: L10n.string("tab.home"),
                     selected: selected == .home)
            }
            .buttonStyle(.plain)

            Spacer()

            Button { selected = .house } label: {
                item(icon: selected == .house ? "house.fill" : "house",
                     title: L10n.string("tab.house"), selected: selected == .house)
            }
            .buttonStyle(.plain)

            Spacer()

            Button(action: onProfile) {
                item(icon: "person.crop.circle", title: L10n.string("tab.profile"),
                     selected: false)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 40)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background { barBackground }
    }

    /// The bar is a top-rounded Liquid Glass sheet on iOS 26+ that bleeds into the
    /// home-indicator area; below iOS 26 it's a flat material with a hairline
    /// shadow. Same shape either way so layout is identical.
    private var barShape: some Shape {
        UnevenRoundedRectangle(topLeadingRadius: 22, topTrailingRadius: 22, style: .continuous)
    }

    @ViewBuilder
    private var barBackground: some View {
        if #available(iOS 26.0, *) {
            Color.clear
                .glassEffect(.regular, in: barShape)
                .ignoresSafeArea(edges: .bottom)
        } else {
            barShape
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: .black.opacity(0.08), radius: 10, y: -2)
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private func item(icon: String, title: String, selected: Bool) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: selected ? .semibold : .regular))
            Text(title)
                .font(.caption2.weight(selected ? .semibold : .regular))
        }
        .foregroundStyle(selected ? Color.accentColor : Color.secondary)
        .frame(minWidth: 64)
        .contentShape(Rectangle())
    }
}

#Preview {
    VStack {
        Spacer()
        HomeTabBar(selected: .constant(.home), onProfile: {})
    }
}
