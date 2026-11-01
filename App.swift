import SwiftUI
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

@main
struct CLIProxyBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var client = ProxyClient()
    
    var menuText: String {
        if !client.isConnected {
            return "Off"
        }
        if let soonest = client.soonestCooldownSeconds, soonest > 0 {
            return "\(client.readyCount)/\(client.totalCount) • \(formatSeconds(soonest))"
        }
        return "\(client.readyCount)/\(client.totalCount)"
    }
    
    var body: some Scene {
        MenuBarExtra {
            MainView(client: client)
        } label: {
            HStack(spacing: 3) {
                Image(systemName: client.isConnected ? (client.cooldownCount > 0 ? "bolt.trianglebadge.exclamationmark.fill" : "bolt.fill") : "bolt.slash.fill")
                Text(menuText)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
            }
        }
        .menuBarExtraStyle(.window)
    }
}
