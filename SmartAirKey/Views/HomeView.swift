import SwiftUI

struct HomeView: View {

    @EnvironmentObject private var environment: AppEnvironment
    @StateObject var viewModel: HomeViewModel
    @State private var confirmSignOut = false
    @State private var selectedTab: HomeTab = .home

    var body: some View {
        VStack(spacing: 0) {
            HomeHeaderView()

            ScrollView {
                VStack(spacing: 16) {
                    switch selectedTab {
                    case .home:
                        SeamlessToggleCard(
                            isOn: Binding(
                                get: { viewModel.isSeamlessOn },
                                set: { viewModel.setSeamless($0) }
                            ),
                            subtitle: viewModel.seamlessSubtitle,
                            isBusy: viewModel.isSeamlessBusy,
                            onHowItWorks: { viewModel.showHowItWorks() }
                        )
                    case .house:
                        doorsSection
                    }
                }
                .padding(20)
            }
            .refreshable { await viewModel.refreshKeys() }

            HomeTabBar(selected: $selectedTab, onProfile: { confirmSignOut = true })
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .onAppear { viewModel.onAppear() }
        .overlay { successOverlay }
        .animation(.default, value: viewModel.doors.map(\.id))
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

    // MARK: "Building" tab — the intercom list with manual open (UI req. 2/9).

    @ViewBuilder
    private var doorsSection: some View {
        Text(L10n.string("doors.section"))
            .font(.headline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)

        if viewModel.doors.isEmpty {
            emptyState
        } else {
            ForEach(viewModel.doors) { door in
                DoorRowView(door: door) { viewModel.open(door) }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "door.left.hand.closed")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(L10n.string("doors.empty.title")).font(.headline)
            Text(L10n.string("doors.empty.message"))
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .card()
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
