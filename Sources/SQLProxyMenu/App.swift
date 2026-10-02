import AppKit
import SwiftUI
import UserNotifications

@main
struct SQLProxyMenuApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        MenuBarExtra {
            MenuView()
                .environmentObject(model)
        } label: {
            MenuBarLabel()
                .environmentObject(model)
        }
        .menuBarExtraStyle(.window)

        Window("Adicionar instância", id: WindowID.add) {
            AddInstanceWindow()
                .environmentObject(model)
        }
        .windowResizability(.contentSize)

        Window("Logs", id: WindowID.logs) {
            LogsView()
                .environmentObject(model)
        }

        Window("Preferências", id: WindowID.prefs) {
            PreferencesView()
                .environmentObject(model)
        }
        .windowResizability(.contentSize)
    }
}

enum WindowID {
    static let add = "add"
    static let logs = "logs"
    static let prefs = "prefs"
}

struct MenuBarLabel: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let active = model.activeCount
        if model.credentialExpired && active > 0 {
            Image(systemName: "exclamationmark.triangle.fill")
        } else if active > 0 {
            HStack(spacing: 3) {
                Image(systemName: "cylinder.fill")
                Text(String(active))
            }
        } else {
            Image(systemName: "cylinder")
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Notifier.setup(delegate: self)
        Task { await AppModel.shared.bootstrap() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppModel.shared.shutdown()
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let isCredential = response.notification.request.content.categoryIdentifier == Notifier.credentialCategory
        if isCredential {
            Task { @MainActor in AppModel.shared.reauth() }
        }
        completionHandler()
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

/// Abre uma janela do app e traz para a frente (apps de barra de menu não ficam ativos sozinhos).
@MainActor
func bringToFront() {
    NSApp.activate(ignoringOtherApps: true)
}
