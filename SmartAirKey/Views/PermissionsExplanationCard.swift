import SwiftUI

/// Plain-language explanation of *why* seamless access needs ongoing Bluetooth
/// and "Always" location access. Shown while seamless access is on so the
/// permission prompts don't feel arbitrary to the user.
struct PermissionsExplanationCard: View {

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label {
                Text(L10n.string("permissions.explain.title"))
                    .font(.subheadline.weight(.semibold))
            } icon: {
                Image(systemName: "lock.shield")
                    .foregroundStyle(Color.accentColor)
            }

            VStack(alignment: .leading, spacing: 10) {
                row(icon: "dot.radiowaves.left.and.right",
                    text: L10n.string("permissions.explain.bluetooth"))
                row(icon: "location.fill",
                    text: L10n.string("permissions.explain.location"))
            }

            Text(L10n.string("permissions.explain.footer"))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .card()
        .accessibilityElement(children: .combine)
    }

    private func row(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(width: 20)
                .accessibilityHidden(true)
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    PermissionsExplanationCard()
        .padding()
        .background(Color(.systemGroupedBackground))
}
