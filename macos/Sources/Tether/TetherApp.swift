import AppKit
import Foundation
import SwiftUI

@main
struct TetherApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("Tether", id: MainWindow.id) {
            MainWindowView()
                .environmentObject(appDelegate.model)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1200, height: 800)

        MenuBarExtra("Tether", systemImage: "network") {
            MenuBarContentView()
                .environmentObject(appDelegate.model)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Keeps Tether alive in the menu bar when its window closes, shows a Dock icon only while a
/// window is open, and terminates the servers it owns when the app quits.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private lazy var controlServer = ControlServer { [model] request in
        await model.handle(request)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        controlServer.start()
        let center = NotificationCenter.default
        for name in [NSWindow.didBecomeMainNotification, NSWindow.willCloseNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleActivationPolicyUpdate() }
            }
        }
        scheduleActivationPolicyUpdate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task {
            await model.shutdown()
            NSApplication.shared.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    private func scheduleActivationPolicyUpdate() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let hasWindow = NSApplication.shared.windows.contains {
                $0.isVisible && $0.canBecomeMain && !($0 is NSPanel)
            }
            let policy: NSApplication.ActivationPolicy = hasWindow ? .regular : .accessory
            if NSApplication.shared.activationPolicy() != policy {
                NSApplication.shared.setActivationPolicy(policy)
                if hasWindow { NSApplication.shared.activate(ignoringOtherApps: true) }
            }
        }
    }
}
