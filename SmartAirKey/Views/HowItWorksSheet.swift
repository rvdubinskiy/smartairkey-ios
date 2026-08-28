import SwiftUI

/// Bottom sheet explaining how keyless access works, with a **live** checklist of
/// the three permissions it needs. Each row shows a done/pending indicator and,
/// when iOS can't fix it with a native prompt, a "Settings" link. Native
/// permission prompts appear over this sheet while the user grants access.
struct HowItWorksSheet: View {

    @ObservedObject var viewModel: HomeViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "lock.badge.clock")
                    .font(.system(size: 44, weight: .regular))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.accentColor)
                    .padding(.top, 28)
                    .accessibilityHidden(true)

                VStack(spacing: 8) {
                    Text(L10n.string("howitworks.title"))
                        .font(.title2.weight(.bold))
                        .multilineTextAlignment(.center)
                    Text(L10n.string("howitworks.subtitle"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 4)

                checklist
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var checklist: some View {
        VStack(spacing: 0) {
            let items = viewModel.permissionChecklist
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 {
                    Divider().padding(.leading, 44)
                }
                row(item)
            }
        }
        .card()
    }

    private func row(_ item: HomeViewModel.PermissionItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            indicator(for: item.status)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(item.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let error = item.settingsError {
                    Button {
                        viewModel.perform(.openSettings, for: error)
                    } label: {
                        HStack(spacing: 3) {
                            Text(L10n.string("common.to_settings"))
                            Image(systemName: "chevron.right").font(.caption2.weight(.semibold))
                        }
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func indicator(for status: HomeViewModel.PermissionItem.Status) -> some View {
        switch status {
        case .done:
            ZStack {
                Circle().fill(Color.green.opacity(0.18)).frame(width: 24, height: 24)
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.green)
            }
            .accessibilityLabel(Text(L10n.string("seamless.state.on")))
        case .pending:
            ZStack {
                Circle().fill(Color.orange.opacity(0.18)).frame(width: 24, height: 24)
                Circle().fill(Color.orange).frame(width: 9, height: 9)
            }
            .accessibilityLabel(Text(L10n.string("seamless.state.needs_access")))
        }
    }
}
