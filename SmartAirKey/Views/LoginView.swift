import SwiftUI

struct LoginView: View {

    @StateObject var viewModel: AuthViewModel
    @FocusState private var phoneFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    header
                    phoneField
                    footer
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .frame(maxWidth: 480)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle(L10n.string("auth.title"))
        }
        // Raise the keyboard after the sign-out transition settles, so the two
        // animations don't run at once (which felt laggy).
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { phoneFocused = true }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 96, height: 96)
                Image(systemName: "phone.badge.checkmark")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .symbolRenderingMode(.hierarchical)
            }
            .accessibilityHidden(true)

            Text(L10n.string("auth.subtitle"))
                .font(.headline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 24)
    }

    // MARK: Phone field

    private var phoneField: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                TextField("+7 (000) 000-00-00", text: phoneBinding)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
                    .focused($phoneFocused)
                    .submitLabel(.go)
                    .accessibilityLabel(L10n.string("auth.phone"))

                if viewModel.isPhoneValid {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.green)
                        .transition(.scale.combined(with: .opacity))
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(fieldBorderColor, lineWidth: phoneFocused ? 2 : 1)
            )
            .animation(.easeInOut(duration: 0.15), value: phoneFocused)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: viewModel.isPhoneValid)

            Text(fieldHintText)
                .font(.footnote)
                .foregroundStyle(fieldHintColor)
                .padding(.leading, 4)
                .accessibilityAddTraits(.isStaticText)
        }
    }

    // MARK: Footer (error + button)

    private var footer: some View {
        VStack(spacing: 16) {
            if let error = viewModel.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityAddTraits(.isStaticText)
            }

            Button {
                phoneFocused = false
                Task { await viewModel.signIn() }
            } label: {
                HStack {
                    if viewModel.isSubmitting { ProgressView().tint(.white) }
                    Text(viewModel.isSubmitting
                         ? L10n.string("auth.signing_in")
                         : L10n.string("auth.sign_in"))
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!viewModel.canSubmit)
        }
    }

    // MARK: Helpers

    private var phoneBinding: Binding<String> {
        Binding(
            get: { viewModel.phoneNumber },
            set: { viewModel.phoneNumber = PhoneNumberFormatter.format($0) }
        )
    }

    private var isPartial: Bool {
        !viewModel.phoneNumber.isEmpty
            && viewModel.phoneNumber != "+7"
            && !viewModel.isPhoneValid
    }

    private var fieldBorderColor: Color {
        if isPartial { return .red.opacity(0.7) }
        if viewModel.isPhoneValid { return .green }
        return phoneFocused ? .accentColor : Color(.separator)
    }

    private var fieldHintText: String {
        isPartial ? L10n.string("auth.phone.hint.invalid")
                  : L10n.string("auth.phone.hint")
    }

    private var fieldHintColor: Color {
        isPartial ? .red : .secondary
    }
}

#Preview {
    LoginView(viewModel: AuthViewModel(environment: AppEnvironment()))
}
