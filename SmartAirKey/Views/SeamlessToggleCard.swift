import SwiftUI

/// The "Keyless Access" card at the top of the home screen (UI req. 1): an icon
/// tile, title + plain description, the big toggle, and a link that opens the
/// "How it works" sheet.
struct SeamlessToggleCard: View {

    @Binding var isOn: Bool
    let subtitle: String
    let isBusy: Bool
    /// Opens the "How keyless access works" sheet.
    let onHowItWorks: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                iconTile

                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.string("seamless.title"))
                        .font(.headline.weight(.bold))
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                if isBusy {
                    ProgressView().controlSize(.regular)
                } else {
                    Toggle("", isOn: $isOn)
                        .labelsHidden()
                        .accessibilityLabel(L10n.string("seamless.title"))
                        .accessibilityValue(isOn
                            ? L10n.string("seamless.state.on")
                            : L10n.string("seamless.state.off"))
                        .accessibilityHint(L10n.string("seamless.accessibility.hint"))
                }
            }

            Divider()

            Button(action: onHowItWorks) {
                HStack(spacing: 4) {
                    Text(L10n.string("seamless.how_it_works"))
                        .font(.subheadline.weight(.semibold))
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                }
                .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
        }
        .card()
        .accessibilityElement(children: .contain)
    }

    private var iconTile: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.accentColor.opacity(0.14))
            .frame(width: 40, height: 40)
            .overlay(
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            )
            .accessibilityHidden(true)
    }
}

#Preview {
    VStack {
        SeamlessToggleCard(isOn: .constant(false),
                           subtitle: "Включите, чтобы двери открывались автоматически, даже если телефон лежит в сумке",
                           isBusy: false,
                           onHowItWorks: {})
        SeamlessToggleCard(isOn: .constant(true),
                           subtitle: "Двери открываются автоматически, когда вы рядом.",
                           isBusy: false,
                           onHowItWorks: {})
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}
