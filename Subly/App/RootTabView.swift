import SwiftUI

struct RootTabView: View {
    let environment: AppEnvironment
    @ObservedObject private var appState: GlobalAppState
    @State private var selectedTab: RootTab = .home
    @State private var appSettings = AppSettings.defaults()

    init(environment: AppEnvironment) {
        self.environment = environment
        _appState = ObservedObject(wrappedValue: environment.appState)
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            homeTab
            .tabItem { Label("订阅", systemImage: "list.bullet.rectangle") }
            .tag(RootTab.home)

            NavigationStack {
                StatisticsView(viewModel: StatisticsViewModel(queryService: StatisticsQueryService(
                    subscriptions: environment.subscriptions,
                    categories: environment.categories,
                    exchangeRates: environment.exchangeRates,
                    settings: environment.settings
                )), events: environment.events)
            }
            .tabItem { Label("统计", systemImage: "chart.pie") }
            .tag(RootTab.statistics)

            NavigationStack {
                SettingsView(viewModel: SettingsViewModel(
                    repository: environment.settings,
                    exchangeRates: environment.exchangeRates,
                    exchangeRateRefresh: environment.exchangeRateRefresh,
                    backupRestore: environment.backupRestore,
                    reminderSync: environment.reminderSync,
                    events: environment.events
                ), categories: environment.categories, subscriptions: environment.subscriptions, events: environment.events)
            }
            .tabItem { Label("设置", systemImage: "gearshape") }
            .tag(RootTab.settings)
        }
        .preferredColorScheme(appSettings.followSystemAppearance ? nil : .light)
        .task {
            loadSettings()
        }
        .onReceive(environment.events.publisher) { notification in
            if let event = notification.userInfo?["event"] as? AppEvent,
               case .settingsChanged(.appearanceChanged) = event {
                loadSettings()
            }
        }
        .overlay(alignment: .top) {
            if let notice = appState.notice {
                AppNoticeBanner(notice: notice) {
                    appState.clearNotice()
                }
                .padding(.horizontal, SublySpacing.md)
                .padding(.top, SublySpacing.sm)
            }
        }
    }

    private func loadSettings() {
        if let settings = try? environment.settings.fetch() {
            appSettings = settings
        }
    }

    private var homeTab: some View {
        NavigationStack {
            HomeView(
                viewModel: HomeViewModel(
                    subscriptions: environment.subscriptions,
                    categories: environment.categories,
                    templates: environment.templates,
                    exchangeRates: environment.exchangeRates,
                    settings: environment.settings
                ),
                repository: environment.subscriptions,
                categories: environment.categories,
                templates: environment.templates,
                exchangeRates: environment.exchangeRates,
                settings: environment.settings,
                commandService: SubscriptionCommandService(
                    repository: environment.subscriptions,
                    categories: environment.categories,
                    reminderSync: environment.reminderSync,
                    events: environment.events
                ),
                events: environment.events
            ) { action in
                switch action {
                case .addSubscription:
                    selectedTab = .home
                case .viewStatistics:
                    selectedTab = .statistics
                case .backupRestore:
                    selectedTab = .settings
                }
            }
        }
    }
}

private enum RootTab: Hashable {
    case home
    case statistics
    case settings
}

private struct AppNoticeBanner: View {
    var notice: AppNotice
    var onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: SublySpacing.sm) {
            Image(systemName: systemImage)
                .foregroundStyle(foregroundColor)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(notice.title)
                    .font(.subheadline.weight(.semibold))
                Text(notice.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: SublySpacing.sm)
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(SublySpacing.md)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: SublyCornerRadius.card))
        .overlay {
            RoundedRectangle(cornerRadius: SublyCornerRadius.card)
                .stroke(foregroundColor.opacity(0.2), lineWidth: 1)
        }
        .shadow(radius: 10, y: 4)
    }

    private var systemImage: String {
        switch notice.kind {
        case .info: "info.circle"
        case .warning: "exclamationmark.triangle"
        case .error: "xmark.octagon"
        }
    }

    private var foregroundColor: Color {
        switch notice.kind {
        case .info: SublyColor.accent
        case .warning: SublyColor.warning
        case .error: SublyColor.danger
        }
    }
}
