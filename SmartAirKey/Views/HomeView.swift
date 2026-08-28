import SwiftUI

struct HomeView: View {

    @EnvironmentObject private var environment: AppEnvironment
    @StateObject var viewModel: HomeViewModel
    @State private var confirmSignOut = false

    var body: some View {
        VStack(spacing: 0) {
            HomeHeaderView()

            ScrollView {
                VStack(spacing: 16) {
                    SeamlessToggleCard(
                        isOn: Binding(
                            get: { viewModel.isSeamlessOn },
                            set: { viewModel.setSeamless($0) }
                        ),
                        subtitle: viewModel.seamlessSubtitle,
                        isBusy: viewModel.isSeamlessBusy,
                        onHowItWorks: { viewModel.showHowItWorks() }
                    )
                }
                .padding(20)
            }

            HomeTabBar(onProfile: { confirmSignOut = true })
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .onAppear { viewModel.onAppear() }
        .overlay { successOverlay }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: viewModel.successDoorName)
        .sheet(isPresented: $viewModel.showsHowItWorks) {
            HowItWorksSheet(viewModel: viewModel)
        }
        // The access modal is now the sheet's checklist; this alert remains only
        // for non-permission errors (e.g. a failed first key load).
        .accessErrorAlert($viewModel.activeError) { error, action in
            viewModel.perform(action, for: error)
        }
        .confirmationDialog(
            L10n.string("auth.sign_out.confirm.title"),
            isPresented: $confirmSignOut,
            titleVisibility: .visible
        ) {
            Button(L10n.string("auth.sign_out"), role: .destructive) {
                environment.signOutCleanup()
            }
            Button(L10n.string("common.cancel"), role: .cancel) {}
        } message: {
            Text(L10n.string("auth.sign_out.confirm.message"))
        }
    }

    @ViewBuilder
    private var successOverlay: some View {
        if let name = viewModel.successDoorName {
            OpenSuccessOverlay(doorName: name)
                .transition(.opacity)
        }
    }
}

#Preview {
    HomeView(viewModel: HomeViewModel(environment: AppEnvironment()))
        .environmentObject(AppEnvironment())
        .environmentObject(SessionStore())
}
