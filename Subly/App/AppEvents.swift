import Foundation
import SwiftUI

struct AppNotice: Identifiable, Equatable {
    enum Kind: Equatable {
        case info
        case warning
        case error
    }

    var id = UUID()
    var title: String
    var message: String
    var kind: Kind
}

@MainActor
final class GlobalAppState: ObservableObject {
    @Published var notice: AppNotice?

    func showNotice(title: String, message: String, kind: AppNotice.Kind = .info) {
        notice = AppNotice(title: title, message: message, kind: kind)
    }

    func clearNotice() {
        notice = nil
    }
}

enum AppEvent: Equatable {
    case subscriptionsChanged
    case statisticsInputsChanged
    case settingsChanged(AppSettingsChange)
    case dataRestored
}

@MainActor
final class AppEventCenter {
    static let didChangeNotification = Notification.Name("SublyAppEventCenterDidChange")

    private let notificationCenter: NotificationCenter

    init(notificationCenter: NotificationCenter = .default) {
        self.notificationCenter = notificationCenter
    }

    var publisher: NotificationCenter.Publisher {
        notificationCenter.publisher(for: Self.didChangeNotification)
    }

    func post(_ event: AppEvent) {
        notificationCenter.post(
            name: Self.didChangeNotification,
            object: self,
            userInfo: ["event": event]
        )
    }
}
