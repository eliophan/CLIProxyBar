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
    
    var body: some Scene {
        MenuBarExtra {
            MainView(client: client)
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "cpu")
                    .font(.system(size: 11, weight: .medium))
                
                if client.isConnected {
                    if let soonest = client.soonestCooldownSeconds, soonest > 0 {
                        Text("\(client.readyCount)/\(client.totalCount) • \(formatSeconds(soonest))")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                    } else {
                        Text("\(client.readyCount)/\(client.totalCount)")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                    }
                } else {
                    Text("Offline")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                }
            }
        }
        .menuBarExtraStyle(.window)
    }
}
