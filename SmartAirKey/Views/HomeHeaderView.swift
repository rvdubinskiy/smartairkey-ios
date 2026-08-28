import SwiftUI

/// Top header of the home screen: a home glyph, the current address (static
/// visual shell — no address switching yet), and a notifications bell.
struct HomeHeaderView: View {

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "house.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.accentColor)

            HStack(spacing: 4) {
                Text(L10n.string("home.address.placeholder"))
                    .font(.headline)
                    .foregroundStyle(.primary)
                Image(systemName: "chevron.down")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "bell")
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(.primary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    HomeHeaderView()
}
