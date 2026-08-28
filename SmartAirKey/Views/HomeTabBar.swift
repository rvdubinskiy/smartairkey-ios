import SwiftUI

/// Bottom tab bar — a visual shell matching the design (Home / Building /
/// Profile). Only "Home" is active; the other tabs aren't wired to real screens
/// yet. "Profile" is the one functional affordance: it surfaces sign-out, which
/// otherwise has no home now that the door list (and its toolbar) is gone.
struct HomeTabBar: View {

    /// Called when the user taps "Profile" (the only wired tab for now).
    let onProfile: () -> Void

    var body: some View {
        HStack(alignment: .center) {
            item(icon: "square.stack.fill", title: L10n.string("tab.home"), selected: true)
            Spacer()
            item(icon: "house", title: L10n.string("tab.house"), selected: false)
            Spacer()
            Button(action: onProfile) {
                item(icon: "person.crop.circle", title: L10n.string("tab.profile"), selected: false)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 40)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(
            Color(.secondarySystemGroupedBackground)
                .ignoresSafeArea(edges: .bottom)
                .shadow(color: .black.opacity(0.06), radius: 8, y: -2)
        )
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
    }
}

#Preview {
    VStack {
        Spacer()
        HomeTabBar(onProfile: {})
    }
}
